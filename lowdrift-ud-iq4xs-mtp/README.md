# Qwen3.8-27B LowDrift UD-IQ4_XS + Embedded MTP

A low-refusal, low-drift Qwen3.8-27B GGUF build optimized for a single 16 GB NVIDIA GPU.

## Final artifact

- File: `Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf`
- Size: `14,252,845,184 bytes` (~13.274 GiB)
- SHA256: `49021e6e76af0ac6298e56aa4fab1ed56b62c7c66b6e7a18933907185bd1827d`
- Architecture metadata: `qwen35`
- `block_count = 65`
- `nextn_predict_layers = 1`
- Tensor count: `866`
- Main quantization class reported by llama.cpp: `IQ4_XS - 4.25 bpw`

## Production baseline — 2026-08-21

Validated target hardware: **NVIDIA GeForce RTX 5060 Ti 16 GB**.

The production profile is fixed at:

```text
Context: 68,096 runtime tokens (`-c 68000`)
Parallel slots: P2
Embedded MTP: enabled
MTP draft max: 2
Main KV: Q4_0 / Q4_0
Draft KV: F16 / F16
Text model: full GPU
Vision projector: F16, CPU-resident (`--no-mmproj-offload`)
Image token cap: 4096
llama.cpp server: b10435-based FA-transient build used in validation
Cold-load GPU memory used: ~15,650 MiB
Cold-load GPU memory free: ~240 MiB
```

Scheduling policy:

- Short customer-service lane: **cap requests at ~4K context**.
- Main reasoning/coding lane: **cap requests at ~64K**.
- Physical server context remains ~68K, leaving a small margin for system/tool/template overhead.
- P2 permits one short-lane task and one main-lane task concurrently under the intended Hermes scheduler.

### Why 68K

Measured comparison points on the same RTX 5060 Ti 16 GB:

```text
72K / P2 / MTP-2:
  decode               51.48 tok/s
  draft acceptance     75.66%
  mean accepted length 2.51

76K / P2 / MTP-2:
  decode               50.78 tok/s
  draft acceptance     73.53%
  mean accepted length 2.47

88K / P2 / MTP-1:
  decode               43.28 tok/s
  draft acceptance     86.99%
  mean accepted length 1.87

80K / P2 / MTP-2:
  OOM while allocating the MTP context
```

68K / P2 / MTP-2 cold-load VRAM was measured at about **15,650 MiB used / 240 MiB free**. It was selected instead of 72K to provide additional operating margin while preserving MTP-2 throughput and enough physical context for the 64K main-task cap.

### CUDA-pool warm-up observation

A repeated 24K-prefill test at 60K / P2 / MTP-2 showed:

```text
cold start free VRAM: 414 MiB
first 24K prefill:    +106 MiB retained CUDA-pool allocation
post-warm free VRAM:  308 MiB
second 24K prefill:   +0 MiB
third 24K prefill:    +0 MiB
```

This behaved as a one-time CUDA-pool high-water allocation rather than a continuing stepwise leak in that test. The 68K profile is chosen with more cold-load margin than the 72K profile for this reason.

## Provenance

Main model behavior comes from the low-drift Heretic derivative `asfgsdfg/Qwen3.8-27B-Heretic`, selected for low published KL drift while reducing refusal behavior.

The quantization layout is reproduced from Unsloth's Qwen3.8-27B Dynamic V3 `UD-IQ4_XS` artifact. The original reference GGUF used for the tensor-type map was:

- `Qwen3.8-27B-UD-IQ4_XS.gguf`
- Size: `14,252,845,984 bytes`
- SHA256: `40fac4050e940397dbf13087afd50f4734a11805bf9d65ef8ddd7483470e6199`

The original UD tensor map was reproduced exactly for all 851 main-model tensors (`851/851`, `0 mismatch`). The embedded MTP layer (`blk.64`) was grafted byte-for-byte from the original Unsloth GGUF.

## Verification

```text
original tensors  : 866
final tensors     : 866
missing tensors   : 0
extra tensors     : 0
structure mismatch: 0
MTP tensors       : 15
MTP byte mismatch : 0
block_count       : 65
nextn_predict     : 1
FINAL VERIFY      : PASS
```

All 15 embedded MTP tensors match the source artifact byte-for-byte by SHA256.

## llama.cpp

The tested MTP server binary is based on llama.cpp b10435 with the previously validated FA-transient memory behavior used for 16 GB MTP operation.

See:

- `production-command.sh` — direct server launch command
- `qwen27b.service` — systemd unit for the 68K production profile
- `SHA256SUMS` — final artifact checksum
- `huggingface/README.md` — Hugging Face model card source
- `publish-huggingface.sh` — VM101 upload helper

## Vision

The multimodal projector is not duplicated in this release. The validated projector is:

```text
mmproj-Qwen3.8-27B-F16.gguf
```

It may be reused from the existing Qwen3.8 deployment and should remain CPU-resident with `--no-mmproj-offload` on a 16 GB GPU.

## Notes

This derivative intentionally prioritizes retaining base-model capability while reducing refusal behavior. It should not be described as mathematically identical to the original model: behavioral weight edits change the output distribution.

The published 68K profile is a hardware-specific production configuration for the tested RTX 5060 Ti 16 GB system, not a universal maximum-context guarantee.

## Credits

- Qwen team — Qwen3.8-27B base model
- Unsloth — Dynamic V3 GGUF quantization reference / importance matrix
- Heretic / low-drift derivative authors
- ggml-org / llama.cpp
