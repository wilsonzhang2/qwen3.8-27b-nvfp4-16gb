# Patch Notes — Transient Flash-Attention Scratch on llama.cpp b10435

This document describes the **exact local experimental CUDA patch** used during the 2026-08-15 RTX 5060 Ti 16 GB validation.

It is important to separate two claims:

1. the Qwen3.8-27B no-MTP model itself can run without this patch; and
2. the patch changes llama.cpp CUDA scratch-allocation behavior and improves **startup / low-context VRAM headroom** on the tested revision.

The patch is **not an upstream llama.cpp option** and should not be presented as a guaranteed permanent VRAM reduction.

## Exact tested artifact

Patch file:

[`patches/b10435-fa-transient-final.patch`](patches/b10435-fa-transient-final.patch)

Exact SHA256 of the uploaded file copied from the tested VM101 system:

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  b10435-fa-transient-final.patch
```

File size and line count:

```text
8,251 bytes
206 lines
```

Tested llama.cpp base:

```text
build:  b10435
commit: 9e40df63ba151d771d8b247ac4011cf203337e99
```

The patch must be treated as **revision-specific**. Do not apply it blindly to another llama.cpp commit.

## Source scope

The tested patch changes exactly four CUDA files:

```text
ggml/src/ggml-cuda/fattn-common.cuh
ggml/src/ggml-cuda/fattn.cu
ggml/src/ggml-cuda/fattn.cuh
ggml/src/ggml-cuda/ggml-cuda.cu
```

Before the experiment, the b10435 source audit showed the persistent FA scratch sizing path through:

```text
ggml_cuda_flash_attn_ext_get_f16_extra_data(...)
ggml_cuda_flash_attn_ext_get_alloc_size(...)
```

The local patch removes that persistent sizing path for this case and restores temporary K/V F16 conversion buffers allocated from the CUDA pool with `ggml_cuda_pool_alloc<half>`.

At a high level it:

- removes `ggml_cuda_flash_attn_ext_f16_extra_data` and its persistent K/V address calculation;
- restores transient `K_f16` / `V_f16` pool allocations in the Flash-Attention path;
- removes `ggml_cuda_flash_attn_ext_get_alloc_size(...)` from the tested b10435 source;
- returns the generic CUDA tensor allocation size to `ggml_nbytes(tensor)` for this path;
- keeps the rest of b10435 and its current kernels unchanged.

This is a narrow allocator-behavior experiment, not a wholesale rollback of the CUDA backend.

## Why this patch exists

The tested llama.cpp revision reserves additional F16 dequant scratch for quantized-KV Flash Attention persistently when the context is created.

This behavior is associated with the memory-accounting change introduced around llama.cpp PR / commit `#23907` (`f8f0a47a`). It improves deterministic memory reservation, but on a single 16 GB card it can make very tight configurations fail during initialization even when the scratch is not simultaneously required at peak runtime.

An audit of b10435 confirmed the persistent allocation path was present. A direct reverse application of the upstream `f8f0a47a.patch` was **not** clean against b10435 because the surrounding FA implementation had changed, so the final tested patch was produced specifically for b10435 rather than claiming that a raw upstream reverse patch was equivalent.

## Startup VRAM effect

64K / P2 / full GPU / Q4_0 K+V:

| Build behavior | Used | Free |
|---|---:|---:|
| Upstream b10435 | 15,766 MiB | 124 MiB |
| Exact local transient-FA patch at startup | **15,526 MiB** | **364 MiB** |

The local variant therefore created approximately **240 MiB more startup headroom** on the tested system.

This extra startup headroom made the CPU-offloaded Qwen3.8 Vision configuration easier to initialize while preserving full-GPU placement of the 27B text backbone.

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

A 64K/P1/MTP1 run with the patched build completed at roughly **28.6–28.8 tok/s**, with observed draft acceptance around **82.8%** in the recorded test. The patch also allowed the 64K/P1/MTP1 server to initialize where the persistent-scratch behavior had previously failed during MTP draft-context setup.

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

With the exact transient patch, physical no-MTP model, P2, and F16 Vision projector kept on CPU:

```text
40,103-token MAIN + simultaneous real-image CS request
GPU high-water: 15,718 MiB used / 172 MiB free
result: both requests completed
CUDA OOM: none observed
```

This was the main validation for the final 16 GB profile.

## Safe application

The repository includes a helper that refuses to apply the patch unless both the base commit and patch SHA256 are correct:

```bash
scripts/apply-b10435-fa-transient.sh
```

Manual equivalent:

```bash
cd /opt/llama.cpp-qwen38

test "$(git rev-parse HEAD)" = "9e40df63ba151d771d8b247ac4011cf203337e99"
sha256sum /path/to/b10435-fa-transient-final.patch
# expected: 1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b

git status --short
git apply --check /path/to/b10435-fa-transient-final.patch
git apply /path/to/b10435-fa-transient-final.patch
git diff --check
```

Then rebuild with the same CUDA/SM120 build settings used for validation.

## Safety / reproducibility guidance

Do **not** blindly transplant this diff to a different llama.cpp revision.

For another revision:

1. identify the exact base commit;
2. inspect whether the persistent FA F16 dequant scratch path still exists;
3. compare current code with the allocation behavior this patch restores;
4. create a new revision-specific patch if necessary;
5. run `git diff --check` and a clean rebuild;
6. validate short decode, long prefill, repeated long-context requests, P2, and Vision separately;
7. keep an unmodified upstream build available for A/B regression testing.

The upstream deterministic reservation exists for a reason: moving scratch back to transient allocation trades deterministic startup accounting for the possibility of a later runtime allocation failure if a future request needs more scratch than the remaining device memory can provide.
