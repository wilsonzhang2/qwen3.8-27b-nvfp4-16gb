# Attribution and provenance

This repository documents a derivative GGUF artifact and runtime configuration.

## Upstream model

Qwen3.8-27B was created by the Qwen team. Architecture, weights, language capability, multimodal capability and training originate from Qwen. The upstream model is distributed under Apache-2.0.

## Behavioral weight source

The language-model weights are derived from `junafinity/Qwen-3.8-27B-Uncensored`, revision `903d149c148b81fdf4e568a05ac9ad4225f493d7`. That checkpoint was created with ZeroFuse v0.1.0. Its model card reports edits to decoder attention `o_proj` and MLP `down_proj`; vision and embedded MTP tensors were copied unchanged from the base model.

## Quantization

The GGUF tensor-type map reproduces an earlier Unsloth UD-IQ4_XS preview-era layout with the corresponding imatrix. This artifact is independently converted and is not an official current Unsloth Dynamic V3 release.

## Runtime

Production validation uses the public upstream llama.cpp b10435 source at commit `9e40df63ba151d771d8b247ac4011cf203337e99`.

## License

Apache-2.0 terms inherited from Qwen and the behavioral source apply. ZeroFuse is separately MIT-licensed; its license does not replace the model license.
