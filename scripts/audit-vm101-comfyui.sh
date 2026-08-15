#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/opt/comfyui

echo "===== COMFYUI CLEANUP AUDIT (READ ONLY) ====="
[[ -d "$ROOT" ]] || { echo "ERROR: $ROOT not found" >&2; exit 1; }

printf '\n===== SERVICE =====\n'
systemctl is-enabled comfyui-qwen-image.service 2>/dev/null || true
systemctl is-active comfyui-qwen-image.service 2>/dev/null || true
systemctl cat comfyui-qwen-image.service 2>/dev/null | sed -n '1,140p' || true

printf '\n===== TOTAL / TOP LEVEL =====\n'
du -sh "$ROOT"
du -sh "$ROOT"/* "$ROOT"/.[!.]* 2>/dev/null | sort -h | tail -40

printf '\n===== MODELS TOP LEVEL =====\n'
if [[ -d "$ROOT/models" ]]; then
  du -sh "$ROOT/models"/* 2>/dev/null | sort -h
else
  echo "No $ROOT/models directory"
fi

printf '\n===== MODEL FILES >= 100 MiB =====\n'
find "$ROOT" -xdev -type f -size +100M -printf '%s\t%p\n' 2>/dev/null \
  | sort -nr \
  | awk -F '\t' '{printf "%.2f GiB\t%s\n", $1/1073741824, $2}' \
  | head -200

printf '\n===== COMMON MODEL EXTENSIONS =====\n'
find "$ROOT" -xdev -type f \( \
    -iname '*.safetensors' -o -iname '*.gguf' -o -iname '*.pt' -o \
    -iname '*.pth' -o -iname '*.ckpt' -o -iname '*.bin' -o -iname '*.onnx' \) \
  -printf '%s\t%p\n' 2>/dev/null \
  | sort -nr \
  | awk -F '\t' '{printf "%.2f GiB\t%s\n", $1/1073741824, $2}' \
  | head -250

printf '\n===== OUTPUT / INPUT / TEMP =====\n'
for d in output input temp user; do
  if [[ -e "$ROOT/$d" ]]; then du -sh "$ROOT/$d"; fi
done

printf '\n===== CACHE-LIKE DIRECTORIES =====\n'
find "$ROOT" -xdev -type d \( \
  -name '.cache' -o -name '__pycache__' -o -name '.pytest_cache' -o \
  -name 'cache' -o -name 'tmp' -o -name 'temp' \) -print0 2>/dev/null \
  | xargs -0 -r du -sh 2>/dev/null | sort -h | tail -80

printf '\n===== GIT / VENV / PYTHON ENV =====\n'
[[ -d "$ROOT/.git" ]] && git -C "$ROOT" status --short && git -C "$ROOT" log -1 --oneline || true
for d in "$ROOT"/.venv "$ROOT"/venv "$ROOT"/env; do
  [[ -d "$d" ]] && du -sh "$d"
done

printf '\n===== SYMLINKS =====\n'
find "$ROOT" -xdev -type l -printf '%p -> %l\n' 2>/dev/null | head -200

printf '\n===== ROOT FILESYSTEM =====\n'
df -h /

echo
echo "Audit only. Nothing was deleted."
