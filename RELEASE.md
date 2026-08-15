# Release Manifest — 2026-08-15

This document records the public artifacts and the exact local validation target used for the first Qwen3.8-27B no-MTP 16 GB release.

## Public repositories

GitHub:

```text
https://github.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb
```

Hugging Face:

```text
https://huggingface.co/QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
```

## Published model artifacts

```text
828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee  mmproj-Qwen3.8-27B-F16.gguf
```

These hashes were computed from the exact VM101 files uploaded to Hugging Face.

## Exact tested llama.cpp patch artifact

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  patches/b10435-fa-transient-final.patch
```

Patch file:

[`patches/b10435-fa-transient-final.patch`](patches/b10435-fa-transient-final.patch)

The uploaded patch is **8,251 bytes / 206 lines** and was copied from the exact file used on VM101 after the successful 2026-08-15 validation.

A separate checksum file is stored at [`PATCH_SHA256SUMS`](PATCH_SHA256SUMS).

## llama.cpp validation base

```text
build:  b10435
commit: 9e40df63ba151d771d8b247ac4011cf203337e99
CUDA target: SM120
```

Important build settings:

```text
GGML_CUDA=ON
CMAKE_CUDA_ARCHITECTURES=120
GGML_CUDA_FA_ALL_QUANTS=ON
CMAKE_BUILD_TYPE=Release
```

## Physical no-MTP structure

Expected structure of the published main GGUF:

```text
qwen35.block_count = 64
qwen35.nextn_predict_layers = 0
highest transformer block = blk.63
MTP / NextN tensors removed = 15
physical reduction from source GGUF = 227.91 MiB
```

Retained tensors were copied without requantization.

## Validated deployment target

```text
GPU: RTX 5060 Ti 16 GB
context: 64000 shared tokens
parallel slots: 2
KV: q4_0 K + q4_0 V
text backbone: full GPU (-ngl 999)
Vision: F16 mmproj on CPU (--no-mmproj-offload)
MTP: disabled / physically removed
```

Recommended server profile is documented in `DEPLOYMENT.md` and `scripts/run-64k-p2-vision.sh`.

## Key measured results

| Test | Measured result |
|---|---:|
| 32K / P1 / full-GPU decode | 25.88 tok/s |
| 72K / P1 / full-GPU decode | 25.85 tok/s |
| 64K / P2 concurrent decode A | 24.35 tok/s |
| 64K / P2 concurrent decode B | 24.48 tok/s |
| Approx. aggregate P2 decode | 48.8 tok/s |
| Vision text decode after preprocessing | 25.24 tok/s |
| 40,103-token MAIN + simultaneous Vision CS | passed |
| Combined stress-test high-water | 15,718 MiB used / 172 MiB free |

No CUDA OOM was observed in the final 40K MAIN + simultaneous real-image customer-service stress test.

## Transient Flash-Attention patch

The production-like validation used the exact b10435-specific patch above. Its behavior and caveats are documented in [`PATCH-NOTES.md`](PATCH-NOTES.md).

The patch changes when quantized-KV Flash-Attention F16 dequant scratch is committed. It improved startup headroom from approximately **124 MiB free to 364 MiB free** in the 64K/P2/full-GPU profile, but long-context work grows the CUDA pool to a high-water mark. It is therefore **not** a permanent worst-case 240 MiB saving.

The patch is paired with the exact llama.cpp base commit above. `scripts/apply-b10435-fa-transient.sh` verifies both the base commit and patch SHA256 before applying it.

## Release scope

This is an independent community deployment/validation release. Performance values are local measurements from one RTX 5060 Ti system, not standardized cross-platform benchmark claims.
