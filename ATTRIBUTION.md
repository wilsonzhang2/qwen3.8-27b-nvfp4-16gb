# Attribution and Provenance

This repository is an independent community deployment project for a Qwen3.8-27B GGUF derivative and associated llama.cpp deployment experiments.

## Upstream model

Base-model metadata points to:

- **Qwen/Qwen3.8-27B** — official Qwen model repository on Hugging Face.

Qwen and the Qwen model family are developed by the Qwen / Alibaba Cloud team.

This repository does not claim authorship of the Qwen3.8 model architecture, tokenizer, pretrained weights, Vision encoder, or official model configuration.

## Source GGUF

The physical no-MTP artifact described here was created from a separately obtained Qwen3.8-27B NVFP4/Q5K GGUF that contained one embedded MTP / NextN layer.

The no-MTP rewrite:

- removes the MTP block tensors;
- changes model metadata from 65 blocks to 64;
- changes `nextn_predict_layers` from 1 to 0;
- copies all retained tensors without requantizing them.

If the derivative GGUF is redistributed, the publisher must also preserve any attribution, notices, and license conditions required by the **specific upstream quantized GGUF** used as the source artifact.

Do not infer redistribution rights from this repository alone.

## Vision projector

The F16 `mmproj` described in this project was generated from the official `Qwen/Qwen3.8-27B` checkpoint with llama.cpp's multimodal conversion tooling.

The generated projector remains a derivative of the upstream Qwen model weights and must follow the applicable upstream model license and attribution requirements.

## llama.cpp

Inference, GGUF tooling, multimodal conversion, and the CUDA experiments described here use **llama.cpp** by the ggml-org community.

Project:

- https://github.com/ggml-org/llama.cpp

The transient Flash-Attention experiment is a local modification to one tested llama.cpp revision. It is **not an official llama.cpp patch or supported configuration**.

## Local work

The following work was performed for this repository:

- physical no-MTP GGUF rewrite utility;
- RTX 5060 Ti 16 GB deployment validation;
- full-GPU / partial-offload A/B measurements;
- 64K/P2 continuous-batching validation;
- Qwen3.8 F16 mmproj conversion and CPU-offload validation;
- 40K MAIN + simultaneous Vision customer-service stress test;
- experimental transient Flash-Attention scratch-allocation patch analysis;
- documentation and deployment scripts.

Validation / repository owner:

- Wilson Zhang
- GitHub: https://github.com/wilsonzhang2

## No affiliation

This repository is not affiliated with or endorsed by Qwen, Alibaba Cloud, NVIDIA, Hugging Face, ggml-org, or the llama.cpp maintainers.

Product names and trademarks belong to their respective owners.

## License handling

Before redistributing any model or projector weights, inspect the **current license files in the exact upstream model repositories** and preserve all required notices.

The documentation here is intended to make the transformation and benchmark provenance explicit; it is not a substitute for the upstream license text and is not itself a grant of rights to redistribute third-party model weights.
