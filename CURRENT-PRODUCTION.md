# Current production baseline — 2026-08-21

The current VM101 production target is no longer the earlier NVFP4 no-MTP profile.

Current production model:

```text
Qwen3.8-27B-LowDrift-UD-IQ4_XS-MTP.gguf
SHA256: 49021e6e76af0ac6298e56aa4fab1ed56b62c7c66b6e7a18933907185bd1827d
Size: 14,252,845,184 bytes (~13.274 GiB)
```

Production runtime:

```text
-c 68000                -> runtime n_ctx observed around 68,096
-np 2                   -> P2
--kv-unified
-ctk q4_0
-ctv q4_0
--spec-type draft-mtp
--spec-draft-n-max 2     -> MTP-2
--spec-draft-type-k f16
--spec-draft-type-v f16
-ngl 999
--flash-attn on
--no-mmproj-offload
--image-max-tokens 4096
```

Hardware validation target: NVIDIA GeForce RTX 5060 Ti 16 GB.

Measured cold-load state at 68K / P2 / MTP-2:

```text
GPU used: ~15,650 MiB
GPU free: ~240 MiB
```

Workload policy:

```text
A / short customer service: <= ~4K context
B / main reasoning-coding:   <= ~64K context
```

Measured neighboring MTP-2 performance:

```text
72K: 51.48 tok/s, 75.66% draft acceptance, mean accepted length 2.51
76K: 50.78 tok/s, 73.53% draft acceptance, mean accepted length 2.47
80K: OOM during MTP-context allocation
```

68K is intentionally selected below those measured limits to retain additional VRAM margin while preserving the MTP-2 performance regime.

A repeated 24K-prefill diagnostic at 60K showed a one-time ~106 MiB CUDA-pool high-water allocation on the first long request and +0 MiB additional retained allocation on the next two repeats. This was treated as warm-up/high-water behavior rather than a continuing leak.

Full release documentation and publishing helpers:

[`lowdrift-ud-iq4xs-mtp/`](lowdrift-ud-iq4xs-mtp/)
