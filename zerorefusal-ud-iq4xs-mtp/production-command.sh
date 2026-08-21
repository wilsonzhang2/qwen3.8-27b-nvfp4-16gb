#!/usr/bin/env bash
set -euo pipefail

exec /opt/llama.cpp-qwen38-unpatched/build/bin/llama-server \
  -m /opt/models/qwen3.8-27b-zerorefusal-gguf/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf \
  --alias qwen3.8-27b-zerorefusal \
  --mmproj /opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf \
  --no-mmproj-offload \
  --image-max-tokens 4096 \
  -c 71680 \
  -np 2 \
  --kv-unified \
  -ngl 999 \
  --flash-attn on \
  -ctk q4_0 \
  -ctv q4_0 \
  --spec-type draft-mtp \
  --spec-draft-n-max 1 \
  --spec-draft-type-k f16 \
  --spec-draft-type-v f16 \
  --no-spec-draft-backend-sampling \
  -b 512 \
  -ub 64 \
  --threads 7 \
  --fit off \
  --jinja \
  --host 0.0.0.0 \
  --port 8001
