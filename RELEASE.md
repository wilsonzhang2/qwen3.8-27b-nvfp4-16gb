# ZeroRefusal UD-IQ4_XS MTP release

## Artifact

```text
Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP.gguf
14252845024 bytes
18f169aa0749a4f136ae0a7bae232ebba6df7784d4fe0616522e88658c9a1260
```

The GGUF contains 866 tensors. Its 15 MTP tensors are embedded, and its tensor-type map matches the 13.27 GiB UD-IQ4_XS reference layout. The 160-byte total-file difference from the reference is metadata; tensor data size is equal.

## Provenance

- Base: `Qwen/Qwen3.8-27B`.
- Behavior source: `junafinity/Qwen-3.8-27B-Uncensored` at revision `903d149c148b81fdf4e568a05ac9ad4225f493d7`.
- Behavior edit: ZeroFuse v0.1.0 directional ablation.
- Quantization: earlier Unsloth UD-IQ4_XS preview-era tensor layout and imatrix.
- Runtime: upstream llama.cpp b10435 commit `9e40df63ba151d771d8b247ac4011cf203337e99`.

## Published and measured claims

The source BF16 model publishes 0/64 refusals and KL divergence 0.00971. The quantized GGUF has not yet been rerun on that refusal suite, so those values are recorded only as source provenance.

The production runtime has passed 70×1024 loading, P2 short throughput, 4K+60K concurrent work, memory monitoring and post-test health checks. A real image request is still pending.
