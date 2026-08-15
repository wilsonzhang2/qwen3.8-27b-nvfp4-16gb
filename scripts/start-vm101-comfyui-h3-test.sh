#!/usr/bin/env bash
set -Eeuo pipefail

QWEN=qwen27b.service
COMFY=comfyui-qwen-image.service

sudo -v

echo "===== PRECHECK ====="
systemctl is-active --quiet "$QWEN" && echo "Qwen: active" || echo "Qwen: not active"
[[ -f /opt/comfyui/models/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors ]] || { echo "Missing H3 diffusion model" >&2; exit 1; }
[[ -f /opt/comfyui/models/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors ]] || { echo "Missing H3 text encoder" >&2; exit 1; }
[[ -f /opt/comfyui/models/vae/minimax_h3_video_vae_fp16.safetensors ]] || { echo "Missing H3 video VAE" >&2; exit 1; }
[[ -f /opt/comfyui/models/vae/minimax_h3_audio_vae_fp32.safetensors ]] || { echo "Missing H3 audio VAE" >&2; exit 1; }

echo "Stopping Qwen production service to free the RTX 5060 Ti..."
sudo systemctl stop "$QWEN"

echo "Starting ComfyUI..."
sudo systemctl start "$COMFY"

for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8188/system_stats >/dev/null 2>&1; then
    echo
    echo "===== COMFYUI READY ====="
    echo "URL: http://192.168.10.101:8188"
    echo "Qwen:  $(systemctl is-active "$QWEN" || true)"
    echo "Comfy: $(systemctl is-active "$COMFY" || true)"
    echo
    nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu --format=csv,noheader
    free -h
    exit 0
  fi
  sleep 2
done

echo "ERROR: ComfyUI did not become ready in time." >&2
sudo journalctl -u "$COMFY" -n 120 --no-pager >&2 || true
exit 1
