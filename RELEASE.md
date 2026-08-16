# Release Manifest — Qwen3.8-27B no-MTP 16 GB

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

## Current production update — 2026-08-16

The best validated 16 GB deployment changed after additional repeated P2 + Vision testing.

Current production recommendation:

```text
GPU: RTX 5060 Ti 16 GB
llama.cpp: upstream b10435 / 9e40df63ba151d771d8b247ac4011cf203337e99
FA patch: NONE
context: 66000 shared tokens
parallel slots: 2
KV: unified q4_0 K + q4_0 V
text backbone: full GPU (-ngl 999)
Vision: F16 mmproj on CPU (--no-mmproj-offload)
image cap: --image-max-tokens 4096
MTP: disabled / physically removed
```

Measured memory:

```text
fresh startup:             15,810 MiB used / 80 MiB free
post first warm-up:        15,816 MiB used / 74 MiB free
later repeated stress:     no further VRAM growth observed
```

Repeated validation workload:

```text
MAIN:   ~40K prompt + 2,048 generated tokens
Vision: real image, ~4,042-4,084 prompt tokens with image-max-tokens 4096
```

The concurrent workload completed repeatedly without CUDA OOM.

## Why the patch is no longer the recommended production path

Historical patch artifact:

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  patches/b10435-fa-transient-final.patch
```

The patch remains published for reproducibility. It previously increased 64K/P2 startup headroom from approximately 124 MiB free to 364 MiB free by moving quantized-KV Flash-Attention dequant scratch back to transient CUDA-pool allocation.

Later repeated P2 + Vision testing showed undesirable stepwise memory growth under the patched path. A 68K sequence measured approximately:

```text
15,778 MiB
15,796 MiB (+18 MiB)
15,814 MiB (+18 MiB)
```

The same characteristic stepping was observed again after returning to 64K with the patched P2 + Vision path.

A clean upstream/no-patch 66K/P2 configuration, after adding `--image-max-tokens 4096`, stabilized after only a small first-use warm-up increase. For that reason the patch is now classified as **experimental/research-only**, not the recommended production deployment.

See `PATCH-NOTES.md` for the full A/B notes.

## Why image-max-tokens 4096 was added

Uncapped dynamic-resolution Vision produced very large prompt sizes in some first-image tests, including ~22K and ~35.7K tokens. In one 66K/P2 run the combined live KV reached:

```text
Vision slot: 35,679
MAIN slot:   30,432
combined:    66,111
```

The server then correctly returned `Context size has been exceeded`; this was a shared-KV capacity failure, not a CUDA OOM.

With `--image-max-tokens 4096`, the tested Vision workload stayed around 4K prompt tokens and the intended mixed-agent workload became practical.

## Physical no-MTP structure

```text
qwen35.block_count = 64
qwen35.nextn_predict_layers = 0
highest transformer block = blk.63
MTP / NextN tensors removed = 15
physical reduction from source GGUF = 227.91 MiB
```

Retained tensors were copied without requantization.

## Historical performance measurements

| Test | Measured result |
|---|---:|
| 32K / P1 / full-GPU decode | 25.88 tok/s |
| 72K / P1 / full-GPU decode | 25.85 tok/s |
| 64K / P2 concurrent decode A | 24.35 tok/s |
| 64K / P2 concurrent decode B | 24.48 tok/s |
| Approx. aggregate P2 decode | 48.8 tok/s |
| 66K/P2/no-patch MAIN decode under concurrent Vision | ~19.7-20.3 tok/s |

## Production helper

Exact VM101 promotion helper:

```text
scripts/promote-vm101-qwen38-66k-p2-nopatch.sh
```

It verifies the upstream b10435 commit and exact model/mmproj hashes before installing the systemd service.

## Release scope

This is an independent community deployment/validation release. The 66K result is intentionally aggressive and was measured on one RTX 5060 Ti 16 GB system with only ~74 MiB free after warm-up. Results are not a universal guarantee for other 16 GB GPUs, drivers, or llama.cpp revisions.
