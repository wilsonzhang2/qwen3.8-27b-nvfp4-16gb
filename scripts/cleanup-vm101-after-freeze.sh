#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_MODEL_SHA=828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66
EXPECTED_MMPROJ_SHA=71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee
EXPECTED_GIT_HEAD=64486c42ce1a578845bc4b71a271c24cb04f1a43
EXPECTED_TAG=qwen38-prod-20260815

MODEL=/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
MMPROJ=/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
LLAMA=/opt/llama.cpp-qwen38
SNAP=/opt/qwen38-production/2026-08-15
SERVICE=qwen27b.service

fail(){ echo "ERROR: $*" >&2; exit 1; }

sudo -v

echo "===== PRE-FLIGHT PRODUCTION VERIFICATION ====="
[[ -f "$MODEL" ]] || fail "production model missing"
[[ -f "$MMPROJ" ]] || fail "production mmproj missing"
[[ -d "$LLAMA/.git" ]] || fail "production llama.cpp tree missing"
[[ -d "$SNAP" ]] || fail "production snapshot missing"

model_sha=$(sha256sum "$MODEL" | awk '{print $1}')
mmproj_sha=$(sha256sum "$MMPROJ" | awk '{print $1}')
head_sha=$(git -C "$LLAMA" rev-parse HEAD)

[[ "$model_sha" == "$EXPECTED_MODEL_SHA" ]] || fail "production model SHA mismatch: $model_sha"
[[ "$mmproj_sha" == "$EXPECTED_MMPROJ_SHA" ]] || fail "production mmproj SHA mismatch: $mmproj_sha"
[[ "$head_sha" == "$EXPECTED_GIT_HEAD" ]] || fail "production llama.cpp HEAD mismatch: $head_sha"
git -C "$LLAMA" rev-parse "$EXPECTED_TAG^{commit}" >/dev/null 2>&1 || fail "production tag missing: $EXPECTED_TAG"

systemctl is-enabled --quiet "$SERVICE" || fail "$SERVICE is not enabled"
systemctl is-active --quiet "$SERVICE" || fail "$SERVICE is not active"

unit=$(systemctl cat "$SERVICE")
grep -Fq "$MODEL" <<<"$unit" || fail "service does not reference production model"
grep -Fq "$MMPROJ" <<<"$unit" || fail "service does not reference production mmproj"
grep -Fq '/opt/llama.cpp-qwen38/build/bin/llama-server' <<<"$unit" || fail "service does not reference production llama-server"

curl -fsS http://127.0.0.1:8001/health >/dev/null || fail "production API health check failed"

echo "Production model / mmproj / git commit / service / API verified."

echo
echo "===== SPACE BEFORE ====="
df -h /

# Preserve tiny test evidence before deleting it from $HOME.
echo
echo "===== ARCHIVE TEST EVIDENCE ====="
EVID="$SNAP/test-evidence"
sudo mkdir -p "$EVID"
shopt -s nullglob
files=(
  /home/ai/qwen38-*.log
  /home/ai/qwen38-*.csv
  /home/ai/qwen38-*.txt
  /home/ai/b10435-*.patch
  /home/ai/b10435-*.log
  /home/ai/llama-patch-audit-20260815/*.txt
  /home/ai/llama-patch-audit-20260815/*.patch
)
if ((${#files[@]})); then
  sudo cp -a "${files[@]}" "$EVID/" 2>/dev/null || true
fi
sudo sh -c "find '$EVID' -maxdepth 1 -type f -print0 | sort -z | xargs -0 -r sha256sum > '$EVID/SHA256SUMS'"
echo "Evidence archived under: $EVID"

# Refuse to remove old llama trees if any current process is actually executing them.
echo
echo "===== CHECK OLD LLAMA TREES ARE UNUSED ====="
if pgrep -af '/opt/llama\.cpp(/|$)|/opt/llama\.cpp\.pre-610-20260730-055401(/|$)' | grep -v 'pgrep -af' ; then
  fail "an old llama.cpp tree appears to be in use"
fi
echo "No running process uses the old llama.cpp trees."

# Large, superseded model artifacts. Production no-MTP + mmproj remain untouched.
echo
echo "===== REMOVE SUPERSEDED MODEL ARTIFACTS ====="
sudo rm -rf -- \
  /opt/models/qwen3.6-27b-utautako \
  /opt/models/qwen3.8-27b-nvfp4 \
  /opt/models/qwen3.8-27b-nvfp4-test
sudo rm -f -- /opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-mtp.gguf
sudo rm -rf -- /opt/models/qwen3.8-27b-avifenesh/.cache

echo "Kept production artifacts:"
ls -lh "$MODEL" "$MMPROJ"

# Only the frozen qwen38 tree remains.
echo
echo "===== REMOVE OLD LLAMA.CPP TREES ====="
sudo rm -rf -- /opt/llama.cpp /opt/llama.cpp.pre-610-20260730-055401

# Remove home test files only after the evidence copy.
echo
echo "===== REMOVE HOME TEST SCRATCH ====="
rm -f /home/ai/qwen38-*.log /home/ai/qwen38-*.csv /home/ai/qwen38-*.txt 2>/dev/null || true
rm -f /home/ai/b10435-*.log 2>/dev/null || true
rm -rf /home/ai/llama-patch-audit-20260815 2>/dev/null || true

# Keep /home/ai/.venvs/hf-publish. Only discard disposable caches.
echo
echo "===== CLEAN DISPOSABLE CACHES ====="
rm -rf /home/ai/.cache/pip 2>/dev/null || true
rm -rf /home/ai/.cache/huggingface 2>/dev/null || true
sudo apt-get clean
sudo journalctl --vacuum-size=50M >/dev/null || true

# Deliberately preserve ComfyUI and NVIDIA install trees.
echo
echo "===== EXPLICITLY PRESERVED ====="
echo "/opt/comfyui"
echo "/opt/nvidia"
echo "$LLAMA"
echo "$SNAP"
echo "/home/ai/.venvs/hf-publish"

# Final production verification after cleanup.
echo
echo "===== POST-CLEANUP PRODUCTION VERIFICATION ====="
[[ -f "$MODEL" ]] || fail "production model disappeared"
[[ -f "$MMPROJ" ]] || fail "production mmproj disappeared"
[[ "$(sha256sum "$MODEL" | awk '{print $1}')" == "$EXPECTED_MODEL_SHA" ]] || fail "model SHA changed"
[[ "$(sha256sum "$MMPROJ" | awk '{print $1}')" == "$EXPECTED_MMPROJ_SHA" ]] || fail "mmproj SHA changed"
[[ "$(git -C "$LLAMA" rev-parse HEAD)" == "$EXPECTED_GIT_HEAD" ]] || fail "llama.cpp HEAD changed"
systemctl is-active --quiet "$SERVICE" || fail "$SERVICE is no longer active"
curl -fsS http://127.0.0.1:8001/health >/dev/null || fail "API health check failed after cleanup"

echo "Production service is still healthy."

echo
echo "===== SPACE AFTER ====="
df -h /

echo
echo "===== REMAINING /opt ====="
sudo du -sh /opt/* 2>/dev/null | sort -h

echo
echo "===== CLEANUP COMPLETE ====="
echo "Protected production state remains intact."
