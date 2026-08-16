#!/usr/bin/env bash
set -Eeuo pipefail

BASE_COMMIT=9e40df63ba151d771d8b247ac4011cf203337e99
MODEL_SHA=828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66
MMPROJ_SHA=71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee

LLAMA_ROOT=${LLAMA_ROOT:-/opt/llama.cpp-qwen38-upstream-b10435}
SERVER=${SERVER:-$LLAMA_ROOT/build/bin/llama-server}
MODEL=${MODEL:-/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf}
MMPROJ=${MMPROJ:-/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf}
SERVICE=${SERVICE:-qwen27b.service}
PORT=${PORT:-8001}
SNAPSHOT=${SNAPSHOT:-/opt/qwen38-production/2026-08-16-66k-p2-nopatch}

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found"; }

need git
need curl
need sha256sum
need nvidia-smi
need systemctl

[[ -d "$LLAMA_ROOT/.git" || -f "$LLAMA_ROOT/.git" ]] || fail "llama.cpp worktree not found: $LLAMA_ROOT"
[[ -x "$SERVER" ]] || fail "llama-server not found: $SERVER"
[[ -f "$MODEL" ]] || fail "model not found: $MODEL"
[[ -f "$MMPROJ" ]] || fail "mmproj not found: $MMPROJ"

head=$(git -C "$LLAMA_ROOT" rev-parse HEAD)
[[ "$head" == "$BASE_COMMIT" ]] || fail "upstream worktree HEAD mismatch: $head"
[[ -z "$(git -C "$LLAMA_ROOT" status --porcelain)" ]] || fail "upstream worktree is not clean"

echo "===== VERIFY EXACT UPSTREAM / ARTIFACTS ====="
echo "llama.cpp upstream b10435: $head"
actual_model=$(sha256sum "$MODEL" | awk '{print $1}')
[[ "$actual_model" == "$MODEL_SHA" ]] || fail "model SHA256 mismatch: $actual_model"
echo "Model SHA256 verified: $actual_model"
actual_mmproj=$(sha256sum "$MMPROJ" | awk '{print $1}')
[[ "$actual_mmproj" == "$MMPROJ_SHA" ]] || fail "mmproj SHA256 mismatch: $actual_mmproj"
echo "mmproj SHA256 verified: $actual_mmproj"

sudo -v
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sudo mkdir -p "$SNAPSHOT"

if [[ -f "/etc/systemd/system/$SERVICE" ]]; then
    sudo cp "/etc/systemd/system/$SERVICE" "$SNAPSHOT/${SERVICE}.before"
fi

cat > "$TMP/$SERVICE" <<EOF
[Unit]
Description=Qwen3.8-27B NVFP4 no-MTP 66K P2 Full-GPU Vision-CPU upstream-b10435 no-patch
Wants=network-online.target
After=network-online.target
Conflicts=comfyui-qwen-image.service

[Service]
Type=simple
User=ai
Group=ai
WorkingDirectory=$LLAMA_ROOT
ExecStart=$SERVER -m $MODEL --alias qwen3.8-27b --mmproj $MMPROJ --no-mmproj-offload --image-max-tokens 4096 -c 66000 -np 2 --kv-unified -ngl 999 --flash-attn on -ctk q4_0 -ctv q4_0 -b 512 -ub 64 --threads 7 --fit off --jinja --host 0.0.0.0 --port $PORT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGINT
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > "$TMP/manifest.txt" <<EOF
Frozen: 2026-08-16
Profile: Qwen3.8-27B NVFP4 Q5K physical no-MTP / 66K / P2 / unified Q4_0 KV / full GPU / Vision CPU / image max tokens 4096 / NO PATCH
llama.cpp: upstream b10435 / $BASE_COMMIT
llama root: $LLAMA_ROOT
server: $SERVER
model: $MODEL
mmproj: $MMPROJ
service: $SERVICE
port: $PORT
context: 66000 shared
parallel: 2
KV unified: yes
GPU layers: 999
KV: q4_0 K + q4_0 V
Vision: F16 mmproj CPU offload
image-max-tokens: 4096
MTP: physically removed / disabled
FA patch: NONE
Model SHA256: $MODEL_SHA
mmproj SHA256: $MMPROJ_SHA
Validated workload: 40K MAIN + ~4K Vision CS concurrent, repeated without further VRAM growth after first warm-up
EOF

"$SERVER" --version > "$TMP/llama-server-version.txt" 2>&1 || true
nvidia-smi > "$TMP/nvidia-smi-before.txt"
git -C "$LLAMA_ROOT" status --short > "$TMP/git-status.txt"
git -C "$LLAMA_ROOT" log -1 --decorate --oneline > "$TMP/git-head.txt"

sudo cp "$TMP/$SERVICE" "/etc/systemd/system/$SERVICE"
sudo cp "$TMP/$SERVICE" "$TMP/manifest.txt" "$TMP/llama-server-version.txt" \
  "$TMP/nvidia-smi-before.txt" "$TMP/git-status.txt" "$TMP/git-head.txt" "$SNAPSHOT/"

# Keep ComfyUI and temporary test units out of the production GPU path.
sudo systemctl disable comfyui-qwen-image.service >/dev/null 2>&1 || true
sudo systemctl stop comfyui-qwen-image.service >/dev/null 2>&1 || true
sudo systemctl stop qwen38-68k-test.service >/dev/null 2>&1 || true
sudo systemctl stop "$SERVICE" >/dev/null 2>&1 || true

# Stop any manually launched upstream-b10435 test server on the production port.
sudo pkill -INT -u ai -f "$SERVER.*--port $PORT" >/dev/null 2>&1 || true
sleep 3
sudo pkill -TERM -u ai -f "$SERVER.*--port $PORT" >/dev/null 2>&1 || true

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE"
sudo systemctl start "$SERVICE"

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
    sudo journalctl -u "$SERVICE" -n 160 --no-pager >&2 || true
    exit 1
fi

sudo systemctl cat "$SERVICE" > "$TMP/systemd-final.txt"
sudo systemctl status "$SERVICE" --no-pager -l > "$TMP/systemd-status.txt" || true
nvidia-smi > "$TMP/nvidia-smi-final.txt"
curl -fsS "http://127.0.0.1:$PORT/health" > "$TMP/health.json"
ps -ef | grep '[l]lama-server' > "$TMP/llama-process.txt" || true
sudo cp "$TMP/systemd-final.txt" "$TMP/systemd-status.txt" "$TMP/nvidia-smi-final.txt" \
  "$TMP/health.json" "$TMP/llama-process.txt" "$SNAPSHOT/"

sudo ln -sfn "$SNAPSHOT" /opt/qwen38-production/current
sudo chown -R ai:ai "$SNAPSHOT"

echo
echo "===== VM101 66K P2 NO-PATCH PRODUCTION READY ====="
echo "Service : $SERVICE"
echo "API     : http://192.168.10.101:$PORT/v1"
echo "Snapshot: $SNAPSHOT"
echo "llama.cpp: upstream b10435 / $BASE_COMMIT"
echo "Context : 66000 shared / P2 unified"
echo "Vision  : CPU mmproj / image-max-tokens 4096"
echo "MTP     : OFF / physically removed"
echo "Patch   : NONE"
echo
echo "VRAM:"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader
echo
echo "Service:"
systemctl is-enabled "$SERVICE" || true
systemctl is-active "$SERVICE" || true
