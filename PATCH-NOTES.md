# Patch Notes — Transient Flash-Attention Scratch on llama.cpp b10435

This document describes the **local experimental CUDA patch** used during the 2026-08-15 RTX 5060 Ti 16 GB validation.

It is important to separate two claims:

1. the Qwen3.8-27B no-MTP model itself can run without this patch; and
2. the patch changes llama.cpp CUDA scratch-allocation behavior and improves **startup / low-context VRAM headroom** on the tested revision.

The patch is **not an upstream llama.cpp option** and should not be presented as a guaranteed permanent VRAM reduction.

## Tested base revision

```text
llama.cpp build: b10435
commit: 9e40df63ba151d771d8b247ac4011cf203337e99
```

The source audit focused on:

```text
ggml/src/ggml-cuda/fattn-common.cuh
ggml/src/ggml-cuda/fattn.cuh
ggml/src/ggml-cuda/fattn.cu
ggml/src/ggml-cuda/ggml-cuda.cu
```

## Motivation

The tested llama.cpp revision reserves additional F16 dequant scratch for quantized-KV Flash Attention persistently when the context is created.

This behavior is associated with the memory-accounting change introduced around llama.cpp PR / commit `#23907` (`f8f0a47a`). It improves deterministic memory reservation, but on a single 16 GB card it can make multi-context or draft-context configurations fail during initialization even when the same scratch is not simultaneously needed at peak runtime.

The local experiment restored the earlier **transient/shared CUDA-pool allocation style** for that FA dequant scratch.

## What the local patch changed

The experiment was intentionally narrow.

At a high level it:

- restored `ggml_cuda_pool_alloc<half>` temporary K/V conversion buffers in the FA path;
- removed the persistent `ggml_cuda_flash_attn_ext_get_alloc_size(...)` sizing path from the tested b10435 source;
- returned the generic CUDA tensor allocation path to `ggml_nbytes(tensor)` for this case;
- kept the current b10435 kernels and surrounding code rather than reverting the whole CUDA backend to an old llama.cpp revision.

The local working tree changed four CUDA files:

```text
ggml/src/ggml-cuda/fattn-common.cuh
ggml/src/ggml-cuda/fattn.cu
ggml/src/ggml-cuda/fattn.cuh
ggml/src/ggml-cuda/ggml-cuda.cu
```

The test branch was named:

```text
local/b10435-fa-transient
```

`git diff --check` was clean before rebuilding.

## Startup VRAM effect

64K / P2 / full GPU / Q4_0 K+V:

| Build behavior | Used | Free |
|---|---:|---:|
| Upstream b10435 | 15,766 MiB | 124 MiB |
| Local transient-FA variant | **15,526 MiB** | **364 MiB** |

The local variant therefore created approximately **240 MiB more startup headroom** on the tested system.

This extra headroom was enough to make a CPU-offloaded Qwen3.8 Vision configuration easier to initialize and test while preserving full-GPU placement of the 27B text backbone.

## Why this is not a permanent 240 MiB saving

A long-context stress test is the critical evidence.

Test:

```text
MAIN: ~48K tokens
CS:   ~8K tokens
P2 / unified KV
full GPU
```

After the first large workload, VRAM rose to approximately:

```text
15,750 MiB used
140 MiB free
```

Repeating the same workload did **not** add another similar amount of VRAM.

Interpretation:

- the transient CUDA pool grows when the scratch is actually required;
- the pool keeps the high-water allocation mapped for reuse;
- the resulting `nvidia-smi` free-memory number therefore remains low after the request finishes;
- the observed behavior is consistent with allocator high-water caching, not a per-request leak.

The patch mainly changes **when** scratch memory is committed. It should not be advertised as permanently reducing worst-case long-context memory by 240 MiB.

## MTP experiment and why it was paused

Before selecting the final no-MTP/P2/Vision profile, the same transient approach was used to explore MTP.

A 32K/P1/MTP1 test showed a large speculative-decoding gain, roughly from ~19.8 tok/s to ~28.8 tok/s in the earlier test configuration.

The patch also allowed a 64K/P1/MTP1 server to initialize where the persistent-scratch behavior had previously failed during the MTP draft-context setup.

However, the 16 GB production target remained too tight once the following priorities were combined:

```text
64K context
full-GPU main model
reserved concurrency
Vision
stable long-running service
```

MTP was therefore intentionally removed from the final production target.

## Production-like validation with Vision

With the transient build, no-MTP, P2, and the F16 Vision projector kept on CPU:

```text
40,103-token MAIN + simultaneous real-image CS request
GPU high-water: 15,718 MiB used / 172 MiB free
result: both requests completed
CUDA OOM: none observed
```

This was the main reason the patch was considered successful for this specific 16 GB deployment experiment.

## Safety / reproducibility guidance

Do **not** blindly apply this idea to a different llama.cpp revision.

Before attempting the same patch on another revision:

1. identify the exact base commit;
2. inspect whether `ggml_cuda_flash_attn_ext_get_alloc_size` and the related persistent scratch path still exist;
3. compare the current FA code with the pre-`#23907` allocation behavior;
4. apply changes manually or with a revision-specific patch;
5. run `git diff --check`;
6. rebuild from clean sources;
7. validate short decode, long prefill, repeated long-context requests, P2, and Vision separately;
8. keep an unmodified upstream build available for A/B regression testing.

The original `#23907` change was made for a reason: deterministic reservation can prevent runtime allocation failures. Returning to transient allocation trades deterministic startup accounting for the possibility of a later runtime OOM if a future request needs more scratch than the remaining device memory can provide.

## Exact patch file

The exact tested patch should be exported from the tested working tree with:

```bash
git diff > b10435-fa-transient.patch
```

and published only together with the exact base commit above.

This repository intentionally documents the behavior and base revision. Do not substitute a patch generated from another llama.cpp commit and call it equivalent.
