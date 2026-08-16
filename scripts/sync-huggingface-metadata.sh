#!/usr/bin/env bash
set -Eeuo pipefail

HF_REPO=${HF_REPO:-QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF}
GH_RAW=${GH_RAW:-https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main}
HF_VENV=${HF_VENV:-/home/ai/.venvs/hf-publish}
EXPECTED_PATCH_SHA256=1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b

command -v curl >/dev/null || { echo "ERROR: curl not found" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "ERROR: sha256sum not found" >&2; exit 1; }

if ! command -v hf >/dev/null 2>&1; then
  if [[ -x "$HF_VENV/bin/hf" ]]; then
    # shellcheck disable=SC1091
    source "$HF_VENV/bin/activate"
  else
    echo "Hugging Face publish venv not found; creating: $HF_VENV"
    python3 -m venv "$HF_VENV"
    # shellcheck disable=SC1091
    source "$HF_VENV/bin/activate"
    python -m pip install --upgrade pip
    python -m pip install --upgrade huggingface_hub hf_xet
  fi
fi

command -v hf >/dev/null || { echo "ERROR: hf CLI unavailable" >&2; exit 1; }

if ! hf auth whoami >/dev/null 2>&1; then
  echo "ERROR: Hugging Face authentication is unavailable." >&2
  echo "Run: $HF_VENV/bin/hf auth login" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/patches"

curl -fsSL "$GH_RAW/huggingface/README.md" -o "$TMP/README.md"
curl -fsSL "$GH_RAW/DEPLOYMENT.md" -o "$TMP/DEPLOYMENT.md"
curl -fsSL "$GH_RAW/PATCH-NOTES.md" -o "$TMP/PATCH-NOTES.md"
curl -fsSL "$GH_RAW/RELEASE.md" -o "$TMP/RELEASE.md"
curl -fsSL "$GH_RAW/PATCH_SHA256SUMS" -o "$TMP/PATCH_SHA256SUMS"
curl -fsSL "$GH_RAW/patches/b10435-fa-transient-final.patch" -o "$TMP/patches/b10435-fa-transient-final.patch"

actual=$(sha256sum "$TMP/patches/b10435-fa-transient-final.patch" | awk '{print $1}')
[[ "$actual" == "$EXPECTED_PATCH_SHA256" ]] || {
  echo "ERROR: patch SHA256 mismatch: $actual" >&2
  exit 1
}

echo "Hugging Face account:"
hf auth whoami
echo
echo "Patch SHA256 verified: $actual"
echo "Publishing current metadata to: $HF_REPO"
echo "Production profile: 66K / P2 / full GPU / CPU Vision / image-max-tokens 4096 / no-MTP / NO PATCH"
echo

hf upload "$HF_REPO" "$TMP/README.md" README.md --repo-type model
hf upload "$HF_REPO" "$TMP/DEPLOYMENT.md" DEPLOYMENT.md --repo-type model
hf upload "$HF_REPO" "$TMP/PATCH-NOTES.md" PATCH-NOTES.md --repo-type model
hf upload "$HF_REPO" "$TMP/RELEASE.md" RELEASE.md --repo-type model
hf upload "$HF_REPO" "$TMP/PATCH_SHA256SUMS" PATCH_SHA256SUMS --repo-type model
hf upload "$HF_REPO" "$TMP/patches/b10435-fa-transient-final.patch" patches/b10435-fa-transient-final.patch --repo-type model

echo
echo "===== HUGGING FACE METADATA SYNC COMPLETE ====="
echo "Repository: https://huggingface.co/$HF_REPO"
echo "Model weights were not re-uploaded."
