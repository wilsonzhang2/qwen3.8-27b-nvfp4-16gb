#!/usr/bin/env bash
set -Eeuo pipefail

MODEL="${MODEL:-/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf}"
MMPROJ="${MMPROJ:-/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf}"
REPO_NAME="${HF_REPO_NAME:-Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF}"
WORK_DIR="${WORK_DIR:-/home/ai/qwen38-publish}"
VENV="${HF_VENV:-/home/ai/.venvs/hf-publish}"
GGUF_PY="${GGUF_PY:-/opt/llama.cpp-qwen38/gguf-py}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$MODEL" ]] || fail "model not found: $MODEL"
[[ -f "$MMPROJ" ]] || fail "mmproj not found: $MMPROJ"
[[ -f "$WORK_DIR/README.md" ]] || fail "missing Hugging Face README: $WORK_DIR/README.md"
[[ -f "$WORK_DIR/NOTICE" ]] || fail "missing NOTICE: $WORK_DIR/NOTICE"
[[ -f "$WORK_DIR/ATTRIBUTION.md" ]] || fail "missing ATTRIBUTION.md: $WORK_DIR/ATTRIBUTION.md"
[[ -d "$GGUF_PY" ]] || fail "gguf-py not found: $GGUF_PY"

MODEL_NAME=$(basename "$MODEL")
MMPROJ_NAME=$(basename "$MMPROJ")
MODEL_SIZE=$(stat -c %s "$MODEL")
MMPROJ_SIZE=$(stat -c %s "$MMPROJ")
MODEL_SHA=$(sha256sum "$MODEL" | awk '{print $1}')
MMPROJ_SHA=$(sha256sum "$MMPROJ" | awk '{print $1}')

echo "===== VERIFY NO-MTP MODEL METADATA ====="
PYTHONPATH="$GGUF_PY" python3 - "$MODEL" <<'PY'
import sys
import gguf

p = sys.argv[1]
r = gguf.GGUFReader(p, "r")

def scalar(name):
    f = r.get_field(name)
    if f is None:
        raise SystemExit(f"ERROR: missing metadata: {name}")
    v = f.contents()
    try:
        return v.item()
    except AttributeError:
        return v

arch = str(scalar(gguf.Keys.General.ARCHITECTURE))
blocks = int(scalar(f"{arch}.block_count"))
nextn = int(scalar(f"{arch}.nextn_predict_layers"))
max_blk = -1
for t in r.tensors:
    if t.name.startswith("blk."):
        try:
            max_blk = max(max_blk, int(t.name.split(".", 2)[1]))
        except (ValueError, IndexError):
            pass

print("architecture         =", arch)
print("block_count          =", blocks)
print("nextn_predict_layers =", nextn)
print("highest block        =", max_blk)

if blocks != 64:
    raise SystemExit(f"ERROR: expected block_count=64, got {blocks}")
if nextn != 0:
    raise SystemExit(f"ERROR: expected nextn_predict_layers=0, got {nextn}")
if max_blk != 63:
    raise SystemExit(f"ERROR: expected highest block=63, got {max_blk}")
PY

echo "===== VERIFY VISION PROJECTOR METADATA ====="
PYTHONPATH="$GGUF_PY" python3 - "$MMPROJ" <<'PY'
import sys
import gguf

p = sys.argv[1]
r = gguf.GGUFReader(p, "r")
projector = r.get_field("clip.projector_type")
if projector is None:
    raise SystemExit("ERROR: clip.projector_type missing from mmproj")
value = projector.contents()
try:
    value = value.item()
except AttributeError:
    pass
print("clip.projector_type =", value)
print("tensor_count        =", len(r.tensors))
if len(r.tensors) < 100:
    raise SystemExit("ERROR: mmproj tensor count is unexpectedly small")
PY

echo "===== LOCAL FILE IDENTITIES ====="
printf 'Model : %s bytes  %s  %s\n' "$MODEL_SIZE" "$MODEL_SHA" "$MODEL_NAME"
printf 'mmproj: %s bytes  %s  %s\n' "$MMPROJ_SIZE" "$MMPROJ_SHA" "$MMPROJ_NAME"

python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip
python -m pip install --upgrade huggingface_hub hf_xet

if ! hf auth whoami >/dev/null 2>&1; then
    echo
    echo "Hugging Face authentication is required."
    echo "Use a token with WRITE permission when prompted."
    hf auth login
fi

HF_USER=$(python - <<'PY'
from huggingface_hub import HfApi
info = HfApi().whoami()
print(info["name"])
PY
)
[[ -n "$HF_USER" ]] || fail "could not determine Hugging Face username"

HF_REPO_ID="${HF_REPO:-$HF_USER/$REPO_NAME}"
export HF_REPO_ID

python - <<'PY'
import os
from huggingface_hub import HfApi
repo_id = os.environ["HF_REPO_ID"]
HfApi().create_repo(repo_id=repo_id, repo_type="model", private=False, exist_ok=True)
print("Repository ready:", repo_id)
PY

STAGE="$WORK_DIR/hf-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$WORK_DIR/README.md" "$STAGE/README.md"
cp "$WORK_DIR/NOTICE" "$STAGE/NOTICE"
cp "$WORK_DIR/ATTRIBUTION.md" "$STAGE/ATTRIBUTION.md"
printf '%s  %s\n%s  %s\n' \
    "$MODEL_SHA" "$MODEL_NAME" \
    "$MMPROJ_SHA" "$MMPROJ_NAME" \
    > "$STAGE/SHA256SUMS"

export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

echo
echo "===== UPLOAD MODEL CARD / NOTICE / CHECKSUMS ====="
hf upload "$HF_REPO_ID" "$STAGE" . \
    --repo-type model \
    --commit-message "Publish Qwen3.8 no-MTP model card and deployment metadata"

echo
echo "===== UPLOAD PHYSICAL NO-MTP GGUF ====="
hf upload "$HF_REPO_ID" "$MODEL" "$MODEL_NAME" \
    --repo-type model \
    --commit-message "Upload Qwen3.8-27B NVFP4 Q5K physical no-MTP GGUF"

echo
echo "===== UPLOAD MATCHING F16 VISION MMPROJ ====="
hf upload "$HF_REPO_ID" "$MMPROJ" "$MMPROJ_NAME" \
    --repo-type model \
    --commit-message "Upload matching Qwen3.8 F16 Vision mmproj"

HF_REPO_URL="https://huggingface.co/$HF_REPO_ID"
printf '%s\n' "$HF_REPO_URL" | tee "$WORK_DIR/HF_REPO_URL.txt"
cp "$STAGE/SHA256SUMS" "$WORK_DIR/SHA256SUMS"

echo
echo "Hugging Face publication completed: $HF_REPO_URL"
