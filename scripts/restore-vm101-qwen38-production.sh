#!/usr/bin/env bash
set -euo pipefail

curl -fsSL \
  https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/zerorefusal-ud-iq4xs-mtp/qwen27b.service \
  | sudo tee /etc/systemd/system/qwen27b.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable qwen27b.service
sudo systemctl restart qwen27b.service

until curl -fsS http://127.0.0.1:8001/health; do sleep 5; done
