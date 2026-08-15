#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_COMMIT=9e40df63ba151d771d8b247ac4011cf203337e99
EXPECTED_PATCH_SHA256=1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b
LLAMA_ROOT=${LLAMA_ROOT:-/opt/llama.cpp-qwen38}
PATCH_FILE=${PATCH_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/b10435-fa-transient-final.patch}

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$LLAMA_ROOT/.git" ]] || fail "not a llama.cpp git tree: $LLAMA_ROOT"
[[ -f "$PATCH_FILE" ]] || fail "patch file not found: $PATCH_FILE"

current=$(git -C "$LLAMA_ROOT" rev-parse HEAD)
[[ "$current" == "$EXPECTED_COMMIT" ]] || fail "wrong llama.cpp base commit: $current"

actual_patch_sha=$(sha256sum "$PATCH_FILE" | awk '{print $1}')
[[ "$actual_patch_sha" == "$EXPECTED_PATCH_SHA256" ]] || \
    fail "wrong patch SHA256: $actual_patch_sha"

if [[ -n "$(git -C "$LLAMA_ROOT" status --porcelain)" ]]; then
    fail "llama.cpp working tree is not clean; refusing to apply patch"
fi

echo "Base commit verified: $current"
echo "Patch SHA256 verified: $actual_patch_sha"

git -C "$LLAMA_ROOT" apply --check "$PATCH_FILE"
git -C "$LLAMA_ROOT" apply "$PATCH_FILE"
git -C "$LLAMA_ROOT" diff --check

echo
echo "Patch applied successfully. Review before rebuilding:"
git -C "$LLAMA_ROOT" status --short
git -C "$LLAMA_ROOT" diff --stat
