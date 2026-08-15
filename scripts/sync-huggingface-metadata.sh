#!/usr/bin/env bash
set -Eeuo pipefail

HF_REPO=${HF_REPO:-QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF}
GH_RAW=${GH_RAW:-https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main}
HF_VENV=${HF_VENV:-/home/ai/.venvs/hf-publish}
EXPECTED_PATCH_SHA256=1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b
MODEL_SHA256=828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66
MMPROJ_SHA256=71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee

command -v curl >/dev/null || { echo "ERROR: curl not found" >&2; exit 1; }

# Non-interactive SSH does not necessarily load ~/.bashrc, so the hf CLI from the
# publishing virtualenv may not be on PATH. Reuse the exact venv created by the
# original model publication before attempting to install anything.
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

command -v hf >/dev/null || { echo "ERROR: hf CLI still not found after activating $HF_VENV" >&2; exit 1; }

if ! hf auth whoami >/dev/null 2>&1; then
  echo "ERROR: Hugging Face authentication is not available in this account/venv." >&2
  echo "Run: $HF_VENV/bin/hf auth login" >&2
  exit 1
fi

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

cat >> "$TMP/README.md" <<EOF

---

## Exact release artifacts

The public model files for this release were uploaded from the validated VM101 system with these SHA256 checksums:

\`\`\`text
${MODEL_SHA256}  Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
${MMPROJ_SHA256}  mmproj-Qwen3.8-27B-F16.gguf
\`\`\`

The exact llama.cpp b10435 transient Flash-Attention patch used for the 16 GB validation is also published in this model repository:

\`\`\`text
${EXPECTED_PATCH_SHA256}  patches/b10435-fa-transient-final.patch
\`\`\`

The patch is revision-specific to:

\`\`\`text
llama.cpp b10435
9e40df63ba151d771d8b247ac4011cf203337e99
\`\`\`

See \`PATCH-NOTES.md\` and \`RELEASE.md\` for its exact scope, measured VRAM behavior, high-water caveat, and safe application procedure. The source repository is:

\`\`\`text
https://github.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb
\`\`\`
EOF

echo "Hugging Face CLI: $(command -v hf)"
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
