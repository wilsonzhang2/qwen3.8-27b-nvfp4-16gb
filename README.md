# Qwen3.8-27B NVFP4 Q5K no-MTP on a 16 GB GPU

Reproducible notes, scripts, and measured deployment data for a **physical no-MTP derivative** of a Qwen3.8-27B NVFP4/Q5K GGUF, validated on an **NVIDIA GeForce RTX 5060 Ti 16 GB** with llama.cpp.

The goal is not maximum speculative-decoding speed. The goal is to keep the complete 27B text backbone on GPU while preserving the features that matter most for a mixed local-agent workload:

- **64K shared KV cache**
- **parallel = 2** with unified KV / continuous batching
- **full-GPU text inference**
- one short, non-thinking customer-service lane kept available
- **native Qwen3.8 Vision** through a matching F16 `mmproj` kept on CPU
- practical Hermes/agent long-context operation on a single 16 GB GPU

The validated target is:

```text
Qwen3.8-27B NVFP4 Q5K
physical no-MTP
64K shared KV
P2 / unified KV
full-GPU text backbone
Q4_0 K/V cache
Qwen3.8 Vision enabled
F16 mmproj on CPU
```

> The local Flash-Attention transient-memory patch documented here is experimental. It improves startup VRAM headroom on the tested llama.cpp revision, but its saving is not permanent under large-context workloads because the CUDA pool grows to a high-water mark.

## Key measured results

| Test | Result |
|---|---:|
| 32K / P1 / full GPU decode | **25.88 tok/s** |
| 72K / P1 / full GPU decode | **25.85 tok/s** |
| 64K / P2 concurrent decode A | **24.35 tok/s** |
| 64K / P2 concurrent decode B | **24.48 tok/s** |
| Approx. combined P2 decode | **48.8 tok/s** |
| Vision text decode after preprocessing | **25.24 tok/s** |
| Qwen3.8 F16 mmproj | **927.6 MiB / 334 tensors** |
| 40,103-token MAIN + simultaneous Vision CS | **passed** |
| Combined stress-test GPU high-water | **15,718 MiB used / 172 MiB free** |

No CUDA OOM or server failure occurred in the combined 40K MAIN + simultaneous Vision customer-service stress test.

## Provenance and no-MTP rewrite

Base model metadata points to:

- `Qwen/Qwen3.8-27B`

The local source GGUF contained one embedded MTP / NextN layer. The physical rewrite produced:

| Field | Original | no-MTP |
|---|---:|---:|
| `block_count` | 65 | 64 |
| `nextn_predict_layers` | 1 | 0 |
| Highest remaining block | 64 | 63 |
| Removed MTP tensors | 15 | — |
| Removed physical size | 227.91 MiB | — |

The retained tensors are copied without requantization. Physical removal is mainly useful for producing a clean no-MTP artifact and preventing accidental MTP activation. It should **not** be interpreted as an additional 227.91 MiB runtime VRAM saving during normal no-MTP inference, because llama.cpp already skips the unused MTP tensors when MTP is disabled.

The exact rewrite utility used for this model is included at [`scripts/strip_qwen38_mtp.py`](scripts/strip_qwen38_mtp.py).

## Tested environment

| Item | Tested value |
|---|---|
| GPU | NVIDIA GeForce RTX 5060 Ti 16 GB |
| VRAM reported by `nvidia-smi` | 16,311 MiB |
| Host CPU | Intel Core i5-13600K |
| Guest OS | Ubuntu 24.04.4 LTS |
| Guest RAM | ~21 GiB |
| NVIDIA driver | 610.43.02 |
| CUDA | 13.3 |
| llama.cpp | b10435 / `9e40df63ba151d771d8b247ac4011cf203337e99` |
| CUDA architecture | SM120 |

Important build options:

```text
GGML_CUDA=ON
CMAKE_CUDA_ARCHITECTURES=120
GGML_CUDA_FA_ALL_QUANTS=ON
CMAKE_BUILD_TYPE=Release
```

## Recommended server configuration

```bash
llama-server \
  -m Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf \
  --mmproj mmproj-Qwen3.8-27B-F16.gguf \
  --no-mmproj-offload \
  -c 64000 \
  -np 2 \
  --kv-unified \
  -ngl 999 \
  --flash-attn on \
  -ctk q4_0 -ctv q4_0 \
  -b 512 -ub 64 \
  --threads 7 \
  --fit off \
  --jinja \
  --host 0.0.0.0 \
  --port 8001
```

A reusable wrapper is provided in [`scripts/run-64k-p2-vision.sh`](scripts/run-64k-p2-vision.sh).

### Why this balance

**Full GPU matters.** Earlier partial-offload tests produced only ~19.8–20.3 tok/s. Once the complete text backbone was confirmed on GPU, the same model family reached ~25.8 tok/s. For this exact 16 GB target, sacrificing one or two main blocks to CPU for a larger nominal context was not worth the decode penalty.

**64K is preferred over 80K.** 80K/P2 could be pushed only with extremely small headroom or partial CPU offload. 64K/P2/full-GPU is the better production balance.

**P2 is useful for two logical lanes.** Two simultaneous 512-token generations measured 24.35 and 24.48 tok/s, rather than each stream collapsing to half of the single-stream speed.

**Vision belongs on CPU in this memory envelope.** A matching Qwen3.8 F16 projector was generated directly from the official checkpoint with llama.cpp's remote `--mmproj` conversion path. With `--no-mmproj-offload`, the ~928 MiB projector stays in system RAM. A real image request increased GPU high-water by only about 20 MiB in the tested configuration, while text decode remained 25.24 tok/s after visual preprocessing.

## Vision projector conversion

```bash
python convert_hf_to_gguf.py \
  Qwen/Qwen3.8-27B \
  --remote \
  --mmproj \
  --outtype f16 \
  --outfile Qwen3.8-27B-F16.gguf
```

The generated file was renamed to:

```text
mmproj-Qwen3.8-27B-F16.gguf
```

Measured projector size: **927.6 MiB**, **334 tensors**.

## Suggested Hermes routing

Treat P2 as two reserved logical lanes, not two arbitrary local jobs.

**CS lane**

```text
local concurrency: 1
context ceiling: ~8K
reasoning: non-thinking / disabled
short output limit
Vision allowed
always reserve this lane
```

**MAIN lane**

```text
local concurrency: 1
normal working context: ~32K–48K
thinking allowed
larger context only when necessary
```

Extra concurrent work should queue or spill to a remote API rather than consume the reserved customer-service lane.

## Experimental transient FA patch

On upstream b10435 behavior, 64K/P2/full-GPU used approximately:

```text
15,766 MiB used
124 MiB free
```

The local transient-FA variant started at approximately:

```text
15,526 MiB used
364 MiB free
```

That is roughly **240 MiB additional startup headroom**.

However, a ~48K MAIN + ~8K CS stress test grew the CUDA pool to approximately:

```text
15,750 MiB used
140 MiB free
```

Repeating the same workload did not keep increasing VRAM. The observed behavior is consistent with allocator high-water caching rather than a per-request leak. The patch therefore changes **when** the scratch memory is committed more than it permanently changes the worst-case memory envelope.

See [`PATCH-NOTES.md`](PATCH-NOTES.md) before using it.

## Production-like combined stress test

The final validation ran:

- slot 1: ~40K-token MAIN / thinking request
- slot 0: simultaneous real-image customer-service request
- 64K unified KV
- P2
- full GPU
- CPU F16 mmproj
- no MTP

MAIN results:

```text
prompt tokens:       40,103
output tokens:       2,048
prompt processing:   382.57 tok/s
decode:              ~19.0 tok/s
```

GPU high-water:

```text
15,718 MiB used
172 MiB free
```

Both lanes completed successfully with no CUDA OOM.

## Repository contents

- [`DEPLOYMENT.md`](DEPLOYMENT.md) — concise deployment profile and measured results
- [`PATCH-NOTES.md`](PATCH-NOTES.md) — transient FA memory behavior, scope, and caveats
- [`ATTRIBUTION.md`](ATTRIBUTION.md) — provenance and redistribution notes
- [`scripts/strip_qwen38_mtp.py`](scripts/strip_qwen38_mtp.py) — physical no-MTP GGUF rewrite
- [`scripts/run-64k-p2-vision.sh`](scripts/run-64k-p2-vision.sh) — parameterized launcher
- [`systemd/qwen38-27b.service.example`](systemd/qwen38-27b.service.example) — example service unit
- [`huggingface/README.md`](huggingface/README.md) — Hugging Face-ready model card

## Scope and limitations

This is an intentionally aggressive configuration validated on one RTX 5060 Ti 16 GB system. Results can change with llama.cpp revision, CUDA/driver behavior, image resolution, KV types, batch sizes, display use, and other GPU processes.

Do not run a competing CUDA workload such as ComfyUI at the same time if you want to preserve this memory envelope.

The published performance values are measured local observations, not a standardized cross-platform benchmark.

## License and attribution

This repository contains original deployment documentation and utility scripts plus information about a derivative model artifact. Preserve the license and attribution requirements of the official Qwen base model and of the specific upstream quantized GGUF from which a derivative is produced. See [`ATTRIBUTION.md`](ATTRIBUTION.md).

This repository is an independent community deployment project and is **not an official Qwen, NVIDIA, Hugging Face, or llama.cpp release**.
