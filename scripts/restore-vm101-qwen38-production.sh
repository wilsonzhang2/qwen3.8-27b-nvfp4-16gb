#!/usr/bin/env bash
set -Eeuo pipefail
SERVICE=qwen27b.service
TEST_SERVICE=qwen38-68k-test.service
PORT=8001
UNIT=/run/systemd/system/$TEST_SERVICE
sudo -v

echo "===== RESTORE FROZEN 64K PRODUCTION ====="
sudo systemctl stop "$TEST_SERVICE" >/dev/null 2>&1 || true
sudo rm -f "$UNIT"
sudo systemctl daemon-reload
sudo systemctl start "$SERVICE"

ready=0
for _ in $(seq 1 150); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" != 1 ]]; then
  sudo systemctl status "$SERVICE" --no-pager -l >&2 || true
  sudo journalctl -u "$SERVICE" -n 120 --no-pager >&2 || true
  exit 1
fi

sleep 2
echo "Production API healthy."
echo "VRAM:"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader
echo "Service:"
systemctl is-enabled "$SERVICE" || true
systemctl is-active "$SERVICE" || true
