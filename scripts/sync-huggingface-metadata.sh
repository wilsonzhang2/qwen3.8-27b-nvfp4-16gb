#!/usr/bin/env bash
set -euo pipefail

PY=/home/ai/.venvs/hf-publish/bin/python
REPO=QQZ2026/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP-GGUF
RAW=https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/zerorefusal-ud-iq4xs-mtp
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

curl -fsSL "$RAW/huggingface/README.md" -o "$STAGE/README.md"
curl -fsSL "$RAW/SHA256SUMS" -o "$STAGE/SHA256SUMS"
export REPO STAGE

"$PY" - <<'PY'
import os
from pathlib import Path
from huggingface_hub import HfApi

api = HfApi()
repo = os.environ["REPO"]
stage = Path(os.environ["STAGE"])
for name in ["README.md", "SHA256SUMS"]:
    api.upload_file(
        path_or_fileobj=str(stage / name),
        path_in_repo=name,
        repo_id=repo,
        repo_type="model",
        commit_message=f"Update {name}",
    )
info = api.model_info(repo)
print(f"pipeline_tag={info.pipeline_tag}")
print(f"library_name={info.library_name}")
PY
