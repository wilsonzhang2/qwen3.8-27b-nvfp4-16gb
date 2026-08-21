#!/usr/bin/env bash
set -euo pipefail

SERVER=/opt/llama.cpp-qwen38/build/bin/llama-server
MODEL=/opt/models/qwen3.8-27b-heretic-lowdrift-gguf/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf
MMPROJ=/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf

exec "$SERVER" \
  -m "$MODEL" \
  --alias qwen3.8-27b \
  --mmproj "$MMPROJ" \
  --no-mmproj-offload \
  --image-max-tokens 4096 \
  -c 68000 \
  -np 2 \
  --kv-unified \
  -ngl 999 \
  --flash-attn on \
  -ctk q4_0 \
  -ctv q4_0 \
  --spec-type draft-mtp \
  --spec-draft-n-max 2 \
  --spec-draft-type-k f16 \
  --spec-draft-type-v f16 \
  -b 512 \
  -ub 64 \
  --threads 7 \
  --fit off \
  --jinja \
  --host 0.0.0.0 \
  --port 8001
