# Deployment

## Verify artifacts

```bash
sha256sum /opt/models/qwen3.8-27b-zerorefusal-gguf/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
stat -c '%s %n' /opt/models/qwen3.8-27b-zerorefusal-gguf/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
/opt/llama.cpp-qwen38-unpatched/build/bin/llama-server --version
git -C /opt/llama.cpp-qwen38-unpatched/src status --short
git -C /opt/llama.cpp-qwen38-unpatched/src rev-parse HEAD
```

Expected model hash:

```text
18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
```

Expected upstream commit:

```text
9e40df63ba151d771d8b247ac4011cf203337e99
```

## Install systemd unit

```bash
curl -fsSL \
  https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/systemd/qwen38-27b.service.example \
  | sudo tee /etc/systemd/system/qwen27b.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now qwen27b.service
```

Model loading takes several minutes. Wait until the health endpoint responds:

```bash
until curl -fsS http://127.0.0.1:8001/health; do sleep 5; done
```

## Verify runtime

```bash
curl -fsS http://127.0.0.1:8001/props > /tmp/qwen38-props.json
python3 - <<'PY'
import json
p = json.load(open('/tmp/qwen38-props.json'))
print('n_ctx:', p['default_generation_settings']['n_ctx'])
print('slots:', p['total_slots'])
print('model:', p['model_alias'])
print('ftype:', p['model_ftype'])
PY

nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv
```

Expected cold state is approximately 206 MiB free on the tested RTX 5060 Ti 16 GiB. Driver and display allocations can move this number.

## Operational cautions

- Keep port 8001 behind an authenticated reverse proxy; the server is otherwise an unauthenticated OpenAI-compatible endpoint.
- Long prefill can temporarily reduce the other slot's output speed.
- Keep the CPU mmproj and 4096 image-token cap unchanged until a real image request passes.
- If the CUDA process exits, inspect `journalctl -u qwen27b.service` before reducing context or changing quantization.
