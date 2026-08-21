# Current production: ZeroRefusal 70×1024 P2 MTP-1

This is the only production baseline documented by this repository.

## Immutable artifacts

```text
model:  /opt/models/qwen3.8-27b-zerorefusal-gguf/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
bytes:  14252845024
sha256: 18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
binary: /opt/llama.cpp-qwen38-unpatched/build/bin/llama-server
commit: 9e40df63ba151d771d8b247ac4011cf203337e99 (upstream b10435)
mmproj: /opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
```

The binary path contains the local word `unpatched`; the required property is the exact upstream commit above and a clean source tree.

## Runtime contract

```text
context             71680 (70 × 1024)
parallel slots      2
KV                  unified, Q4_0 K/V
model offload       full GPU
Flash Attention     on
MTP                 embedded, draft length 1
draft KV            F16 K/V
backend sampling    disabled for speculative draft
batch / ubatch      512 / 64
threads             7
Vision projector    CPU
image token cap     4096
port                8001
```

`--no-spec-draft-backend-sampling` is part of the production contract. It prevents lazy speculative-sampling buffers from consuming the remaining VRAM during first decode.

## Capacity policy

- A-class interactive work: normally ≤4K prompt.
- B-class long work: normally ≤60K prompt.
- P2 is validated for one A-class plus one B-class request.
- Do not assume 190 MiB of measured headroom is available to other GPU processes.
- Do not run ComfyUI or another CUDA workload concurrently with this service.

## Acceptance status

Text, long-context, concurrent decode, server survival and VRAM monitoring: **PASS**.

Real image request with the configured CPU mmproj: **PENDING**.
