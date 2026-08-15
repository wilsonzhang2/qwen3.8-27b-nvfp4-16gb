#!/usr/bin/env bash
set -euo pipefail

: "${MODEL:?Set MODEL=/path/to/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf}"
: "${MMPROJ:?Set MMPROJ=/path/to/mmproj-Qwen3.8-27B-F16.gguf}"

LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8001}"
THREADS="${THREADS:-7}"

exec "$LLAMA_SERVER" \
  -m "$MODEL" \
  --mmproj "$MMPROJ" \
  --no-mmproj-offload \
  -c 64000 \
  -np 2 \
  --kv-unified \
  -ngl 999 \
  --flash-attn on \
  -ctk q4_0 \
  -ctv q4_0 \
  -b 512 \
  -ub 64 \
  --threads "$THREADS" \
  --fit off \
  --jinja \
  --host "$HOST" \
  --port "$PORT"
