#!/usr/bin/env bash
set -euo pipefail

MODEL=/opt/models/qwen3.8-27b-zerorefusal-gguf/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
EXPECTED_SIZE=14252845024
EXPECTED_SHA=18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
COMMIT=9e40df63ba151d771d8b247ac4011cf203337e99

test "$(stat -c '%s' "$MODEL")" = "$EXPECTED_SIZE"
test "$(sha256sum "$MODEL" | awk '{print $1}')" = "$EXPECTED_SHA"
test "$(git -C /opt/llama.cpp-qwen38-unpatched/src rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C /opt/llama.cpp-qwen38-unpatched/src status --short)"

curl -fsS http://127.0.0.1:8001/health
curl -fsS http://127.0.0.1:8001/props > /tmp/qwen38-production-props.json
python3 - <<'PY'
import json
p = json.load(open('/tmp/qwen38-production-props.json'))
assert p['default_generation_settings']['n_ctx'] == 71680
assert p['total_slots'] == 2
assert p['model_alias'] == 'qwen3.8-27b-zerorefusal'
print('LOCAL RELEASE VERIFY: PASS')
PY
