# Qwen3.8-27B NVFP4 Q5K no-MTP on a 16 GB GPU

Reproducible notes, scripts, and measured deployment data for a **physical no-MTP derivative** of a Qwen3.8-27B NVFP4/Q5K GGUF, validated on an **NVIDIA GeForce RTX 5060 Ti 16 GB** with llama.cpp.

## Current best 16 GB deployment

As of **2026-08-16**, the recommended production profile is:

```text
Qwen3.8-27B NVFP4 Q5K
physical no-MTP
66K shared KV
P2 / unified KV
full-GPU text backbone (-ngl 999)
Q4_0 K/V cache
Qwen3.8 Vision enabled
F16 mmproj on CPU (--no-mmproj-offload)
image-max-tokens = 4096
llama.cpp upstream b10435 / 9e40df63ba151d771d8b247ac4011cf203337e99
NO local FA patch
```

Recommended launcher:

```bash
llama-server \
  -m Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf \
  --mmproj mmproj-Qwen3.8-27B-F16.gguf \
  --no-mmproj-offload \
  --image-max-tokens 4096 \
  -c 66000 \
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

This profile is intentionally aggressive. On the tested RTX 5060 Ti 16 GB it started at approximately:

```text
15,810 MiB used / 80 MiB free
```

After the first concurrent long-context + Vision warm-up it reached approximately:

```text
15,816 MiB used / 74 MiB free
```

Repeated equivalent runs did **not** continue increasing VRAM.

## Why 66K / P2 / no patch became the preferred profile

Earlier work focused on a local transient Flash-Attention scratch patch for llama.cpp b10435. The patch increased startup headroom substantially, but later P2 + Vision testing exposed repeatable stepwise CUDA-pool growth under the patched configuration.

In the 68K/P2/Vision test, measured high-water moved:

```text
15,778 MiB
15,796 MiB   (+18 MiB)
15,814 MiB   (+18 MiB)
```

A similar +18 MiB stepping pattern was observed again after returning to 64K while keeping the patched P2 + Vision path.

By contrast, the final **upstream/no-patch 66K/P2** profile with `--image-max-tokens 4096` showed only a small first-use warm-up increase:

```text
15,810 -> 15,814 -> 15,816 MiB
```

and then remained stable across repeated concurrent tests.

Therefore:

> **The local FA patch is no longer recommended for the best 16 GB production deployment.** It is retained only as a revision-specific research artifact and for reproducing the earlier memory-allocation experiments.

See [`PATCH-NOTES.md`](PATCH-NOTES.md) for the exact patch scope and the later A/B findings.

## Production-like validation

The final 66K/P2/no-patch validation used two live logical lanes:

```text
MAIN:   ~40K-token long-context request + 2,048 generated tokens
Vision: real image request, capped with --image-max-tokens 4096
```

Observed Vision prompt sizes were approximately **4,042–4,084 tokens**, rather than the 20K–35K prompt sizes seen when dynamic-resolution image tokens were left uncapped.

Repeated MAIN results were approximately:

```text
prompt tokens:       40,103
generated tokens:    2,048
prompt processing:   ~191-194 tok/s under concurrent Vision load
decode:              ~19.7-20.3 tok/s under concurrent Vision load
```

The concurrent workload completed repeatedly without CUDA OOM and without continued VRAM growth after first-use warm-up.

## Why image-max-tokens 4096 matters

Without an image-token cap, a first real-image Vision request could expand to tens of thousands of prompt tokens. That is undesirable when two slots share a 66K unified KV pool.

With:

```text
--image-max-tokens 4096
```

the tested ID-card recognition workload stayed around 4K prompt tokens while preserving useful OCR/detail recognition. This also restored practical CPU-offloaded Vision latency compared with the uncapped 20K–35K prompt cases.

For a mixed agent + customer-service workload, the intended scheduler policy is:

```text
CS lane:   ~4K class, non-thinking, short output, Vision allowed
MAIN lane: use the remaining shared KV for long-context agent work
```

`-c 66000 -np 2 --kv-unified` is a **shared** KV pool, not two independent 66K contexts. The external scheduler must enforce lane budgets.

## Key measured results

| Test | Result |
|---|---:|
| 32K / P1 / full GPU decode | **25.88 tok/s** |
| 72K / P1 / full GPU decode | **25.85 tok/s** |
| 64K / P2 concurrent decode A | **24.35 tok/s** |
| 64K / P2 concurrent decode B | **24.48 tok/s** |
| Approx. combined P2 decode | **48.8 tok/s** |
| 72K / P1 / no-patch / CPU Vision | stable across repeated Vision runs |
| 66K / P2 / no-patch startup | **15,810 MiB used / 80 MiB free** |
| 66K / P2 / no-patch post-warm-up | **15,816 MiB used / 74 MiB free** |
| 40K MAIN + ~4K Vision CS, repeated | **passed** |

## Provenance and no-MTP rewrite

Base model metadata points to:

- `Qwen/Qwen3.8-27B`

The source GGUF contained one embedded MTP / NextN layer. The physical rewrite produced:

| Field | Original | no-MTP |
|---|---:|---:|
| `block_count` | 65 | 64 |
| `nextn_predict_layers` | 1 | 0 |
| Highest remaining block | 64 | 63 |
| Removed MTP tensors | 15 | — |
| Removed physical size | 227.91 MiB | — |

The retained tensors were copied without requantization. Physical removal mainly produces a clean no-MTP artifact and prevents accidental MTP activation; it should not be interpreted as an additional 227.91 MiB runtime saving when MTP would already be disabled.

Exact model SHA256:

```text
828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee  mmproj-Qwen3.8-27B-F16.gguf
```

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

## Full-GPU placement matters

Earlier partial-offload tests produced only ~19.8–20.3 tok/s. Once the complete text backbone was confirmed on GPU, the model reached ~25.8 tok/s in single-stream decode. For this exact 16 GB target, giving up one or two main blocks to CPU for a larger nominal context was not worth the decode penalty.

## Vision support

The matching F16 projector is:

```text
mmproj-Qwen3.8-27B-F16.gguf
927.6 MiB
334 tensors
```

Use `--no-mmproj-offload` to keep it in system RAM. The 72K/P1/upstream/no-patch test showed repeated Vision requests were VRAM-stable: approximately 15,792 MiB at startup, then ~15,796-15,798 MiB after first use, with no further growth in later runs.

## Experimental patch status

The exact historical patch remains published for reproducibility:

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  patches/b10435-fa-transient-final.patch
```

It is revision-specific to llama.cpp b10435 / commit `9e40df63ba151d771d8b247ac4011cf203337e99`.

**Do not use the patch for the recommended 66K/P2 production configuration.** The best current result on the tested 16 GB system is the clean upstream b10435 build.

## Repository contents

- [`DEPLOYMENT.md`](DEPLOYMENT.md) — current 66K/P2/no-patch production recipe
- [`PATCH-NOTES.md`](PATCH-NOTES.md) — experimental patch history and later A/B findings
- [`RELEASE.md`](RELEASE.md) — release/update manifest
- [`ATTRIBUTION.md`](ATTRIBUTION.md) — provenance and redistribution notes
- [`scripts/strip_qwen38_mtp.py`](scripts/strip_qwen38_mtp.py) — physical no-MTP GGUF rewrite
- [`scripts/promote-vm101-qwen38-66k-p2-nopatch.sh`](scripts/promote-vm101-qwen38-66k-p2-nopatch.sh) — exact VM101 production promotion script
- [`huggingface/README.md`](huggingface/README.md) — Hugging Face model card source

## Scope and limitations

This is an intentionally aggressive configuration validated on one RTX 5060 Ti 16 GB system. The measured **74 MiB post-warm-up free VRAM is a very small margin**. Another driver, display workload, llama.cpp revision, image, batch shape, or background CUDA process can change the result.

Do not run ComfyUI or another CUDA-heavy workload concurrently with this profile.

This repository is an independent community deployment project and is **not an official Qwen, NVIDIA, Hugging Face, or llama.cpp release**.
