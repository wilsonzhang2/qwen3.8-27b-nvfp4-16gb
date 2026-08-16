# Hugging Face Publishing

## Published repository

```text
https://huggingface.co/QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
```

Published artifacts:

```text
828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee  mmproj-Qwen3.8-27B-F16.gguf
```

## Current public deployment description

> Qwen3.8-27B NVFP4/Q5K physical no-MTP GGUF, validated on an RTX 5060 Ti 16 GB with **66K shared KV**, **P2 unified KV**, full-GPU text inference, native Qwen3.8 Vision using a CPU-resident F16 mmproj, `--image-max-tokens 4096`, and **clean upstream llama.cpp b10435 with no local FA patch**.

## Patch status

The exact historical transient Flash-Attention patch remains published for reproducibility:

```text
1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b  patches/b10435-fa-transient-final.patch
```

It is now classified as **experimental / research-only**. Later P2 + Vision A/B testing showed repeatable stepwise VRAM growth in the patched path, while the final clean upstream 66K/P2 profile stabilized after first-use warm-up.

The Hugging Face model card should therefore clearly say:

```text
Recommended production build: upstream b10435, NO PATCH
Historical patch: published only for reproduction/research
```

See `PATCH-NOTES.md` for details.

## Model card source

The source of the Hugging Face `README.md` is:

```text
huggingface/README.md
```

It now documents the 2026-08-16 best 16 GB profile:

```text
-c 66000
-np 2
--kv-unified
-ngl 999
-ctk q4_0
-ctv q4_0
--no-mmproj-offload
--image-max-tokens 4096
NO MTP
NO PATCH
```

## Lightweight metadata sync

There is no need to re-upload the ~15.5 GB model weights when only documentation changes.

Run on VM101:

```bash
curl -fsSL https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/scripts/sync-huggingface-metadata.sh | bash
```

The sync publishes only documentation/checksum/patch metadata and does not replace the model GGUF or mmproj.

The script verifies the historical patch SHA256 before uploading it.

## Authentication

The publishing virtualenv is expected at:

```text
/home/ai/.venvs/hf-publish
```

The script reuses the existing Hugging Face login when available. If authentication is missing:

```bash
/home/ai/.venvs/hf-publish/bin/hf auth login
```

Never commit a Hugging Face token into GitHub.

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
