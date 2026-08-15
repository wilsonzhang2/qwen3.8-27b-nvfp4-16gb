#!/usr/bin/env bash
set -Eeuo pipefail

MODEL=/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf
MMPROJ=/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf
LLAMA=/opt/llama.cpp-qwen38
SNAP=/opt/qwen38-production/2026-08-15
SERVICE=qwen27b.service

echo '===== PRODUCTION KEEP SET ====='
printf '%-18s %s\n' 'model' "$MODEL" 'mmproj' "$MMPROJ" 'llama.cpp' "$LLAMA" 'snapshot' "$SNAP" 'service' "$SERVICE"

echo; echo '===== SERVICE / API ====='
systemctl is-enabled "$SERVICE" || true
systemctl is-active "$SERVICE" || true
curl -fsS --max-time 3 http://127.0.0.1:8001/health || true
echo

echo; echo '===== ROOT FILESYSTEM ====='
df -hT /

echo; echo '===== /opt TOP LEVEL ====='
sudo du -xhd1 /opt 2>/dev/null | sort -h

echo; echo '===== /opt/models ====='
sudo du -xhd2 /opt/models 2>/dev/null | sort -h

echo; echo '===== GGUF FILES ====='
sudo find /opt/models -type f -iname '*.gguf' -printf '%s\t%p\n' 2>/dev/null | sort -nr | awk '{printf "%.2f GiB\t",$1/1073741824; $1=""; sub(/^ /,""); print}'

echo; echo '===== LLAMA.CPP TREES / BACKUPS ====='
sudo find /opt -maxdepth 2 -type d \( -name 'llama.cpp*' -o -name '*llama*backup*' -o -name '*pre-*' \) -print 2>/dev/null | while read -r d; do sudo du -sh "$d" 2>/dev/null || true; done | sort -h

echo; echo '===== PRODUCTION SNAPSHOTS ====='
sudo find /opt/qwen38-production -maxdepth 2 -type d -print 2>/dev/null | while read -r d; do sudo du -sh "$d" 2>/dev/null || true; done | sort -h

echo; echo '===== HOME LARGE FILES ====='
find /home/ai -xdev -type f -size +100M -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -80 | awk '{printf "%.2f GiB\t",$1/1073741824; $1=""; sub(/^ /,""); print}'

echo; echo '===== HOME CACHES ====='
for d in /home/ai/.cache /home/ai/.cache/huggingface /home/ai/.cache/pip /home/ai/.venvs /home/ai/qwen38-publish; do [[ -e "$d" ]] && du -sh "$d" 2>/dev/null || true; done

echo; echo '===== /var CACHES / LOGS ====='
sudo du -sh /var/cache/apt /var/log /var/lib/systemd/coredump 2>/dev/null || true
journalctl --disk-usage 2>/dev/null || true

echo; echo '===== OLD QWEN SERVICES ====='
systemctl list-unit-files --type=service | grep -Ei 'qwen|llama|comfy' || true

echo; echo '===== CANDIDATE TEST LOGS ====='
find /home/ai -maxdepth 1 -type f \( -name 'qwen38*.log' -o -name 'qwen38*.csv' -o -name '*vram*.csv' -o -name '*audit*.txt' \) -printf '%s\t%p\n' 2>/dev/null | sort -nr | awk '{printf "%.1f MiB\t",$1/1048576; $1=""; sub(/^ /,""); print}'

echo; echo '===== DO NOT DELETE ====='
echo "$MODEL"
echo "$MMPROJ"
echo "$LLAMA"
echo "$SNAP"
echo '/etc/systemd/system/qwen27b.service'
echo '/home/ai/.venvs/hf-publish   # small, keep for HF maintenance'

echo; echo 'Audit only. Nothing was deleted.'
