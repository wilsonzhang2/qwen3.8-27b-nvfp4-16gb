#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE=qwen27b.service
TEST_SERVICE=qwen38-68k-test.service
COMFY=comfyui-qwen-image.service
LLAMA=/opt/llama.cpp-qwen38
SERVER=$LLAMA/build/bin/llama-server
MODEL=/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
MMPROJ=/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
EXPECTED_HEAD=64486c42ce1a578845bc4b71a271c24cb04f1a43
PORT=8001
UNIT=/run/systemd/system/$TEST_SERVICE

fail(){ echo "ERROR: $*" >&2; exit 1; }
sudo -v

[[ -x "$SERVER" ]] || fail "llama-server missing: $SERVER"
[[ -f "$MODEL" ]] || fail "model missing: $MODEL"
[[ -f "$MMPROJ" ]] || fail "mmproj missing: $MMPROJ"
[[ "$(git -C "$LLAMA" rev-parse HEAD)" == "$EXPECTED_HEAD" ]] || fail "unexpected llama.cpp HEAD"

echo "===== CURRENT STATE ====="
systemctl is-active "$SERVICE" || true
systemctl is-active "$COMFY" || true
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader

echo "===== SWITCH TO TEMPORARY 68K TEST ====="
sudo systemctl stop "$COMFY" >/dev/null 2>&1 || true
sudo systemctl stop "$SERVICE" >/dev/null 2>&1 || true
sudo systemctl stop "$TEST_SERVICE" >/dev/null 2>&1 || true
sleep 3

cat <<EOF | sudo tee "$UNIT" >/dev/null
[Unit]
Description=TEMP Qwen3.8-27B no-MTP 68K P2 Full-GPU Vision-CPU stress test
Wants=network-online.target
After=network-online.target
Conflicts=$SERVICE $COMFY

[Service]
Type=simple
User=ai
Group=ai
WorkingDirectory=$LLAMA
ExecStart=$SERVER -m $MODEL --alias qwen3.8-27b-68k-test --mmproj $MMPROJ --no-mmproj-offload -c 68000 -np 2 --kv-unified -ngl 999 --flash-attn on -ctk q4_0 -ctv q4_0 -b 512 -ub 64 --threads 7 --fit off --jinja --host 0.0.0.0 --port $PORT
Restart=no
TimeoutStopSec=30
KillSignal=SIGINT
LimitNOFILE=65535
EOF

sudo systemctl daemon-reload
sudo systemctl start "$TEST_SERVICE"

ready=0
for _ in $(seq 1 150); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! systemctl is-active --quiet "$TEST_SERVICE"; then
    break
  fi
  sleep 1
done

if [[ "$ready" != 1 ]]; then
  echo "===== 68K START FAILED =====" >&2
  sudo systemctl status "$TEST_SERVICE" --no-pager -l >&2 || true
  sudo journalctl -u "$TEST_SERVICE" -n 120 --no-pager >&2 || true
  sudo systemctl stop "$TEST_SERVICE" >/dev/null 2>&1 || true
  sudo rm -f "$UNIT"
  sudo systemctl daemon-reload
  echo "Restoring frozen 64K production service..." >&2
  sudo systemctl start "$SERVICE" || true
  exit 1
fi

sleep 2
echo
echo "===== 68K TEST READY ====="
echo "API/UI : http://192.168.10.101:$PORT"
echo "Context: 68000 shared"
echo "P2     : enabled / unified KV"
echo "Vision : CPU mmproj"
echo "GPU    : full text backbone (-ngl 999)"
echo
echo "VRAM AFTER STARTUP:"
nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu --format=csv,noheader
echo
echo "Service:"
systemctl is-active "$TEST_SERVICE"
echo "Frozen production unit remains unchanged and stopped during this test."
