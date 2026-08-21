---
license: apache-2.0
language:
- en
- zh
library_name: gguf
pipeline_tag: image-text-to-text
base_model:
- asfgsdfg/Qwen3.8-27B-Heretic
base_model_relation: quantized
model_name: Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF
tags:
- gguf
- llama-cpp
- qwen
- qwen3_5
- qwen3.8
- vision
- multimodal
- heretic
- abliterated
- uncensored
- quantized
- iq4_xs
- mtp
- speculative-decoding
- dynamic-v3
- rtx-5060-ti
- 16gb-vram
---

# Qwen3.8-27B LowDrift UD-IQ4_XS + Embedded MTP GGUF

Low-drift / reduced-refusal Qwen3.8-27B derivative quantized with a Dynamic-V3-style UD-IQ4_XS tensor layout and an embedded original MTP layer.

## Download

Repository:

```text
QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF
```

Download the GGUF with the Hugging Face CLI:

```bash
hf download QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF \
  Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf \
  --local-dir .
```

Or let llama.cpp download the exact file:

```bash
llama-server \
  -hf QQZ2026/Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP-GGUF \
  -hff Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf \
  --port 8001
```

The GGUF is the model artifact. Vision additionally requires a compatible Qwen3.8-27B F16 `mmproj` as documented below.

## Files

Main model:

```text
Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf
```

Integrity:

```text
size    14,252,845,184 bytes (~13.274 GiB)
sha256  49021e6e76af0ac6298e56aa4fab1ed56b62c7c66b6e7a18933907185bd1827d
```

GGUF verification:

```text
architecture       qwen35
block_count        65
nextn_predict      1
tensor_count       866
main quant class   IQ4_XS - 4.25 bpw
FINAL VERIFY       PASS
```

The 851 main-model tensor types reproduce the reference Unsloth UD-IQ4_XS layout with `0 mismatch`. The 15 `blk.64` MTP tensors were grafted byte-for-byte from the reference UD GGUF and verified by SHA256.

## Recommended RTX 5060 Ti 16 GB profile

Production target validated on a single RTX 5060 Ti 16 GB:

```bash
llama-server \
  -m Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf \
  --alias qwen3.8-27b \
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
  --jinja
```

Measured cold-load state at the 68K production point:

```text
runtime n_ctx      68,096
parallel slots     2
GPU used           ~15,650 MiB
GPU free           ~240 MiB
```

Recommended workload policy:

- short customer-service requests: cap at about **4K** context;
- main reasoning/coding requests: cap at about **64K**;
- leave the remaining physical context for system prompts, tools and template overhead.

## MTP performance observations

Same RTX 5060 Ti 16 GB, same model family and server build:

```text
72K / P2 / MTP-2
  decode               51.48 tok/s
  draft acceptance     75.66%
  mean accepted length 2.51

76K / P2 / MTP-2
  decode               50.78 tok/s
  draft acceptance     73.53%
  mean accepted length 2.47

88K / P2 / MTP-1
  decode               43.28 tok/s
  draft acceptance     86.99%
  mean accepted length 1.87

80K / P2 / MTP-2
  OOM during MTP-context allocation
```

68K was selected as the production profile to preserve MTP-2 throughput while providing more VRAM margin than 72K.

## CUDA pool warm-up

A repeated 24K-prefill diagnostic at 60K / P2 / MTP-2 observed a one-time ~106 MiB retained CUDA-pool allocation on the first long prefill, followed by `+0 MiB` on the second and third repeats. In that test this behaved like a pool high-water allocation, not a continuing stepwise leak.

## Vision

A matching Qwen3.8 F16 `mmproj` can be used with CPU residency on a 16 GB GPU:

```text
--mmproj mmproj-Qwen3.8-27B-F16.gguf
--no-mmproj-offload
--image-max-tokens 4096
```

The projector is not duplicated in this repository. It can be reused from the existing Qwen3.8 deployment/repository.

## Provenance and license

- Base family: Qwen3.8-27B
- Behavioral derivative: `asfgsdfg/Qwen3.8-27B-Heretic`
- Quantization-layout reference: Unsloth Qwen3.8-27B Dynamic V3 UD-IQ4_XS artifact
- Runtime: llama.cpp, b10435-based FA-transient build used during validation
- License: Apache-2.0, inherited from the behavioral source/base model

This derivative is not mathematically identical to the original model. The behavioral source was selected to reduce refusal behavior while keeping published output-distribution drift low.

## Reproducibility

Build notes, production command, checksum and validation data:

https://github.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/tree/main/lowdrift-ud-iq4xs-mtp
