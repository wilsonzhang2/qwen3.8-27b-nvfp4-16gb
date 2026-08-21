---
library_name: gguf
pipeline_tag: image-text-to-text
license: apache-2.0
language:
- en
- zh
base_model: junafinity/Qwen-3.8-27B-Uncensored
base_model_relation: quantized
tags:
- qwen
- qwen3.8
- qwen3_5
- gguf
- iq4-xs
- mtp
- llama-cpp
- vision
- multimodal
- zerofuse
- abliterated
- reduced-refusal
- long-context
- rtx-5060-ti
---

# Qwen3.8-27B ZeroRefusal UD-IQ4_XS MTP GGUF

A compact multimodal GGUF derived from `junafinity/Qwen-3.8-27B-Uncensored`, with embedded MTP tensors and a production profile validated on one RTX 5060 Ti 16 GiB.

## Download

```bash
hf download QQZ2026/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP-GGUF \
  Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf \
  --local-dir .
```

The GGUF is `14,252,845,024` bytes. Verify it with:

```text
18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
```

## Provenance

| Item | Value |
|---|---|
| Base model | `Qwen/Qwen3.8-27B` |
| Behavior source | `junafinity/Qwen-3.8-27B-Uncensored` |
| Source revision | `903d149c148b81fdf4e568a05ac9ad4225f493d7` |
| Behavior method | ZeroFuse v0.1.0 directional ablation |
| Quantization | UD-IQ4_XS-style mixed tensor map with imatrix |
| GGUF tensors | 866 total, including 15 embedded MTP tensors |

The tensor map reproduces an earlier Unsloth UD-IQ4_XS preview-era artifact. This is an independently converted derivative and is not an official current Unsloth Dynamic V3 quantization.

## Refusal and KL claims

The source BF16 model card reports **0/64 refusals** and **KL 0.00971** on its held-out evaluation. These numbers describe the BF16 source under that exact methodology.

This quantized GGUF has not yet been rerun on the same 64-prompt suite. Quantization can change token probabilities and individual classifications. Therefore this release does not claim a measured 0/64 refusal rate for the GGUF, nor does it claim that all prompts will be answered.

Reduced refusal is not improved factual accuracy. Operators remain responsible for independent moderation, access controls and legal compliance.

## Validated llama.cpp profile

Validation used public upstream llama.cpp b10435 commit `9e40df63ba151d771d8b247ac4011cf203337e99` without local CUDA source changes.

```bash
llama-server \
  -m Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf \
  --alias qwen3.8-27b-zerorefusal \
  --mmproj /path/to/compatible-mmproj-Qwen3.8-27B-F16.gguf \
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
  --host 127.0.0.1 \
  --port 8001
```

The compatible F16 mmproj is a separate file and is not bundled in this repository.

## RTX 5060 Ti 16 GiB measurements

| Workload | Result |
|---|---:|
| 70×1024 cold load | 206 MiB free |
| Short output, one stream | 41.69 tok/s median |
| Short output, two streams | 34.73 tok/s per stream median |
| Two-stream aggregate | 61.21 tok/s median |
| 4K + 60K concurrent minimum free | 190 MiB |
| 60K concurrent prefill | 543.40 tok/s |
| 60K concurrent output | 7.35 tok/s |

The long-context concurrent test completed with the server alive. A single 60K request at the 64K test baseline measured 26.55 tok/s output. Long prefill can temporarily reduce the other slot's latency.

VRAM headroom is deliberately narrow. Do not run another CUDA workload on the same GPU. Driver, display and allocator differences may require a smaller context.

## Vision status

The F16 mmproj loads on CPU with `--image-max-tokens 4096`. Text and long-context paths are validated. A real image request has not yet been included in the final acceptance run, so Vision should be treated as configured but pending end-to-end verification.

## License and attribution

Apache-2.0, inherited from Qwen and the behavioral source. Qwen created the base architecture, training and multimodal capability. ZeroFuse performed the directional behavior edit. The quantization layout and imatrix are attributed to Unsloth's earlier preview-era UD artifact.
