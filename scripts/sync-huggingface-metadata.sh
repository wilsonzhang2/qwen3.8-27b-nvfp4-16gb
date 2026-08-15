#!/usr/bin/env bash
set -Eeuo pipefail

HF_REPO=${HF_REPO:-QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF}
GH_RAW=${GH_RAW:-https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main}
EXPECTED_PATCH_SHA256=1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b

command -v curl >/dev/null || { echo "ERROR: curl not found" >&2; exit 1; }
command -v hf >/dev/null || { echo "ERROR: hf CLI not found" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/patches"

curl -fsSL "$GH_RAW/huggingface/README.md" -o "$TMP/README.md"
curl -fsSL "$GH_RAW/PATCH-NOTES.md" -o "$TMP/PATCH-NOTES.md"
curl -fsSL "$GH_RAW/RELEASE.md" -o "$TMP/RELEASE.md"
curl -fsSL "$GH_RAW/PATCH_SHA256SUMS" -o "$TMP/PATCH_SHA256SUMS"
curl -fsSL "$GH_RAW/patches/b10435-fa-transient-final.patch" -o "$TMP/patches/b10435-fa-transient-final.patch"

actual=$(sha256sum "$TMP/patches/b10435-fa-transient-final.patch" | awk '{print $1}')
[[ "$actual" == "$EXPECTED_PATCH_SHA256" ]] || {
  echo "ERROR: patch SHA256 mismatch: $actual" >&2
  exit 1
}

echo "Patch SHA256 verified: $actual"
echo "Syncing documentation to: $HF_REPO"

hf upload "$HF_REPO" "$TMP/README.md" README.md --repo-type model
hf upload "$HF_REPO" "$TMP/PATCH-NOTES.md" PATCH-NOTES.md --repo-type model
hf upload "$HF_REPO" "$TMP/RELEASE.md" RELEASE.md --repo-type model
hf upload "$HF_REPO" "$TMP/PATCH_SHA256SUMS" PATCH_SHA256SUMS --repo-type model
hf upload "$HF_REPO" "$TMP/patches/b10435-fa-transient-final.patch" patches/b10435-fa-transient-final.patch --repo-type model

echo
echo "Hugging Face metadata sync completed."
echo "https://huggingface.co/$HF_REPO"
