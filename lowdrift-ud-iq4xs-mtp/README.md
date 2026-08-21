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

## Provenance

Main model behavior comes from the low-drift Heretic derivative `asfgsdfg/Qwen3.8-27B-Heretic`, whose published checkpoint targets low KL drift while reducing refusal behavior.

The quantization layout is reproduced from Unsloth's Qwen3.8-27B Dynamic V3 `UD-IQ4_XS` artifact. The original reference GGUF used for the tensor-type map was:

- `Qwen3.8-27B-UD-IQ4_XS.gguf`
- Size: `14,252,845,984 bytes`
- SHA256: `40fac4050e940397dbf13087afd50f4734a11805bf9d65ef8ddd7483470e6199`

The original UD tensor map was reproduced exactly for all 851 main-model tensors (`851/851`, `0 mismatch`). The embedded MTP layer (`blk.64`) was grafted byte-for-byte from the original Unsloth GGUF.

## Verification

Final verification results:

```text
original tensors : 866
final tensors    : 866
missing tensors  : 0
extra tensors    : 0
structure mismatch: 0
MTP tensors      : 15
MTP byte mismatch: 0
block_count      : 65
nextn_predict    : 1
FINAL VERIFY     : PASS
```

All 15 embedded MTP tensors match the source artifact byte-for-byte by SHA256.

## Tested 16 GB production profiles

Hardware: NVIDIA GeForce RTX 5060 Ti 16 GB.

### Recommended production profile

```text
Context: 68,096
Parallel slots: P2
MTP draft max: 2
Main KV: Q4_0 / Q4_0
Draft KV: F16 / F16
Vision projector: CPU offload
GPU memory used after load: ~15,650 MiB
GPU memory free after load: ~240 MiB
```

Intended scheduling policy:

- Short customer-service lane: cap each request to ~4K context.
- Main reasoning/coding lane: allow up to ~64K.
- Keep at most one active short-lane task and one active main-lane task.

### Measured MTP behavior

At 76K / P2 / MTP-2:

```text
decode: 50.78 tok/s
draft acceptance: 73.53%
mean accepted length: 2.47
```

At 88K / P2 / MTP-1:

```text
decode: 43.28 tok/s
draft acceptance: 86.99%
mean accepted length: 1.87
```

80K / P2 / MTP-2 exceeded the 16 GB VRAM budget during MTP-context allocation.

## llama.cpp

The tested MTP server binary is based on llama.cpp b10435 with the previously validated FA-transient memory patch used for 16 GB MTP operation.

The production command is included in `production-command.sh`.

## Notes

This derivative intentionally prioritizes retaining base-model capability while reducing refusal behavior. It should not be described as mathematically identical to the original model: any behavioral weight edit changes the output distribution. The low-drift source checkpoint was selected specifically to minimize that change.

Vision/mmproj weights are not included in this repository. Use the matching Qwen3.8-27B F16 multimodal projector and keep it CPU-offloaded when GPU memory is constrained.

## Credits

- Qwen team — Qwen3.8-27B base model
- Unsloth — Dynamic V3 GGUF quantization reference / importance matrix
- Heretic / low-drift derivative authors
- ggml-org / llama.cpp
