# Patch Notes — Transient Flash-Attention Scratch on llama.cpp b10435

This document describes the **exact local experimental CUDA patch** used during the 2026-08-15 RTX 5060 Ti 16 GB experiments and the later 2026-08-16 A/B findings.

## Current recommendation

> **Do not use this patch for the recommended 16 GB production profile.**

The current best validated production configuration is:

```text
llama.cpp upstream b10435 / 9e40df63ba151d771d8b247ac4011cf203337e99
NO PATCH
Qwen3.8-27B NVFP4 Q5K physical no-MTP
66K shared KV
P2 / unified KV
full GPU
Q4_0 K/V
Vision mmproj on CPU
--image-max-tokens 4096
```

The patch remains published for reproducibility and allocator research.

## Exact patch artifact

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  b10435-fa-transient-final.patch
```

File:

[`patches/b10435-fa-transient-final.patch`](patches/b10435-fa-transient-final.patch)

```text
8,251 bytes
206 lines
```

Exact llama.cpp base:

```text
build:  b10435
commit: 9e40df63ba151d771d8b247ac4011cf203337e99
```

The patch is revision-specific. Do not transplant it blindly to another llama.cpp commit.

## What the patch changes

The tested patch modifies exactly four CUDA files:

```text
ggml/src/ggml-cuda/fattn-common.cuh
ggml/src/ggml-cuda/fattn.cu
ggml/src/ggml-cuda/fattn.cuh
ggml/src/ggml-cuda/ggml-cuda.cu
```

At a high level, it removes the persistent Flash-Attention F16 dequant-scratch sizing path used for quantized KV in this b10435 revision and restores temporary K/V F16 conversion buffers allocated from the CUDA pool with `ggml_cuda_pool_alloc<half>`.

This is a narrow allocator-behavior experiment, not a general CUDA optimization.

## Why it originally looked attractive

For 64K/P2/full-GPU/Q4_0 K+V:

| Build behavior | Used | Free |
|---|---:|---:|
| Upstream b10435 | 15,766 MiB | 124 MiB |
| Local transient-FA patch at startup | **15,526 MiB** | **364 MiB** |

The patch therefore created roughly **240 MiB more startup headroom** on the tested RTX 5060 Ti 16 GB.

That extra startup margin helped explore otherwise marginal configurations, including MTP and larger P2/Vision combinations.

## Later finding: P2 + Vision stepwise VRAM growth

The more important production finding came later.

With the patched build under repeated **P2 + Vision** stress, GPU memory showed repeatable stepwise growth rather than settling immediately at one stable high-water mark.

A 68K/P2/Vision sequence measured approximately:

```text
round 1 high-water: 15,778 MiB used / 112 MiB free
round 2 high-water: 15,796 MiB used /  94 MiB free   (+18 MiB)
round 3 high-water: 15,814 MiB used /  76 MiB free   (+18 MiB)
```

After returning to 64K while retaining the patched P2 + Vision path, the same characteristic **~18 MiB step pattern** was observed again during repeated Vision/concurrent activity.

It is not necessary to label this conclusively as a classic memory leak to make the production decision. On a 16 GB card with only tens of MiB of remaining headroom, repeatable allocator/pool growth is itself unacceptable for a long-running service.

## A/B-like comparison with clean upstream b10435

The clean upstream/no-patch build was then tested separately.

### 72K / P1 / Vision CPU / no patch

Repeated Vision requests were stable:

```text
startup:       ~15,792 MiB used / 98 MiB free
first use:     ~15,796-15,798 MiB used
later runs:    no continued growth observed
```

This reduced suspicion on CPU-offloaded Vision itself.

### 66K / P2 / Vision CPU / no patch

The final production candidate added:

```text
--image-max-tokens 4096
```

Measured VRAM:

```text
fresh startup:             15,810 MiB used / 80 MiB free
first concurrent warm-up:  15,814 -> 15,816 MiB used
post-warm-up:              15,816 MiB used / 74 MiB free
later repeated runs:       no further growth observed
```

The same class of 40K MAIN + real-image Vision CS workload completed repeatedly.

This makes the clean upstream build the better production choice on the tested 16 GB system.

## Why image-max-tokens is part of the fix at the system level

An uncapped dynamic-resolution Vision request could expand to tens of thousands of prompt tokens. One failing 66K/P2/no-patch experiment reached approximately:

```text
Vision slot: 35,679 tokens
MAIN slot:   30,432 tokens
combined:    66,111 tokens
```

The server correctly reported:

```text
failed to find free space in the KV cache
Context size has been exceeded
```

This was a KV-capacity failure, not a CUDA OOM.

After adding `--image-max-tokens 4096`, the tested image workload stayed around 4K prompt tokens and concurrent operation became practical.

## MTP experiment

The transient patch also enabled 64K/P1/MTP1 experiments that were difficult to initialize with persistent scratch reservation. Measured decode was roughly **28.6–28.8 tok/s** with observed draft acceptance around **82.8%** in the recorded test.

MTP was still rejected for the final 16 GB production target because the combined priorities were more valuable:

```text
long context
full-GPU text backbone
P2 concurrency
Vision
long-running stability
```

The published model is therefore physical no-MTP.

## Safe reproduction of the patch

The helper remains:

```text
scripts/apply-b10435-fa-transient.sh
```

Manual prerequisites:

```bash
cd /opt/llama.cpp-qwen38

test "$(git rev-parse HEAD)" = "9e40df63ba151d771d8b247ac4011cf203337e99"
sha256sum /path/to/b10435-fa-transient-final.patch
# expected:
# 1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b

git apply --check /path/to/b10435-fa-transient-final.patch
git apply /path/to/b10435-fa-transient-final.patch
```

Use this only for reproducing the historical experiment or for new controlled research. Keep an unmodified upstream build available for A/B testing.

## Bottom line

The patch **does** improve startup headroom on b10435, but later P2 + Vision stress testing showed undesirable repeatable pool growth. The best current 16 GB deployment therefore uses **upstream b10435 with no patch**, 66K/P2, full GPU, physical no-MTP, CPU Vision, and `--image-max-tokens 4096`.
