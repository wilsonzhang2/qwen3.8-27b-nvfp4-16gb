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

# Qwen3.8-27B NVFP4 Q5K — Physical no-MTP, 16 GB VRAM

This repository contains a **physical no-MTP derivative** of a Qwen3.8-27B NVFP4/Q5K GGUF and the matching F16 Vision projector.

## Current best 16 GB deployment

Validated on an **NVIDIA GeForce RTX 5060 Ti 16 GB** on 2026-08-16:

```text
Qwen3.8-27B NVFP4 Q5K
physical no-MTP
66K shared KV
P2 / unified KV
full-GPU text backbone
Q4_0 K/V cache
Qwen3.8 Vision enabled
F16 mmproj on CPU
--image-max-tokens 4096
llama.cpp upstream b10435 / 9e40df63ba151d771d8b247ac4011cf203337e99
NO local FA patch
```

Recommended command:

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

## Measured memory envelope

```text
fresh startup:             15,810 MiB used / 80 MiB free
post first warm-up:        15,816 MiB used / 74 MiB free
later repeated stress:     no further VRAM growth observed
```

The tested GPU reports 16,311 MiB total VRAM through `nvidia-smi`, so this is an intentionally tight, hardware-specific profile.

## Repeated production-like test

Two live logical lanes were exercised concurrently:

```text
MAIN:   ~40K prompt + 2,048 generated tokens
Vision: real image request, ~4,042-4,084 prompt tokens
```

The MAIN request repeatedly completed at approximately:

```text
prompt processing: ~191-194 tok/s under concurrent Vision load
decode:            ~19.7-20.3 tok/s under concurrent Vision load
```

No CUDA OOM was observed. After first-use warm-up, repeated equivalent runs did not continue increasing VRAM.

## Why image-max-tokens 4096 is important

Without an image-token cap, dynamic-resolution Vision requests could expand to tens of thousands of prompt tokens. One failing 66K/P2 test reached:

```text
Vision slot: 35,679 tokens
MAIN slot:   30,432 tokens
combined:    66,111 tokens
```

The server then returned `Context size has been exceeded`. This was a shared-KV capacity failure, not a CUDA OOM.

With:

```text
--image-max-tokens 4096
```

the tested image-recognition workload stayed around 4K prompt tokens and CPU-offloaded Vision latency returned to a practical range.

## Patch status — experimental only

An earlier local b10435 Flash-Attention transient-scratch patch is still published for reproducibility:

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  patches/b10435-fa-transient-final.patch
```

It increased startup VRAM headroom substantially in the earlier 64K/P2 tests. However, later repeated **P2 + Vision** stress showed undesirable stepwise CUDA-pool growth under the patched path. A 68K sequence measured approximately:

```text
15,778 MiB
15,796 MiB (+18 MiB)
15,814 MiB (+18 MiB)
```

A similar ~18 MiB stepping pattern was observed again after returning to 64K while keeping the patched P2 + Vision path.

By contrast, clean upstream b10435 at 66K/P2 with `--image-max-tokens 4096` stabilized after a small first-use warm-up increase.

**Therefore the patch is not recommended for production.** Use the clean upstream b10435 build for the current best 16 GB profile. See `PATCH-NOTES.md` for the detailed A/B notes.

## Full-GPU placement matters

Measured single-stream decode:

| Configuration | Decode speed |
|---|---:|
| 32K / P1 / full GPU | **25.88 tok/s** |
| 72K / P1 / full GPU | **25.85 tok/s** |
| earlier partial-offload tests | ~**19.8–20.3 tok/s** |

For this card, keeping the text backbone fully on GPU is substantially more valuable than gaining a little more context through CPU layer offload.

## P2 continuous batching

Earlier 64K/P2/upstream tests measured two simultaneous 512-token generations at approximately:

```text
24.35 tok/s
24.48 tok/s
aggregate ~48.8 tok/s
```

This established that P2 itself is useful on the card. The final 66K profile adds the Vision token cap while keeping upstream/no-patch behavior.

## Vision projector

Matching projector:

```text
mmproj-Qwen3.8-27B-F16.gguf
927.6 MiB
334 tensors
```

Use:

```text
--no-mmproj-offload
```

to keep the projector in system RAM.

A separate 72K/P1/upstream/no-patch test showed repeated Vision requests were VRAM-stable after a small first-use warm-up increase.

## Physical no-MTP rewrite

Base model:

```text
Qwen/Qwen3.8-27B
```

The source GGUF contained one embedded MTP / NextN layer. The physical rewrite changed:

| Field | Original | no-MTP |
|---|---:|---:|
| `block_count` | 65 | 64 |
| `nextn_predict_layers` | 1 | 0 |
| Highest remaining block | 64 | 63 |
| Removed MTP tensors | 15 | — |
| Removed physical size | 227.91 MiB | — |

No requantization was performed. Retained tensors were copied unchanged.

## Exact artifact SHA256

```text
828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee  mmproj-Qwen3.8-27B-F16.gguf
```

## Tested software

```text
Ubuntu:        24.04.4 LTS
NVIDIA driver: 610.43.02
CUDA:          13.3
llama.cpp:     b10435
commit:        9e40df63ba151d771d8b247ac4011cf203337e99
CUDA target:   SM120
```

Build options:

```text
GGML_CUDA=ON
CMAKE_CUDA_ARCHITECTURES=120
GGML_CUDA_FA_ALL_QUANTS=ON
CMAKE_BUILD_TYPE=Release
```

## Scheduler guidance

`-c 66000 -np 2 --kv-unified` is one shared KV pool, not two independent 66K contexts.

Recommended mixed-agent policy:

```text
CS lane:   ~4K class, non-thinking, short output, Vision allowed
MAIN lane: use the remaining shared KV for long-context work
```

Additional concurrent jobs should queue or spill to a remote model rather than consume the reserved CS lane.

## Practical warning

The measured post-warm-up free VRAM was only about **74 MiB**. A different driver, llama.cpp revision, display load, image shape, batch size, or background CUDA process can change the result. Do not run another CUDA-heavy workload such as ComfyUI at the same time.

This is an independent community deployment project and is not an official Qwen, NVIDIA, Hugging Face, or llama.cpp release.
