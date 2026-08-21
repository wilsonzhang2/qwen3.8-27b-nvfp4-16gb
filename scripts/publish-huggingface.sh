#!/usr/bin/env bash
set -euo pipefail

exec bash < <(
  curl -fsSL \
    https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/zerorefusal-ud-iq4xs-mtp/publish-huggingface.sh
)
