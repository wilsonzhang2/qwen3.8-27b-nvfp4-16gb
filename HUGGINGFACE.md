# Hugging Face Publishing

The Hugging Face-ready model card is stored at:

```text
huggingface/README.md
```

The helper script is:

```text
scripts/publish-huggingface.sh
```

Default target repository:

```text
QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
```

Override it with `HF_REPO` if a different account or repository name is preferred.

## Files to publish

Recommended model repository contents:

```text
README.md
Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
mmproj-Qwen3.8-27B-F16.gguf
```

The main GGUF is the physical no-MTP derivative. The `mmproj` is the matching F16 Vision projector converted from the official `Qwen/Qwen3.8-27B` checkpoint.

## Authentication

Install/update `huggingface_hub` so the `hf` CLI is available, then authenticate with a token that has write permission to the target repository.

The publishing helper uses the token already saved by `hf auth login`. It also accepts an `HF_TOKEN` environment variable.

Never commit a Hugging Face access token into this GitHub repository.

## Publish from VM101

From a clone of this repository:

```bash
chmod +x scripts/publish-huggingface.sh
scripts/publish-huggingface.sh
```

The script defaults to the locally validated paths:

```text
/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
```

Override them if necessary:

```bash
MODEL=/other/path/model.gguf \
MMPROJ=/other/path/mmproj.gguf \
HF_REPO=username/repository \
scripts/publish-huggingface.sh
```

The script enables:

```text
HF_XET_HIGH_PERFORMANCE=1
```

unless that environment variable is already set.

## Before public release

Verify these items before making the model repository public:

```text
[ ] no-MTP GGUF loads successfully
[ ] metadata reports 64 blocks
[ ] nextn_predict_layers = 0
[ ] highest remaining transformer block is 63
[ ] matching mmproj identifies Qwen3 Vision projector metadata
[ ] SHA256 recorded locally for both GGUF files
[ ] source GGUF attribution identified
[ ] current upstream Qwen license checked
[ ] current source-quantization license checked
```

Do not publish a guessed SHA256. Record hashes from the exact files being uploaded.

## Suggested model-repository description

> Qwen3.8-27B NVFP4/Q5K physical no-MTP GGUF, validated on an RTX 5060 Ti 16 GB with 64K shared KV, P2 continuous batching, full-GPU text inference, and native Qwen3.8 Vision using a CPU-resident F16 mmproj.

## Suggested tags

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

## Large-file note

The model GGUF is large. Use the `hf` CLI rather than normal Git commits for the Hugging Face upload. Re-running the same `hf upload` command is the intended recovery path if the transfer is interrupted.
