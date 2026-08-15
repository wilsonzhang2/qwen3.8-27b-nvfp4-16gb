# Hugging Face Publishing

## Published repository

The model has been successfully published at:

```text
https://huggingface.co/QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
```

Published model artifacts:

```text
828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee  mmproj-Qwen3.8-27B-F16.gguf
```

These are the checksums from the exact VM101 files uploaded to Hugging Face. They are also stored in the GitHub repository root as [`SHA256SUMS`](SHA256SUMS).

## Exact llama.cpp patch artifact

The exact tested b10435 transient Flash-Attention patch is stored at:

[`patches/b10435-fa-transient-final.patch`](patches/b10435-fa-transient-final.patch)

Verified patch SHA256:

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  b10435-fa-transient-final.patch
```

The patch is **8,251 bytes / 206 lines** and is byte-identical to the uploaded VM101 file. Git blob SHA for the repository object is:

```text
36155122737b86f532880f31b690e7cf1aa382a8
```

See [`PATCH-NOTES.md`](PATCH-NOTES.md) before using it. The helper [`scripts/apply-b10435-fa-transient.sh`](scripts/apply-b10435-fa-transient.sh) verifies both the exact llama.cpp base commit and the patch SHA256 before applying it.

## Model card source

The Hugging Face-ready model card is stored in this GitHub repository at:

```text
huggingface/README.md
```

The main GGUF is the physical no-MTP derivative. The `mmproj` is the matching F16 Vision projector converted from the official `Qwen/Qwen3.8-27B` checkpoint.

## Lightweight metadata sync

After documentation or patch metadata changes in GitHub, there is no need to re-upload the 15.5 GB model weights.

Use:

```text
scripts/sync-huggingface-metadata.sh
```

It uploads only:

```text
README.md
PATCH-NOTES.md
RELEASE.md
PATCH_SHA256SUMS
patches/b10435-fa-transient-final.patch
```

The script verifies the exact patch SHA256 before publishing.

## Full re-publication helper

The full helper remains:

```text
scripts/publish-huggingface.sh
```

Default target repository:

```text
QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
```

From VM101 / a clone of this repository:

```bash
chmod +x scripts/publish-huggingface.sh
scripts/publish-huggingface.sh
```

The full helper validates the physical no-MTP structure before upload, calculates SHA256 for both model artifacts, stages the model card / notices / checksums, and uploads the main GGUF plus matching Vision mmproj.

Locally validated paths:

```text
/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
```

## Authentication

Use `hf auth login` with a token that has write permission to the target repository. Never commit a Hugging Face access token into this GitHub repository.

## Published deployment description

> Qwen3.8-27B NVFP4/Q5K physical no-MTP GGUF, validated on an RTX 5060 Ti 16 GB with 64K shared KV, P2 continuous batching, full-GPU text inference, and native Qwen3.8 Vision using a CPU-resident F16 mmproj.

## Tags

```text
gguf
qwen
qwen3.8
nvfp4
llama.cpp
multimodal
vision
no-mtp
rtx-5060-ti
16gb-vram
```
