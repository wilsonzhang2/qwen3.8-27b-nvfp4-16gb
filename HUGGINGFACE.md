# Hugging Face release

Target repository:

```text
QQZ2026/Qwen3.8-27B-ZeroRefusal-UD-IQ4_XS-MTP-GGUF
```

The publisher performs this sequence:

1. Verify the local GGUF byte count and SHA256.
2. Create the new model repository privately.
3. Upload GGUF, model card, checksum and inherited license.
4. Verify the remote files and make the new repository public.
5. Verify the public download endpoint.
6. Delete the superseded LowDrift repository only after the new release passes.

Run on VM101:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/zerorefusal-ud-iq4xs-mtp/publish-huggingface.sh \
  | bash
```

If authentication is missing:

```bash
/home/ai/.venvs/hf-publish/bin/hf auth login
```

Final verification:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/wilsonzhang2/qwen3.8-27b-nvfp4-16gb/main/zerorefusal-ud-iq4xs-mtp/verify-huggingface-public.sh \
  | bash
```

The expected final line is `PUBLIC RELEASE VERIFY: PASS`.
