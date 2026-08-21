#!/usr/bin/env bash
set -euo pipefail

REPO_ID="${HF_REPO_ID:-QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF}"
MODEL_NAME="Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf"
EXPECTED_SHA="49021e6e76af0ac6298e56aa4fab1ed56b62c7c66b6e7a18933907185bd1827d"
RAW_BASE="https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/lowdrift-ud-iq4xs-mtp"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$RAW_BASE/huggingface/README.md" -o "$TMP/README.md"
printf '%s  %s\n' "$EXPECTED_SHA" "$MODEL_NAME" > "$TMP/SHA256SUMS"

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
[[ -n "$PY" ]] || { echo "ERROR: no Python with huggingface_hub" >&2; exit 1; }

"$PY" - "$REPO_ID" "$TMP/README.md" "$TMP/SHA256SUMS" <<'PY'
import sys, time
from huggingface_hub import HfApi, hf_hub_download

repo_id, readme, sums = sys.argv[1:]
api = HfApi()
who = api.whoami()
print("Authenticated as:", who.get("name") or who)

license_path = hf_hub_download(
    repo_id="asfgsdfg/Qwen3.8-27B-Heretic",
    filename="LICENSE",
    repo_type="model",
)

for local_path, remote_path, msg in [
    (readme, "README.md", "Sync searchable model card metadata"),
    (sums, "SHA256SUMS", "Sync checksum"),
    (license_path, "LICENSE", "Add inherited Apache-2.0 license"),
]:
    print("Uploading", remote_path)
    api.upload_file(
        path_or_fileobj=local_path,
        path_in_repo=remote_path,
        repo_id=repo_id,
        repo_type="model",
        commit_message=msg,
    )

# Hub metadata can take a short moment to re-index after README update.
for i in range(12):
    time.sleep(5 if i else 2)
    info = api.model_info(repo_id=repo_id, files_metadata=True)
    files = {x.rfilename: x for x in info.siblings}
    print(
        f"check {i+1}: private={info.private} "
        f"pipeline_tag={info.pipeline_tag} "
        f"library_name={getattr(info, 'library_name', None)}"
    )
    if {"README.md", "SHA256SUMS", "LICENSE"}.issubset(files):
        card = getattr(info, "cardData", None) or {}
        # pipeline/library may be exposed either as top-level info attrs or cardData.
        pt = info.pipeline_tag or card.get("pipeline_tag")
        ln = getattr(info, "library_name", None) or card.get("library_name")
        if pt == "image-text-to-text" and ln == "gguf":
            print("HF METADATA SYNC: PASS")
            print("MODEL PAGE: https://huggingface.co/" + repo_id)
            raise SystemExit(0)

raise SystemExit("HF METADATA SYNC: files uploaded, but metadata index has not refreshed yet; rerun verifier in a few minutes")
PY
