# Deployment Profile — RTX 5060 Ti 16 GB

This document captures the exact deployment shape that was validated on 2026-08-15 for Qwen3.8-27B NVFP4/Q5K physical no-MTP on a single NVIDIA GeForce RTX 5060 Ti 16 GB.

## Validated target

```text
Model:            Qwen3.8-27B NVFP4/Q5K, physical no-MTP
GPU:              RTX 5060 Ti 16 GB
Context pool:     64,000 tokens
Parallel slots:   2
KV:               unified
K cache:          q4_0
V cache:          q4_0
Text model:       full GPU
Vision:           enabled
Vision projector: F16, CPU-resident
MTP:              disabled / physically removed
```

## Software environment

```text
Ubuntu:           24.04.4 LTS
NVIDIA driver:    610.43.02
CUDA:             13.3
llama.cpp:        b10435
commit:           9e40df63ba151d771d8b247ac4011cf203337e99
CUDA target:      SM120
```

Important llama.cpp build options:

```text
GGML_CUDA=ON
CMAKE_CUDA_ARCHITECTURES=120
GGML_CUDA_FA_ALL_QUANTS=ON
CMAKE_BUILD_TYPE=Release
```

## Recommended launcher

```bash
MODEL=/path/to/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
MMPROJ=/path/to/mmproj-Qwen3.8-27B-F16.gguf

llama-server \
  -m "$MODEL" \
  --mmproj "$MMPROJ" \
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

`-ngl 999` is intentional here. The deployment was tuned around complete GPU placement of the text backbone.

## Decode measurements

| Scenario | Result |
|---|---:|
| 32K / P1 / full GPU | **25.88 tok/s** |
| 72K / P1 / full GPU | **25.85 tok/s** |
| Earlier partial-offload, 64K / P1 | ~**19.8–20.3 tok/s** |
| P2 request A, 512 generated tokens | **24.35 tok/s** |
| P2 request B, 512 generated tokens | **24.48 tok/s** |
| Approx. aggregate P2 decode | **48.8 tok/s** |

The partial-offload measurements are important: the earlier ~20 tok/s behavior was not representative of the model's full-GPU capability on this card.

## Vision measurements

A matching F16 projector was generated from `Qwen/Qwen3.8-27B` using llama.cpp's remote multimodal conversion path.

```text
Projector tensors: 334
Projector size:    927.6 MiB
Projector device:  CPU via --no-mmproj-offload
```

Measured with the local transient-FA patch:

```text
Server startup:         15,526 MiB used / 364 MiB free
Real image request:     15,546 MiB used / 344 MiB free
Increment at high-water: ~20 MiB
Text decode after image preprocessing: 25.24 tok/s
```

The image was correctly understood. CPU Vision preprocessing is slower than GPU projector execution, but it preserves the GPU memory needed to keep the complete 27B text backbone resident.

## Long-context P2 test

A simultaneous ~48K MAIN + ~8K CS test completed successfully.

The local transient-FA build reached:

```text
~15,750 MiB used
~140 MiB free
```

Repeating the same workload did not cause another comparable memory increase.

## Combined production-like stress test

The most important final test ran the two logical lanes simultaneously:

```text
slot 1: ~40K MAIN / thinking
slot 0: real-image customer-service request
```

MAIN result:

```text
prompt tokens:       40,103
output tokens:       2,048
prompt processing:   382.57 tok/s
decode:              ~19.0 tok/s
```

Combined GPU high-water:

```text
15,718 MiB used
172 MiB free
```

Both requests completed. No CUDA OOM or allocation failure was observed.

## Recommended scheduler policy

### Lane A — customer service

```text
concurrency:      1
context ceiling:  ~8K
reasoning:        non-thinking / disabled
output:           short
Vision:           allowed
reservation:      always keep available
```

### Lane B — MAIN / Hermes

```text
concurrency:      1
normal context:   ~32K–48K
reasoning:        allowed
64K use:          only when necessary
```

Do not treat `-c 64000 -np 2 --kv-unified` as two guaranteed independent 64K slots. It is a shared KV pool. Scheduler policy matters.

## Why 64K instead of 80K

80K/P2 was explored, but the practical choices were either extremely small memory headroom or CPU offload of main model layers. Because even limited CPU offload materially reduced decode speed, 64K/P2/full-GPU was selected as the better balance.

## Why no MTP

MTP produced a large speculative-decoding speed gain in earlier testing, but the additional draft context made the desired 64K production envelope too fragile on 16 GB.

The final priority order is:

1. full-GPU text backbone;
2. reserved P2 concurrency;
3. 64K shared KV;
4. Vision;
5. stability;
6. MTP only if future llama.cpp/CUDA memory behavior makes it fit comfortably.

## Operational cautions

- Keep the GPU dedicated to llama.cpp for this profile.
- Do not run ComfyUI or another CUDA-heavy process concurrently.
- `--fit off` means the requested memory layout is not automatically reduced to save you from OOM.
- Very large images, different batches, another driver, or another llama.cpp revision can change the memory envelope.
- Restarting the server resets CUDA allocator high-water state after extreme long-context tests.

This profile is a measured deployment recipe for one specific 16 GB system, not a universal guarantee for every 16 GB GPU.
