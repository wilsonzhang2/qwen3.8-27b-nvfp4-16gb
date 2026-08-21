#!/usr/bin/env bash
set -euo pipefail

PY=/home/ai/.venvs/hf-publish/bin/python
MODEL=/opt/models/qwen3.8-27b-zerorefusal-gguf/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
MODEL_NAME=Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
NEW_REPO=QQZ2026/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP-GGUF
OLD_REPO=QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF
EXPECTED_SIZE=14252845024
EXPECTED_SHA=18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
GITHUB_REF="${GITHUB_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/${GITHUB_REF}/zerorefusal-ud-iq4xs-mtp"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

export HF_XET_HIGH_PERFORMANCE=1
export HF_HUB_DISABLE_TELEMETRY=1
export MODEL MODEL_NAME NEW_REPO OLD_REPO EXPECTED_SIZE EXPECTED_SHA STAGE

test -x "$PY"
test -f "$MODEL"

actual_size="$(stat -c '%s' "$MODEL")"
actual_sha="$(sha256sum "$MODEL" | awk '{print $1}')"
test "$actual_size" = "$EXPECTED_SIZE"
test "$actual_sha" = "$EXPECTED_SHA"

curl -fsSL "$RAW_BASE/huggingface/README.md" -o "$STAGE/README.md"
curl -fsSL "$RAW_BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"

"$PY" - <<'PY'
import os
from pathlib import Path
from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.errors import HfHubHTTPError

api = HfApi()
stage = Path(os.environ["STAGE"])
new_repo = os.environ["NEW_REPO"]
old_repo = os.environ["OLD_REPO"]
model = Path(os.environ["MODEL"])
model_name = os.environ["MODEL_NAME"]
expected_size = int(os.environ["EXPECTED_SIZE"])

try:
    license_path = hf_hub_download(
        repo_id="junafinity/Qwen-3.8-27B-Uncensored",
        filename="LICENSE",
        local_dir=stage,
    )
except Exception:
    license_path = hf_hub_download(
        repo_id="Qwen/Qwen3.8-27B",
        filename="LICENSE",
        local_dir=stage,
    )

try:
    api.model_info(new_repo)
except HfHubHTTPError as exc:
    if getattr(exc.response, "status_code", None) != 404:
        raise
    api.create_repo(new_repo, repo_type="model", private=True, exist_ok=False)

for local, remote in [
    (stage / "README.md", "README.md"),
    (stage / "SHA256SUMS", "SHA256SUMS"),
    (Path(license_path), "LICENSE"),
]:
    api.upload_file(
        path_or_fileobj=str(local),
        path_in_repo=remote,
        repo_id=new_repo,
        repo_type="model",
        commit_message=f"Publish {remote}",
    )

api.upload_file(
    path_or_fileobj=str(model),
    path_in_repo=model_name,
    repo_id=new_repo,
    repo_type="model",
    commit_message="Publish ZeroRefusal UD-IQ4_XS MTP GGUF",
)

info = api.model_info(new_repo, files_metadata=True)
files = {item.rfilename: item.size for item in info.siblings}
required = {"README.md", "SHA256SUMS", "LICENSE", model_name}
missing = sorted(required - set(files))
if missing:
    raise SystemExit(f"missing remote files: {missing}")
if files[model_name] != expected_size:
    raise SystemExit(f"remote size mismatch: {files[model_name]}")

api.update_repo_settings(new_repo, repo_type="model", private=False)
public_info = api.model_info(new_repo, files_metadata=True)
if public_info.private:
    raise SystemExit("new repository is still private")
if public_info.pipeline_tag != "image-text-to-text":
    raise SystemExit(f"pipeline_tag mismatch: {public_info.pipeline_tag}")
if public_info.library_name != "gguf":
    raise SystemExit(f"library_name mismatch: {public_info.library_name}")

try:
    api.model_info(old_repo)
except HfHubHTTPError as exc:
    if getattr(exc.response, "status_code", None) != 404:
        raise
    print(f"old repository already absent: {old_repo}")
else:
    api.delete_repo(old_repo, repo_type="model")
    print(f"deleted superseded repository: {old_repo}")

print(f"new public repository: https://huggingface.co/{new_repo}")
PY

curl -fsIL -o /dev/null \
  "https://huggingface.co/${NEW_REPO}/resolve/main/${MODEL_NAME}?download=true"

echo "HUGGING FACE RELEASE: PASS"
