#!/usr/bin/env bash
set -euo pipefail

export HF_XET_HIGH_PERFORMANCE=1

REPO_ID="${HF_REPO_ID:-QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF}"
MODEL="${MODEL:-/opt/models/qwen3.8-27b-heretic-lowdrift-gguf/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf}"
EXPECTED_SHA="49021e6e76af0ac6298e56aa4fab1ed56b62c7c66b6e7a18933907185bd1827d"
RAW_BASE="https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/lowdrift-ud-iq4xs-mtp"

if [[ ! -f "$MODEL" ]]; then
  echo "ERROR: model not found: $MODEL" >&2
  exit 1
fi

ACTUAL_SHA="$(sha256sum "$MODEL" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "ERROR: SHA256 mismatch" >&2
  echo " expected: $EXPECTED_SHA" >&2
  echo " actual:   $ACTUAL_SHA" >&2
  exit 1
fi

echo "Model SHA256 verified: $ACTUAL_SHA"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$RAW_BASE/huggingface/README.md" -o "$TMP/README.md"
printf '%s  %s\n' "$EXPECTED_SHA" "$(basename "$MODEL")" > "$TMP/SHA256SUMS"

PY=""
for candidate in \
  /home/ai/.venvs/hf-publish/bin/python \
  /opt/llama.cpp-qwen38/.venv-convert/bin/python \
  python3; do
  if [[ -x "$candidate" ]] || command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" - <<'PY' >/dev/null 2>&1
import huggingface_hub
PY
    then
      PY="$candidate"
      break
    fi
  fi
done

if [[ -z "$PY" ]]; then
  echo "ERROR: no Python environment with huggingface_hub found" >&2
  exit 1
fi

echo "Using Python: $PY"
echo "Publishing to: $REPO_ID"

"$PY" - "$REPO_ID" "$MODEL" "$TMP/README.md" "$TMP/SHA256SUMS" <<'PY'
import os
import sys
from huggingface_hub import HfApi, hf_hub_download

repo_id, model, readme, sums = sys.argv[1:]
api = HfApi()

who = api.whoami()
print("Authenticated as:", who.get("name") or who)

api.create_repo(repo_id=repo_id, repo_type="model", private=False, exist_ok=True)

print("Fetching inherited Apache-2.0 LICENSE from behavioral source...")
license_path = hf_hub_download(
    repo_id="asfgsdfg/Qwen3.8-27B-Heretic",
    filename="LICENSE",
    repo_type="model",
)

uploads = [
    (model, os.path.basename(model), "Upload Qwen3.8-27B LowDrift UD-IQ4_XS MTP GGUF"),
    (readme, "README.md", "Add searchable model card and download instructions"),
    (sums, "SHA256SUMS", "Add SHA256 checksum"),
    (license_path, "LICENSE", "Add inherited Apache-2.0 license"),
]

for local_path, remote_path, message in uploads:
    print(f"Uploading {remote_path}...")
    api.upload_file(
        path_or_fileobj=local_path,
        path_in_repo=remote_path,
        repo_id=repo_id,
        repo_type="model",
        commit_message=message,
    )

print("Verifying public repository metadata...")
info = api.model_info(repo_id=repo_id, files_metadata=True)
files = {x.rfilename: x for x in info.siblings}
required = {
    os.path.basename(model),
    "README.md",
    "SHA256SUMS",
    "LICENSE",
}
missing = sorted(required - set(files))
if missing:
    raise SystemExit(f"ERROR: missing uploaded files: {missing}")

model_size = getattr(files[os.path.basename(model)], "size", None)
expected_size = os.path.getsize(model)
if model_size is not None and model_size != expected_size:
    raise SystemExit(
        f"ERROR: remote model size mismatch: remote={model_size} local={expected_size}"
    )

print("PUBLIC VERIFY: PASS")
print(f"MODEL PAGE: https://huggingface.co/{repo_id}")
print(
    "DIRECT FILE: https://huggingface.co/"
    + repo_id
    + "/resolve/main/"
    + os.path.basename(model)
)
PY
