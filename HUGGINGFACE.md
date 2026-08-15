# Hugging Face Publishing

## Published repository

The model has been successfully published at:

```text
https://huggingface.co/QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
```

Published files include:

```text
README.md
NOTICE
ATTRIBUTION.md
SHA256SUMS
Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
mmproj-Qwen3.8-27B-F16.gguf
```

Verified SHA256 checksums from the exact uploaded files:

```text
828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee  mmproj-Qwen3.8-27B-F16.gguf
```

The same checksums are stored in the GitHub repository root as [`SHA256SUMS`](SHA256SUMS).

## Model card source

The Hugging Face-ready model card is stored in this GitHub repository at:

```text
huggingface/README.md
```

The main GGUF is the physical no-MTP derivative. The `mmproj` is the matching F16 Vision projector converted from the official `Qwen/Qwen3.8-27B` checkpoint.

## Re-publication helper

The helper script is:

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

The helper validates the physical no-MTP structure before upload, calculates SHA256 for both artifacts, stages the model card / notices / checksums, and uploads the main GGUF plus matching Vision mmproj.

Locally validated paths:

```text
/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
```

The script enables `HF_XET_HIGH_PERFORMANCE=1` unless already overridden.

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
