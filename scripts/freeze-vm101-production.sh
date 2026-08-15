#!/usr/bin/env bash
set -Eeuo pipefail

# Freeze the validated 2026-08-15 VM101 Qwen3.8 deployment into a reproducible
# local git commit/tag, snapshot directory, and systemd service.

BASE_COMMIT=9e40df63ba151d771d8b247ac4011cf203337e99
PATCH_SHA=1b0cb7a04a62543a4f27ce8ae6ef7f08cc79bd246dc282af23e4b3439a6c266b
MODEL_SHA=828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66
MMPROJ_SHA=71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee

LLAMA_ROOT=${LLAMA_ROOT:-/opt/llama.cpp-qwen38}
SERVER=${SERVER:-$LLAMA_ROOT/build/bin/llama-server}
MODEL=${MODEL:-/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf}
MMPROJ=${MMPROJ:-/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf}
PORT=${PORT:-8001}
SERVICE=${SERVICE:-qwen27b.service}
SNAPSHOT=${SNAPSHOT:-/opt/qwen38-production/2026-08-15}
PATCH_LOCAL=${PATCH_LOCAL:-/home/ai/b10435-fa-transient-final.patch}
PATCH_URL=${PATCH_URL:-https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/patches/b10435-fa-transient-final.patch}

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found"; }

need git
need curl
need sha256sum
need nvidia-smi
need systemctl
[[ -d "$LLAMA_ROOT/.git" ]] || fail "llama.cpp tree not found: $LLAMA_ROOT"
[[ -x "$SERVER" ]] || fail "llama-server not found: $SERVER"
[[ -f "$MODEL" ]] || fail "model not found: $MODEL"
[[ -f "$MMPROJ" ]] || fail "mmproj not found: $MMPROJ"

sudo -v
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PATCH="$TMP/b10435-fa-transient-final.patch"

if [[ -f "$PATCH_LOCAL" ]]; then
    cp "$PATCH_LOCAL" "$PATCH"
else
    curl -fsSL "$PATCH_URL" -o "$PATCH"
fi

actual_patch=$(sha256sum "$PATCH" | awk '{print $1}')
[[ "$actual_patch" == "$PATCH_SHA" ]] || fail "patch SHA256 mismatch: $actual_patch"

echo "===== VERIFY RELEASE FILES ====="
echo "Patch SHA256 verified: $actual_patch"
actual_model=$(sha256sum "$MODEL" | awk '{print $1}')
[[ "$actual_model" == "$MODEL_SHA" ]] || fail "model SHA256 mismatch: $actual_model"
echo "Model SHA256 verified: $actual_model"
actual_mmproj=$(sha256sum "$MMPROJ" | awk '{print $1}')
[[ "$actual_mmproj" == "$MMPROJ_SHA" ]] || fail "mmproj SHA256 mismatch: $actual_mmproj"
echo "mmproj SHA256 verified: $actual_mmproj"

# Confirm the exact transient-FA patch is currently represented in the source tree.
if ! git -C "$LLAMA_ROOT" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    fail "the exact tested FA patch is not applied to $LLAMA_ROOT"
fi
echo "Exact tested FA patch is present in the llama.cpp source tree."

# Freeze the patched source in a local commit/tag when the working tree is still
# the original b10435 commit plus the four tested CUDA modifications.
current_head=$(git -C "$LLAMA_ROOT" rev-parse HEAD)
if [[ "$current_head" == "$BASE_COMMIT" ]]; then
    expected=$(printf '%s\n' \
      ggml/src/ggml-cuda/fattn-common.cuh \
      ggml/src/ggml-cuda/fattn.cu \
      ggml/src/ggml-cuda/fattn.cuh \
      ggml/src/ggml-cuda/ggml-cuda.cu | sort)
    changed=$(git -C "$LLAMA_ROOT" diff --name-only | sort)
    [[ "$changed" == "$expected" ]] || {
        echo "Unexpected tracked changes:" >&2
        git -C "$LLAMA_ROOT" status --short >&2
        fail "refusing to create the local production commit"
    }

    branch=local/qwen38-prod-20260815
    if git -C "$LLAMA_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$LLAMA_ROOT" branch -D "$branch"
    fi
    git -C "$LLAMA_ROOT" switch -c "$branch"
    git -C "$LLAMA_ROOT" add \
      ggml/src/ggml-cuda/fattn-common.cuh \
      ggml/src/ggml-cuda/fattn.cu \
      ggml/src/ggml-cuda/fattn.cuh \
      ggml/src/ggml-cuda/ggml-cuda.cu
    git -C "$LLAMA_ROOT" \
      -c user.name='VM101 Local Production' \
      -c user.email='local@ai-gpu' \
      commit -m 'Local: transient FA scratch for Qwen3.8 16GB production'
    git -C "$LLAMA_ROOT" tag -f qwen38-prod-20260815
    current_head=$(git -C "$LLAMA_ROOT" rev-parse HEAD)
    echo "Created local production commit: $current_head"
else
    echo "Source HEAD already differs from b10435: $current_head"
    echo "Patch presence was verified; leaving existing git history unchanged."
fi

# Snapshot everything needed to reconstruct tonight's validated state.
sudo mkdir -p "$SNAPSHOT"
if [[ -f "/etc/systemd/system/$SERVICE" && ! -f "$SNAPSHOT/${SERVICE}.before" ]]; then
    sudo cp "/etc/systemd/system/$SERVICE" "$SNAPSHOT/${SERVICE}.before"
fi
sudo cp "$PATCH" "$SNAPSHOT/b10435-fa-transient-final.patch"

git -C "$LLAMA_ROOT" status --short > "$TMP/git-status.txt"
git -C "$LLAMA_ROOT" log -1 --decorate --oneline > "$TMP/git-head.txt"
git -C "$LLAMA_ROOT" show --stat --oneline HEAD > "$TMP/git-show.txt"
"$SERVER" --version > "$TMP/llama-server-version.txt" 2>&1 || true
nvidia-smi > "$TMP/nvidia-smi-before.txt"
cat > "$TMP/SHA256SUMS" <<EOF
$MODEL_SHA  $(basename "$MODEL")
$MMPROJ_SHA  $(basename "$MMPROJ")
$PATCH_SHA  b10435-fa-transient-final.patch
EOF

cat > "$TMP/manifest.txt" <<EOF
Frozen: 2026-08-15
Profile: Qwen3.8-27B NVFP4 Q5K physical no-MTP / 64K / P2 / unified Q4_0 KV / full GPU / CPU Vision
llama.cpp base: b10435 / $BASE_COMMIT
local source HEAD: $current_head
model: $MODEL
mmproj: $MMPROJ
port: $PORT
service: $SERVICE
context: 64000 shared
parallel: 2
GPU layers: 999 (full GPU text backbone)
KV: q4_0 K + q4_0 V
Vision: F16 mmproj, CPU offload
MTP: physically removed / disabled
FA patch SHA256: $PATCH_SHA
Published model SHA256: $MODEL_SHA
Published mmproj SHA256: $MMPROJ_SHA
GitHub: https://github.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb
HuggingFace: https://huggingface.co/QQZ2026/Qwen3.8-27B-NVFP4-Q5K-no-MTP-GGUF
EOF

sudo cp "$TMP"/git-status.txt "$TMP"/git-head.txt "$TMP"/git-show.txt \
  "$TMP"/llama-server-version.txt "$TMP"/nvidia-smi-before.txt \
  "$TMP"/SHA256SUMS "$TMP"/manifest.txt "$SNAPSHOT/"

# Preserve the exact tested production runtime parameters. Reuse the historical
# qwen27b.service name so existing local operational tooling keeps a stable unit.
cat > "$TMP/$SERVICE" <<EOF
[Unit]
Description=Qwen3.8-27B NVFP4 no-MTP 64K P2 Full-GPU Vision-CPU
Wants=network-online.target
After=network-online.target
Conflicts=comfyui-qwen-image.service

[Service]
Type=simple
User=ai
Group=ai
WorkingDirectory=$LLAMA_ROOT
ExecStart=$SERVER -m $MODEL --alias qwen3.8-27b --mmproj $MMPROJ --no-mmproj-offload -c 64000 -np 2 --kv-unified -ngl 999 --flash-attn on -ctk q4_0 -ctv q4_0 -b 512 -ub 64 --threads 7 --fit off --jinja --host 0.0.0.0 --port $PORT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGINT
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo cp "$TMP/$SERVICE" "/etc/systemd/system/$SERVICE"
sudo cp "$TMP/$SERVICE" "$SNAPSHOT/$SERVICE"

# Make the Qwen server the default GPU workload at boot. ComfyUI remains
# available but will not race this service for the 16 GB GPU.
sudo systemctl disable comfyui-qwen-image.service >/dev/null 2>&1 || true
sudo systemctl stop comfyui-qwen-image.service >/dev/null 2>&1 || true
sudo systemctl stop "$SERVICE" >/dev/null 2>&1 || true

# Stop the manually launched test server on the same port before systemd takes over.
sudo pkill -INT -u ai -f "$SERVER.*--port $PORT" >/dev/null 2>&1 || true
sleep 3
sudo pkill -TERM -u ai -f "$SERVER.*--port $PORT" >/dev/null 2>&1 || true

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE"
sudo systemctl start "$SERVICE"

# Wait for model load and API readiness.
ready=0
for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done

if [[ "$ready" != 1 ]]; then
    echo "Service did not become healthy in 120 seconds." >&2
    sudo systemctl status "$SERVICE" --no-pager -l >&2 || true
    sudo journalctl -u "$SERVICE" -n 120 --no-pager >&2 || true
    exit 1
fi

sudo systemctl cat "$SERVICE" > "$TMP/systemd-final.txt"
sudo systemctl status "$SERVICE" --no-pager -l > "$TMP/systemd-status.txt" || true
nvidia-smi > "$TMP/nvidia-smi-final.txt"
curl -fsS "http://127.0.0.1:$PORT/health" > "$TMP/health.json" || true
sudo cp "$TMP"/systemd-final.txt "$TMP"/systemd-status.txt \
  "$TMP"/nvidia-smi-final.txt "$TMP"/health.json "$SNAPSHOT/"
sudo ln -sfn "$SNAPSHOT" /opt/qwen38-production/current
sudo chown -R ai:ai /opt/qwen38-production

echo
echo "===== VM101 PRODUCTION STATE FROZEN ====="
echo "Service : $SERVICE"
echo "API     : http://192.168.10.101:$PORT/v1"
echo "Snapshot: $SNAPSHOT"
echo "Git HEAD: $current_head"
echo "Tag     : qwen38-prod-20260815"
echo
echo "VRAM:"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader
echo
echo "Service:"
systemctl is-enabled "$SERVICE" || true
systemctl is-active "$SERVICE" || true
