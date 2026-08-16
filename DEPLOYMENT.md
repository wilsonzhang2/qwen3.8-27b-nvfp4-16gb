# Deployment Profile — RTX 5060 Ti 16 GB

This document captures the **current best validated production profile as of 2026-08-16** for Qwen3.8-27B NVFP4/Q5K physical no-MTP on a single NVIDIA GeForce RTX 5060 Ti 16 GB.

## Recommended target

```text
Model:            Qwen3.8-27B NVFP4/Q5K, physical no-MTP
GPU:              RTX 5060 Ti 16 GB
Context pool:     66,000 tokens
Parallel slots:   2
KV:               unified
K cache:          q4_0
V cache:          q4_0
Text model:       full GPU (-ngl 999)
Vision:           enabled
Vision projector: F16, CPU-resident
Image token cap:  4096 per image
MTP:              disabled / physically removed
FA patch:         NONE
```

## Exact llama.cpp base

```text
Ubuntu:           24.04.4 LTS
NVIDIA driver:    610.43.02
CUDA:             13.3
llama.cpp:        b10435
commit:           9e40df63ba151d771d8b247ac4011cf203337e99
CUDA target:      SM120
```

Build options:

```text
GGML_CUDA=ON
CMAKE_CUDA_ARCHITECTURES=120
GGML_CUDA_FA_ALL_QUANTS=ON
CMAKE_BUILD_TYPE=Release
```

The recommended deployment uses a **clean upstream b10435 tree**. Do not apply the local transient FA patch for this production profile.

## Recommended launcher

```bash
MODEL=/path/to/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
MMPROJ=/path/to/mmproj-Qwen3.8-27B-F16.gguf

llama-server \
  -m "$MODEL" \
  --mmproj "$MMPROJ" \
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

## Measured VRAM envelope

On the tested RTX 5060 Ti:

```text
fresh startup:             15,810 MiB used / 80 MiB free
first concurrent warm-up:  15,814 -> 15,816 MiB used
post-warm-up:              15,816 MiB used / 74 MiB free
later equivalent runs:     no further VRAM growth observed
```

This is an extremely tight memory envelope. The profile should be treated as specific to the tested driver/CUDA/build combination.

## Production-like concurrent test

The final repeated stress workload used:

```text
slot 1 / MAIN:
  ~40K-token long-context prompt
  2,048 generated tokens

slot 0 / Vision CS:
  real image
  --image-max-tokens 4096
  ~4,042-4,084 prompt tokens observed
```

Repeated MAIN results were approximately:

```text
prompt tokens:       40,103
output tokens:       2,048
prompt processing:   ~191-194 tok/s under concurrent Vision load
decode:              ~19.7-20.3 tok/s under concurrent Vision load
```

Both lanes completed repeatedly. No CUDA OOM was observed, and after first-use warm-up the GPU-memory reading stopped increasing.

## Why image-max-tokens 4096 is part of the production recipe

Before applying an image-token cap, real-image requests could expand to very large prompt sizes:

```text
~22K tokens in one test
~35.7K tokens in another test
```

With a 66K shared KV pool, that can exhaust the pool when a ~40K MAIN request is active. The server log confirmed this failure mode with messages including:

```text
failed to find free space in the KV cache
Context size has been exceeded
```

The failing request pair reached approximately:

```text
Vision slot: 35,679 tokens
MAIN slot:   30,432 tokens
combined:    66,111 tokens
```

After adding:

```text
--image-max-tokens 4096
```

Vision prompts for the same class of image stayed around 4K tokens and the concurrent workload completed normally.

## Scheduler policy

P2 is used as two logical lanes, but the KV cache is shared.

### Lane A — customer service

```text
concurrency:      1
normal context:   ~4K class
reasoning:        non-thinking / disabled
output:           short
Vision:           allowed
image cap:        4096
reservation:      keep available
```

### Lane B — MAIN / Hermes

```text
concurrency:      1
normal context:   as large as required within the remaining shared pool
reasoning:        allowed
```

The scheduler should keep the CS lane small and allow the MAIN lane to use the rest. Extra concurrent work should queue or spill to a remote API.

## Full-GPU placement matters

Measured single-stream decode:

| Configuration | Result |
|---|---:|
| 32K / P1 / full GPU | **25.88 tok/s** |
| 72K / P1 / full GPU | **25.85 tok/s** |
| earlier partial-offload tests | ~**19.8–20.3 tok/s** |

The final profile therefore keeps all repeating text blocks plus output on GPU with `-ngl 999`.

## P2 continuous batching

Earlier 64K/P2/upstream testing measured two simultaneous 512-token generations at approximately:

```text
24.35 tok/s
24.48 tok/s
aggregate ~48.8 tok/s
```

This established that P2 itself is useful on the card. The later 66K profile adds the Vision token cap and retains upstream/no-patch behavior.

## Vision on CPU

Use:

```text
--no-mmproj-offload
```

The matching F16 projector is approximately 927.6 MiB / 334 tensors and remains in system RAM. A separate 72K/P1/upstream/no-patch Vision test was stable across repeated image requests, with only a small first-use VRAM increase and no continued growth.

## Patch decision

The historical local transient Flash-Attention patch created about 240 MiB of extra startup headroom in the earlier 64K/P2 profile. However, later P2 + Vision stress testing showed repeatable stepwise VRAM growth under the patched configuration.

The current recommendation is therefore:

```text
Production: upstream b10435, NO PATCH
Research/reproduction only: b10435 transient FA patch
```

See `PATCH-NOTES.md` for the measured A/B evidence.

## Production promotion helper

The VM101 helper for the exact validated profile is:

```text
scripts/promote-vm101-qwen38-66k-p2-nopatch.sh
```

It validates the exact upstream commit and published model/mmproj SHA256 values before installing the service.

## Operational cautions

- Keep the GPU dedicated to llama.cpp for this profile.
- Do not run ComfyUI or another CUDA-heavy process concurrently.
- The observed post-warm-up margin was only ~74 MiB.
- `--fit off` deliberately prevents automatic fallback to a smaller layout.
- A different driver, llama.cpp revision, image shape, batch, or background process can change the result.
- 66K is one shared KV pool, not two independent 66K contexts.

This is a measured recipe for one specific 16 GB system, not a universal guarantee for every 16 GB GPU.
