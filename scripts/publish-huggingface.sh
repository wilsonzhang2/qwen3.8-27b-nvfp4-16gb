#!/usr/bin/env bash
set -euo pipefail

# Default repository matches the Hugging Face account used by the related
# Qwen3.6 deployment project. Override HF_REPO if needed.
HF_REPO="${HF_REPO:-QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF}"
MODEL="${MODEL:-/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf}"
MMPROJ="${MMPROJ:-/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf}"
CARD="${CARD:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/huggingface/README.md}"

command -v hf >/dev/null 2>&1 || {
  echo "ERROR: 'hf' CLI not found. Install/update huggingface_hub first." >&2
  exit 1
}

for f in "$MODEL" "$MMPROJ" "$CARD"; do
  [[ -f "$f" ]] || {
    echo "ERROR: missing file: $f" >&2
    exit 1
  }
done

# Current Hugging Face guidance uses hf_xet for large transfers. This enables
# its high-performance mode when available.
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

TOKEN_ARGS=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  TOKEN_ARGS=(--token "$HF_TOKEN")
fi

echo "Repository : $HF_REPO"
echo "Model      : $MODEL"
echo "mmproj     : $MMPROJ"
echo "Model card : $CARD"
echo

echo "[1/3] Uploading README.md (repo is created automatically if needed)..."
hf upload "$HF_REPO" "$CARD" README.md \
  --commit-message "Add Qwen3.8 no-MTP 16GB deployment model card" \
  "${TOKEN_ARGS[@]}"

echo "[2/3] Uploading no-MTP GGUF..."
hf upload "$HF_REPO" "$MODEL" "$(basename "$MODEL")" \
  --commit-message "Upload Qwen3.8-27B NVFP4 Q5K physical no-MTP GGUF" \
  "${TOKEN_ARGS[@]}"

echo "[3/3] Uploading F16 Vision mmproj..."
hf upload "$HF_REPO" "$MMPROJ" "$(basename "$MMPROJ")" \
  --commit-message "Upload matching Qwen3.8 F16 Vision mmproj" \
  "${TOKEN_ARGS[@]}"

echo
echo "DONE: https://huggingface.co/$HF_REPO"
