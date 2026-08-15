---
base_model:
  - Qwen/Qwen3.8-27B
pipeline_tag: image-text-to-text
library_name: llama.cpp
tags:
  - gguf
  - qwen
  - qwen3.8
  - nvfp4
  - llama.cpp
  - multimodal
  - vision
  - no-mtp
  - rtx-5060-ti
  - 16gb-vram
---

# Qwen3.8-27B NVFP4 Q5K — Physical no-MTP, 16 GB VRAM Deployment Notes

This model card documents a **physical no-MTP derivative** of a Qwen3.8-27B NVFP4/Q5K GGUF build and a reproducible deployment profile validated on an **NVIDIA GeForce RTX 5060 Ti 16 GB**.

The goal is not maximum speculative-decoding speed. The goal is to fit the main 27B model as tightly as possible into 16 GB VRAM while keeping:

- the full 27B text backbone on GPU;
- a 64K shared KV cache;
- `parallel = 2`;
- a permanently available low-latency customer-service lane;
- native Qwen3.8 Vision through a separate CPU-offloaded `mmproj`;
- stable llama.cpp serving for Hermes/agent workloads.

The tested result is a practical **64K / P2 / full-GPU / Vision-on-CPU** configuration on a 16 GB card.

> **Important:** The FA memory patch described below is experimental and local. It is not an upstream llama.cpp configuration option. The model itself does not require this patch, but the patch materially improves startup VRAM headroom on this exact 16 GB deployment.

## Provenance

Base model:

- `Qwen/Qwen3.8-27B`

GGUF architecture reported by llama.cpp:

- `qwen35`

The source GGUF used for this work contained an additional MTP / NextN block.

The physical no-MTP conversion changed:

| Field | Original | no-MTP |
|---|---:|---:|
| `block_count` | 65 | 64 |
| `nextn_predict_layers` | 1 | 0 |
| Highest remaining block | 64 | 63 |
| Removed MTP tensors | 15 | — |
| Removed physical size | 227.91 MiB | — |

No requantization was performed during the no-MTP rewrite. The retained NVFP4/Q5K tensors were copied unchanged into the new GGUF.

The main practical benefit of physically removing MTP is a cleaner deployment artifact and elimination of accidental MTP activation. It does **not** save another 227.91 MiB of runtime VRAM in normal no-MTP inference, because llama.cpp already skips the MTP tensors when MTP is disabled.

## Tested hardware and software

### GPU

- NVIDIA GeForce RTX 5060 Ti
- VRAM reported by `nvidia-smi`: **16,311 MiB**
- CUDA compute target used for build: **SM120**

### Host / VM

- Intel Core i5-13600K host
- Ubuntu 24.04.4 LTS guest
- Approximately 21 GiB guest RAM during testing

### NVIDIA / CUDA

- NVIDIA driver: **610.43.02**
- CUDA runtime/toolkit: **13.3**

### llama.cpp

Tested revision:

- build: **b10435**
- commit: **`9e40df63ba151d771d8b247ac4011cf203337e99`**

Important build options:

```text
GGML_CUDA=ON
CMAKE_CUDA_ARCHITECTURES=120
GGML_CUDA_FA_ALL_QUANTS=ON
CMAKE_BUILD_TYPE=Release
```

## Recommended 16 GB configuration

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
  -ctk q4_0 \
  -ctv q4_0 \
  -b 512 \
  -ub 64 \
  --threads 7 \
  --fit off \
  --jinja \
  --host 0.0.0.0 \
  --port 8001
```

### Why these settings

- **64K context:** practical upper target that still allows P2 and Vision on a 16 GB card.
- **P2 / unified KV:** one shared KV pool with two live server slots.
- **Full GPU text model:** required to preserve ~25–26 tok/s decode speed.
- **Q4_0 K/V cache:** necessary for fitting the desired context.
- **Vision projector on CPU:** avoids spending ~928 MiB of VRAM on the Qwen3.8 vision projector.
- **MTP disabled:** avoids the additional draft context and its memory pressure.

## Full-GPU placement matters

A major finding from this deployment is that Qwen3.8-27B loses substantial decode performance when even a small number of backbone blocks remain on CPU.

Measured decode speed:

| Configuration | Context / Parallel | Decode speed |
|---|---|---:|
| Full GPU | 32K / P1 | **25.88 tok/s** |
| Full GPU | 72K / P1 | **25.85 tok/s** |
| Earlier partial-offload tests | 64K / P1 | ~**19.8–20.3 tok/s** |

For this card, do not trade one or two backbone layers to CPU unless the additional VRAM is more valuable than the decode penalty.

## P2 continuous-batching results

Test configuration:

- 64K context
- `parallel = 2`
- unified KV
- full GPU
- no MTP
- 512 generated tokens on both concurrent requests

Measured concurrent decode:

| Slot | Decode speed |
|---|---:|
| Request A | **24.35 tok/s** |
| Request B | **24.48 tok/s** |
| Approx. combined decode throughput | **48.8 tok/s** |

P2 did not simply divide single-request speed in half during this test. llama.cpp continuous batching kept both streams close to the single-stream decode rate.

Static VRAM for 64K/P2/full-GPU with upstream b10435 FA memory behavior was approximately:

- **15,766 MiB used**
- **124 MiB free**

## Vision support

Qwen3.8-27B is natively multimodal in the tested checkpoint metadata.

A matching Qwen3.8 vision projector was generated directly from `Qwen/Qwen3.8-27B` with llama.cpp's remote `--mmproj` conversion path.

Generated projector:

- format: F16 GGUF
- tensors: **334**
- size: **927.6 MiB**

Example conversion:

```bash
python convert_hf_to_gguf.py \
  Qwen/Qwen3.8-27B \
  --remote \
  --mmproj \
  --outtype f16 \
  --outfile Qwen3.8-27B-F16.gguf
```

The output was renamed to:

```text
mmproj-Qwen3.8-27B-F16.gguf
```

### CPU Vision offload

Use:

```text
--no-mmproj-offload
```

This keeps the ~928 MiB Vision projector in system RAM instead of VRAM.

Measured behavior with the local transient-FA patch:

- server startup with Vision enabled: **15,526 MiB used / 364 MiB free**;
- real image request peak: **15,546 MiB used / 344 MiB free**;
- additional GPU memory at image high-water: about **20 MiB**;
- image understanding completed successfully;
- text decode after visual preprocessing: **25.24 tok/s**.

CPU visual preprocessing is slower than a GPU-resident projector, but main 27B text decode remains essentially unchanged.

## Experimental FA transient-memory patch

On this 16 GB card, upstream b10435 persistent Flash-Attention dequant scratch reservation leaves very little free VRAM in the 64K/P2/full-GPU configuration.

A local patch restored an earlier transient/shared CUDA-pool allocation style for quantized-KV FA F16 dequant scratch instead of reserving the full scratch persistently at context initialization.

64K / P2 / full GPU:

| Build behavior | Used | Free |
|---|---:|---:|
| Upstream b10435 | 15,766 MiB | 124 MiB |
| Local transient-FA patch at startup | **15,526 MiB** | **364 MiB** |

Startup headroom improved by roughly **240 MiB**.

### High-water caveat

This is **not** a permanent 240 MiB saving.

A ~48K MAIN + ~8K customer-service stress test grew the CUDA pool to approximately:

- **15,750 MiB used**
- **140 MiB free**

Repeating the same workload did not continue increasing VRAM. The observed behavior is consistent with allocator high-water caching rather than a per-request leak.

The patch therefore provides useful startup and low/medium-context headroom, but should not be advertised as a guaranteed permanent reduction in worst-case long-context VRAM.

## Combined P2 + long context + Vision stress test

A production-like test was performed with:

- slot 1: ~40K-token MAIN / thinking workload;
- slot 0: simultaneous real-image customer-service request;
- 64K unified KV;
- P2;
- full GPU;
- CPU-offloaded F16 Qwen3.8 mmproj;
- no MTP.

MAIN lane:

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

Both lanes completed successfully. No CUDA OOM or allocation failure was observed.

## Suggested Hermes routing policy

Use P2 as two logical lanes rather than two arbitrary local jobs.

### Customer-service lane

```text
local concurrency: 1
context ceiling: ~8K
reasoning: disabled / non-thinking
short output limit
Vision allowed
always reserve this lane
```

### MAIN lane

```text
local concurrency: 1
normal working context: ~32K–48K
larger context only when necessary
thinking allowed
```

Additional concurrent jobs should queue or spill to a remote API rather than consume the reserved customer-service lane.

## Why MTP was not selected

MTP produced a large single-stream speed increase in earlier testing, but 16 GB did not provide comfortable memory headroom for the desired 64K production context plus the additional MTP draft context.

The final deployment prioritizes:

1. full-GPU text backbone;
2. P2 concurrency;
3. 64K shared KV;
4. Vision;
5. stability;
6. MTP only if future memory behavior makes it fit comfortably.

## Why 64K instead of 80K

80K/P2 was explored, but it required either extremely small VRAM headroom or CPU layer offload. The performance cost of partial CPU offload was too large compared with the practical benefit of moving from 64K to 80K.

For this exact 16 GB target, **64K/P2/full-GPU/CPU-Vision is the better balance**.

## Practical limits

This setup is intentionally aggressive and has been validated on one RTX 5060 Ti 16 GB system, not across multiple GPUs or driver versions.

Expect sensitivity to:

- llama.cpp revision;
- CUDA allocator changes;
- driver version;
- prompt length;
- image size;
- batch/ubatch settings;
- KV cache quantization;
- background GPU processes.

Recommended operational rules:

- keep the GPU dedicated to llama.cpp while this configuration is active;
- do not run ComfyUI or another CUDA workload at the same time;
- use `--fit off` only when you deliberately want the requested settings and understand the OOM risk;
- treat 64K as the shared configured pool, not as a promise that two independent 64K requests can coexist;
- reserve an explicit KV budget for the customer-service lane;
- restart the server if you need to reset CUDA allocator high-water state after extreme long-context workloads.

## Reproducibility checklist

```text
[ ] RTX 5060 Ti 16 GB
[ ] llama.cpp b10435 / commit 9e40df6
[ ] CUDA build for SM120
[ ] physical no-MTP GGUF
[ ] 64 text blocks
[ ] nextn_predict_layers = 0
[ ] full GPU placement
[ ] -c 64000
[ ] -np 2
[ ] --kv-unified
[ ] Q4_0 K cache
[ ] Q4_0 V cache
[ ] Flash Attention enabled
[ ] CPU-offloaded Qwen3.8 mmproj
[ ] no competing CUDA workloads
```

## Licensing and redistribution note

Before publishing model weights or derived GGUF files, verify and preserve the license and attribution requirements of:

1. the official `Qwen/Qwen3.8-27B` base model; and
2. the specific upstream quantized GGUF from which the no-MTP artifact is derived.

This model card is documentation and does not itself grant redistribution rights for third-party model weights.

## Summary

Validated target:

```text
Qwen3.8-27B NVFP4 Q5K
physical no-MTP
64K shared KV
parallel = 2
full GPU text backbone
Q4_0 K/V cache
Qwen3.8 Vision enabled
F16 mmproj on CPU
~25.8 tok/s single-stream text decode
~24 + 24 tok/s in the tested dual 512-token decode case
40K MAIN + simultaneous Vision CS stress test passed
```

For a mixed Hermes + customer-service workload on a 16 GB GPU, this configuration is a practical balance between **context, concurrency, multimodality, speed, and reliability**.
