# Qwen3.8-27B ZeroRefusal UD-IQ4_XS MTP

Production-oriented GGUF release for a 16 GiB NVIDIA GPU.

## Current production baseline

| Item | Value |
|---|---|
| Behavior source | `junafinity/Qwen-3.8-27B-Uncensored` |
| Source revision | `903d149c148b81fdf4e568a05ac9ad4225f493d7` |
| GGUF | `Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf` |
| Size | `14,252,845,024` bytes |
| SHA256 | `18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260` |
| Tensor structure | 866 tensors, including 15 embedded MTP tensors |
| llama.cpp | upstream b10435, commit `9e40df63ba151d771d8b247ac4011cf203337e99` |
| Context / concurrency | `71,680 = 70 × 1024`, P2, unified KV |
| Speculation | MTP-1, draft KV F16 |
| Main KV | Q4_0 K/V |
| GPU | full model offload, Flash Attention on |
| Vision | F16 mmproj on CPU, image token cap 4096 |

The production binary is built from the stated upstream commit without local CUDA source changes.

## Verified on RTX 5060 Ti 16 GiB

| Test | Result |
|---|---:|
| Short generation, one stream | 41.69 tok/s median |
| Short generation, two streams | 34.73 tok/s per stream median |
| Two-stream aggregate | 61.21 tok/s median |
| 4K + 60K concurrent minimum free VRAM | 190 MiB |
| 60K concurrent prefill | 543.40 tok/s |
| 60K concurrent decode | 7.35 tok/s |
| Server after tests | alive |

The 60K decode rate is measured while a 4K request runs concurrently. A single 60K request measured 26.55 tok/s at the 64K test baseline. Long prefill can temporarily reduce latency for the other slot, so production scheduling should prioritize short interactive requests.

## Important accuracy notes

- The source BF16 model reports 0/64 refusals and KL divergence 0.00971 on its published held-out evaluation. Those are source-model results, not measurements of this quantized GGUF.
- This GGUF has not yet been rerun on the same 64-prompt refusal evaluation. Do not advertise the quantized artifact as universally zero-refusal.
- The tensor layout reproduces an earlier Unsloth UD-IQ4_XS preview-era layout. It is not an official current Unsloth Dynamic V3 quantization.
- The mmproj loads successfully on CPU with a 4096 image-token cap. A real image request still needs a final production acceptance test.
- Reduced refusal does not add knowledge or correctness. Deploy an independent moderation layer where required.

## Files

- `CURRENT-PRODUCTION.md` — exact production contract.
- `DEPLOYMENT.md` — install, start and verify.
- `zerorefusal-ud-iq4xs-mtp/` — release assets and Hugging Face publisher.
- `systemd/qwen38-27b.service.example` — production unit.

The GGUF itself is distributed through Hugging Face rather than GitHub.
