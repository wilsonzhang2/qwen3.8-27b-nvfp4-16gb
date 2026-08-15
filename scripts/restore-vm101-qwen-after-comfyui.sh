#!/usr/bin/env bash
set -Eeuo pipefail

QWEN=qwen27b.service
COMFY=comfyui-qwen-image.service

sudo -v

echo "Stopping ComfyUI..."
sudo systemctl stop "$COMFY" || true

echo "Starting Qwen production service..."
sudo systemctl start "$QWEN"

for i in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:8001/health >/dev/null 2>&1; then
    echo
    echo "===== QWEN PRODUCTION RESTORED ====="
    echo "API: http://192.168.10.101:8001/v1"
    echo "Qwen:  $(systemctl is-active "$QWEN" || true)"
    echo "Comfy: $(systemctl is-active "$COMFY" || true)"
    nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu --format=csv,noheader
    exit 0
  fi
  sleep 2
done

echo "ERROR: Qwen health check did not recover." >&2
sudo journalctl -u "$QWEN" -n 120 --no-pager >&2 || true
exit 1
