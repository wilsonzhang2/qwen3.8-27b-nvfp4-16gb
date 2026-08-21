#!/usr/bin/env bash
set -euo pipefail

REPO_ID="${HF_REPO_ID:-QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF}"
FILE="Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf"
EXPECTED_SIZE=14252845184

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

[[ -n "$PY" ]] || { echo "No Python with huggingface_hub" >&2; exit 1; }

"$PY" - "$REPO_ID" "$FILE" "$EXPECTED_SIZE" <<'PY'
import sys
import time
from urllib.request import Request, urlopen
from huggingface_hub import HfApi

repo, filename, expected_size = sys.argv[1], sys.argv[2], int(sys.argv[3])
api = HfApi()
info = api.model_info(repo_id=repo, files_metadata=True)

print("repo:", info.id)
print("private:", info.private)
print("pipeline_tag:", info.pipeline_tag)
print("library_name:", getattr(info, "library_name", None))
print("tags:", ", ".join(info.tags or []))

if info.private:
    raise SystemExit("ERROR: repository is private")

files = {x.rfilename: x for x in info.siblings}
for required in (filename, "README.md", "SHA256SUMS", "LICENSE"):
    if required not in files:
        raise SystemExit(f"MISSING: {required}")
    print("file OK:", required, getattr(files[required], "size", None))

remote_size = getattr(files[filename], "size", None)
if remote_size is not None and remote_size != expected_size:
    raise SystemExit(f"SIZE MISMATCH: {remote_size} != {expected_size}")

url = f"https://huggingface.co/{repo}/resolve/main/{filename}?download=true"
req = Request(url, method="HEAD", headers={"User-Agent": "release-verifier/1.0"})
with urlopen(req, timeout=60) as r:
    print("download HTTP:", r.status)
    print("resolved URL host:", r.geturl().split('/')[2])

# Hub search indexing can lag behind the repository commit. Poll up to 5 minutes.
queries = [
    "Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP",
    "Qwen3.8 LowDrift IQ4_XS MTP",
]
indexed = False
for attempt in range(16):
    for q in queries:
        ids = {m.id for m in api.list_models(search=q, limit=50)}
        if repo in ids:
            print("search query OK:", q)
            indexed = True
            break
    if indexed:
        break
    if attempt < 15:
        print(f"search index pending; retry {attempt + 1}/15 in 20s")
        time.sleep(20)

if not indexed:
    raise SystemExit("ERROR: repository is public/downloadable but not yet returned by Hub search after 5 minutes")

print("PUBLIC RELEASE VERIFY: PASS")
print("model page:", f"https://huggingface.co/{repo}")
print("download:", url)
PY
