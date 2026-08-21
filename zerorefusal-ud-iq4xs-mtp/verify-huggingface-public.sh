#!/usr/bin/env bash
set -euo pipefail

PY=/home/ai/.venvs/hf-publish/bin/python
REPO=QQZ2026/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP-GGUF
OLD_REPO=QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF
MODEL=Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
EXPECTED_SIZE=14252845024
export REPO OLD_REPO MODEL EXPECTED_SIZE

"$PY" - <<'PY'
import os
import time
from huggingface_hub import HfApi
from huggingface_hub.errors import HfHubHTTPError

api = HfApi()
repo = os.environ["REPO"]
old_repo = os.environ["OLD_REPO"]
model = os.environ["MODEL"]
expected_size = int(os.environ["EXPECTED_SIZE"])

info = api.model_info(repo, files_metadata=True)
if info.private:
    raise SystemExit("repository is private")
if info.pipeline_tag != "image-text-to-text":
    raise SystemExit(f"pipeline_tag={info.pipeline_tag!r}")
if info.library_name != "gguf":
    raise SystemExit(f"library_name={info.library_name!r}")

files = {item.rfilename: item.size for item in info.siblings}
for name in [model, "README.md", "SHA256SUMS", "LICENSE"]:
    if name not in files:
        raise SystemExit(f"missing: {name}")
if files[model] != expected_size:
    raise SystemExit(f"size mismatch: {files[model]}")

try:
    api.model_info(old_repo)
except HfHubHTTPError as exc:
    if getattr(exc.response, "status_code", None) != 404:
        raise
else:
    raise SystemExit(f"superseded repository still exists: {old_repo}")

queries = [repo, "Qwen3.8 ZeroRefusal IQ4_XS MTP"]
for attempt in range(30):
    found = set()
    for query in queries:
        found.update(m.id for m in api.list_models(search=query, limit=50))
    if repo in found:
        break
    if attempt == 29:
        raise SystemExit("repository has not appeared in Hub search index")
    time.sleep(20)

print(f"private: {info.private}")
print(f"pipeline_tag: {info.pipeline_tag}")
print(f"library_name: {info.library_name}")
print(f"file OK: {model} {files[model]}")
print("search index: OK")
PY

curl -fsIL -o /dev/null \
  "https://huggingface.co/${REPO}/resolve/main/${MODEL}?download=true"

echo "PUBLIC RELEASE VERIFY: PASS"
