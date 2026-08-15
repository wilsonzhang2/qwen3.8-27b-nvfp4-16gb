#!/usr/bin/env bash
set -Eeuo pipefail

COMFY=/opt/comfyui
TARGET_TAG=v0.33.1
QWEN_SERVICE=qwen27b.service
COMFY_SERVICE=comfyui-qwen-image.service
STATE_DIR=/opt/qwen38-production/2026-08-15
HF_REPO=Comfy-Org/MiniMax-H3
HF_VENV=/home/ai/.venvs/hf-publish
STAGE="$COMFY/models/.minimax-h3-stage"

H3_DIFF_REL=diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors
H3_TEXT_REL=text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
H3_VAE_REL=vae/minimax_h3_video_vae_fp16.safetensors
H3_AUDIO_VAE_REL=vae/minimax_h3_audio_vae_fp32.safetensors

HUNYUAN_DIFF="$COMFY/models/diffusion_models/hunyuanvideo1.5_480p_i2v_step_distilled_fp8_scaled.safetensors"
HUNYUAN_VAE="$COMFY/models/vae/hunyuanvideo15_vae_fp16.safetensors"
HUNYUAN_SUM="$COMFY/models/hunyuanvideo15-i2v-step-distilled.sha256"

fail() { echo "ERROR: $*" >&2; exit 1; }

sudo -v

[[ -d "$COMFY/.git" ]] || fail "ComfyUI git tree not found: $COMFY"
[[ -x "$COMFY/.venv/bin/python" ]] || fail "ComfyUI venv not found: $COMFY/.venv"
[[ -d "$STATE_DIR" ]] || fail "production state directory missing: $STATE_DIR"

# Qwen production is deliberately kept online throughout disk/code maintenance.
systemctl is-active --quiet "$QWEN_SERVICE" || fail "$QWEN_SERVICE is not active"
curl -fsS http://127.0.0.1:8001/health >/dev/null || fail "Qwen production API health check failed"

# ComfyUI must not be running while its code and weights are changed.
sudo systemctl stop "$COMFY_SERVICE" 2>/dev/null || true

printf '\n===== PHASE 1/3: UPGRADE COMFYUI TO %s =====\n' "$TARGET_TAG"
cd "$COMFY"
OLD_HEAD=$(git rev-parse HEAD)
OLD_DESCRIBE=$(git describe --tags --always --dirty 2>/dev/null || true)
echo "Current ComfyUI: $OLD_DESCRIBE ($OLD_HEAD)"

# Refuse to overwrite tracked local edits. Untracked deployment notes are preserved.
git diff --quiet || fail "tracked ComfyUI working-tree changes exist; refusing automatic upgrade"
git diff --cached --quiet || fail "staged ComfyUI changes exist; refusing automatic upgrade"

sudo mkdir -p "$STATE_DIR"
{
  echo "pre_h3_comfyui_head=$OLD_HEAD"
  echo "pre_h3_comfyui_describe=$OLD_DESCRIBE"
  echo "upgrade_target=$TARGET_TAG"
  date -Is | sed 's/^/upgrade_started=/'
} | sudo tee "$STATE_DIR/comfyui-h3-upgrade-state.txt" >/dev/null

if [[ -f DEPLOYMENT_VERSIONS.txt ]]; then
  sudo cp -a DEPLOYMENT_VERSIONS.txt "$STATE_DIR/DEPLOYMENT_VERSIONS.pre-h3.txt"
fi

# Keep a local rollback name for the old source state. This is code-only and tiny.
git tag -f comfyui-pre-h3-20260815 "$OLD_HEAD" >/dev/null

git fetch --force --tags origin "refs/tags/$TARGET_TAG:refs/tags/$TARGET_TAG" --depth=1
git checkout -B local/comfyui-h3-v0.33.1 "$TARGET_TAG"

# Do NOT use --upgrade here: torch/torchvision/torchaudio are intentionally kept
# at the already-working CUDA build unless the new requirements actually require a change.
"$COMFY/.venv/bin/python" -m pip install -r "$COMFY/requirements.txt"

NEW_HEAD=$(git rev-parse HEAD)
NEW_DESCRIBE=$(git describe --tags --always 2>/dev/null || true)
echo "Upgraded ComfyUI: $NEW_DESCRIBE ($NEW_HEAD)"
[[ -f "$COMFY/comfy_extras/nodes_minimax_h3.py" ]] || fail "MiniMax H3 native nodes are missing after upgrade"

PYTHONPATH="$COMFY" "$COMFY/.venv/bin/python" - <<'PY'
import torch, torchaudio
import comfy_extras.nodes_minimax_h3 as h3
print("torch:", torch.__version__)
print("torch CUDA:", torch.version.cuda)
print("MiniMax H3 native node import: OK")
print("H3 native canvas:", h3.BASE_SHORT_EDGE, "short edge; max pixels", h3.MAX_PIXELS)
PY

# Update only the descriptive service label. Preserve the known launcher, lowvram
# setting, port, and qwen27b conflict behavior.
if [[ -f /etc/systemd/system/comfyui-qwen-image.service ]]; then
  sudo sed -i 's/^Description=.*/Description=ComfyUI Qwen-Image-2512 and MiniMax H3/' /etc/systemd/system/comfyui-qwen-image.service
  sudo systemctl daemon-reload
fi

printf '\n===== PHASE 2/3: REMOVE HUNYUANVIDEO 1.5 =====\n'
echo "Removing only the audited HunyuanVideo 1.5 main model + VAE."
for f in "$HUNYUAN_DIFF" "$HUNYUAN_VAE" "$HUNYUAN_SUM"; do
  if [[ -e "$f" ]]; then
    ls -lh "$f"
    sudo rm -f -- "$f"
  else
    echo "Already absent: $f"
  fi
done

# Deliberately keep shared/uncertain assets such as Qwen text encoders, sigclip,
# Qwen-Image VAE, Qwen-Image NVFP4 and the old Q4_K_M until H3 is validated.
echo "Preserved Qwen-Image and shared encoder assets."

df -h /

printf '\n===== PHASE 3/3: DOWNLOAD OFFICIAL COMFYUI H3 SET =====\n'
mkdir -p "$STAGE"

if [[ -x "$HF_VENV/bin/hf" ]]; then
  # shellcheck disable=SC1091
  source "$HF_VENV/bin/activate"
else
  echo "Creating Hugging Face download venv: $HF_VENV"
  python3 -m venv "$HF_VENV"
  # shellcheck disable=SC1091
  source "$HF_VENV/bin/activate"
  python -m pip install --upgrade pip
  python -m pip install --upgrade huggingface_hub hf_xet
fi

command -v hf >/dev/null || fail "hf CLI not available"
export HF_XET_HIGH_PERFORMANCE=1

# One hf/xet job gives fast concurrent chunk transfer and is resumable if the SSH
# session is interrupted. Re-running this script reuses completed/partial data.
hf download "$HF_REPO" \
  "$H3_DIFF_REL" \
  "$H3_TEXT_REL" \
  "$H3_VAE_REL" \
  "$H3_AUDIO_VAE_REL" \
  --local-dir "$STAGE"

for rel in "$H3_DIFF_REL" "$H3_TEXT_REL" "$H3_VAE_REL" "$H3_AUDIO_VAE_REL"; do
  [[ -s "$STAGE/$rel" ]] || fail "downloaded file missing/empty: $rel"
done

mkdir -p "$COMFY/models/diffusion_models" "$COMFY/models/text_encoders" "$COMFY/models/vae"
mv -f "$STAGE/$H3_DIFF_REL" "$COMFY/models/diffusion_models/"
mv -f "$STAGE/$H3_TEXT_REL" "$COMFY/models/text_encoders/"
mv -f "$STAGE/$H3_VAE_REL" "$COMFY/models/vae/"
mv -f "$STAGE/$H3_AUDIO_VAE_REL" "$COMFY/models/vae/"
rm -rf "$STAGE"

H3_DIFF="$COMFY/models/diffusion_models/$(basename "$H3_DIFF_REL")"
H3_TEXT="$COMFY/models/text_encoders/$(basename "$H3_TEXT_REL")"
H3_VAE="$COMFY/models/vae/$(basename "$H3_VAE_REL")"
H3_AUDIO_VAE="$COMFY/models/vae/$(basename "$H3_AUDIO_VAE_REL")"

printf '\n===== H3 FILES =====\n'
ls -lh "$H3_DIFF" "$H3_TEXT" "$H3_VAE" "$H3_AUDIO_VAE"

MANIFEST="$STATE_DIR/comfyui-minimax-h3-manifest.txt"
{
  echo "prepared=$(date -Is)"
  echo "comfyui_tag=$TARGET_TAG"
  echo "comfyui_head=$NEW_HEAD"
  echo "hf_repo=$HF_REPO"
  echo
  sha256sum "$H3_DIFF" "$H3_TEXT" "$H3_VAE" "$H3_AUDIO_VAE"
} | sudo tee "$MANIFEST" >/dev/null

echo "Manifest: $MANIFEST"

# Leave ComfyUI disabled/inactive: qwen27b remains the production GPU service.
sudo systemctl disable "$COMFY_SERVICE" >/dev/null 2>&1 || true
sudo systemctl stop "$COMFY_SERVICE" >/dev/null 2>&1 || true

printf '\n===== FINAL VERIFICATION =====\n'
systemctl is-active --quiet "$QWEN_SERVICE" || fail "$QWEN_SERVICE stopped unexpectedly"
curl -fsS http://127.0.0.1:8001/health >/dev/null || fail "Qwen API unhealthy after H3 preparation"

echo "Qwen production: active / healthy"
echo "ComfyUI service: $(systemctl is-active "$COMFY_SERVICE" 2>/dev/null || true) / $(systemctl is-enabled "$COMFY_SERVICE" 2>/dev/null || true)"
echo "ComfyUI version: $(git -C "$COMFY" describe --tags --always 2>/dev/null || true)"
echo
sudo du -sh "$COMFY" "$COMFY/models" 2>/dev/null || true
df -h /

echo
echo "===== READY FOR MINIMAX H3 VALIDATION ====="
echo "Diffusion : $H3_DIFF"
echo "Text enc. : $H3_TEXT"
echo "Video VAE : $H3_VAE"
echo "Audio VAE : $H3_AUDIO_VAE"
echo "ComfyUI remains stopped so qwen27b keeps the GPU."
