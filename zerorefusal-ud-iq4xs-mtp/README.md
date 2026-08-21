# ZeroRefusal UD-IQ4_XS MTP release assets

This directory is the reproducible release bundle for:

```text
Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
```

## Production profile

```text
upstream llama.cpp b10435 / 9e40df6
70 × 1024 context / P2 / unified Q4_0 KV
MTP-1 / F16 draft KV / backend draft sampling disabled
full-GPU text model
F16 Vision projector on CPU / image cap 4096
```

## Integrity

```text
bytes:  14252845024
sha256: 18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
tensors: 866 total, 15 embedded MTP
```

## Use

- `production-command.sh` starts the validated command on port 8001.
- `qwen27b.service` is the production systemd unit.
- `huggingface/README.md` is the public model card.
- `publish-huggingface.sh` uploads and verifies the new public release, then deletes the superseded LowDrift HF repository.
- `verify-huggingface-public.sh` rechecks discoverability and public downloads.

The source BF16 behavior scores are not automatically inherited as measured GGUF scores. Run the same refusal suite before attaching 0/64 to this quantized artifact.
