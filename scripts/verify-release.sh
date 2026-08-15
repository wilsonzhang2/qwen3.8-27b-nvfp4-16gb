#!/usr/bin/env bash
set -Eeuo pipefail

MODEL=${MODEL:-/opt/models/qwen3.8-27b-avifenesh/Qwen3.8-27B-NVFP4-Q5K-no-MTP.gguf}
MMPROJ=${MMPROJ:-/opt/models/qwen3.8-27b-avifenesh/mmproj-Qwen3.8-27B-F16.gguf}
LLAMA_ROOT=${LLAMA_ROOT:-/opt/llama.cpp-qwen38}
PATCH_FILE=${PATCH_FILE:-$HOME/b10435-fa-transient-final.patch}

EXPECTED_MODEL_SHA=828c54b45e711a7579abe007aeea46c4fbadb71cacc07545239ffb6efa332e66
EXPECTED_MMPROJ_SHA=71101eb61e223e70e58b762c596f5303b63a91aec45fd9cdc5dad5592377f2ee
EXPECTED_LLAMA_COMMIT=9e40df63ba151d771d8b247ac4011cf203337e99

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$MODEL" ]] || fail "missing model: $MODEL"
[[ -f "$MMPROJ" ]] || fail "missing mmproj: $MMPROJ"
[[ -d "$LLAMA_ROOT/.git" ]] || fail "not a llama.cpp git tree: $LLAMA_ROOT"

model_sha=$(sha256sum "$MODEL" | awk '{print $1}')
mmproj_sha=$(sha256sum "$MMPROJ" | awk '{print $1}')
llama_commit=$(git -C "$LLAMA_ROOT" rev-parse HEAD)

[[ "$model_sha" == "$EXPECTED_MODEL_SHA" ]] || fail "model SHA mismatch: $model_sha"
[[ "$mmproj_sha" == "$EXPECTED_MMPROJ_SHA" ]] || fail "mmproj SHA mismatch: $mmproj_sha"
[[ "$llama_commit" == "$EXPECTED_LLAMA_COMMIT" ]] || fail "llama.cpp commit mismatch: $llama_commit"

echo "MODEL_SHA256_OK=$model_sha"
echo "MMPROJ_SHA256_OK=$mmproj_sha"
echo "LLAMA_COMMIT_OK=$llama_commit"

python3 - "$MODEL" <<'PY'
import struct, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    if f.read(4) != b'GGUF':
        raise SystemExit('ERROR: not a GGUF file')
    version = struct.unpack('<I', f.read(4))[0]
    n_tensors, n_kv = struct.unpack('<QQ', f.read(16))

    def s():
        n = struct.unpack('<Q', f.read(8))[0]
        return f.read(n).decode('utf-8', errors='replace')

    def value(t):
        if t == 4: return struct.unpack('<I', f.read(4))[0]
        if t == 5: return struct.unpack('<i', f.read(4))[0]
        if t == 8: return s()
        if t == 10: return struct.unpack('<Q', f.read(8))[0]
        if t == 11: return struct.unpack('<q', f.read(8))[0]
        if t == 7: return bool(struct.unpack('<?', f.read(1))[0])
        if t == 0: return struct.unpack('<B', f.read(1))[0]
        if t == 1: return struct.unpack('<b', f.read(1))[0]
        if t == 2: return struct.unpack('<H', f.read(2))[0]
        if t == 3: return struct.unpack('<h', f.read(2))[0]
        if t == 6: return struct.unpack('<f', f.read(4))[0]
        if t == 12: return struct.unpack('<d', f.read(8))[0]
        if t == 9:
            et = struct.unpack('<I', f.read(4))[0]
            n = struct.unpack('<Q', f.read(8))[0]
            return [value(et) for _ in range(n)]
        raise RuntimeError(f'unsupported GGUF metadata type {t}')

    kv = {}
    for _ in range(n_kv):
        k = s(); t = struct.unpack('<I', f.read(4))[0]; kv[k] = value(t)

print('GGUF_VERSION=', version, sep='')
print('TENSORS=', n_tensors, sep='')
for k in ('qwen35.block_count', 'qwen35.nextn_predict_layers'):
    print(f'{k}={kv.get(k)!r}')

if kv.get('qwen35.block_count') != 64:
    raise SystemExit('ERROR: qwen35.block_count != 64')
if kv.get('qwen35.nextn_predict_layers') != 0:
    raise SystemExit('ERROR: qwen35.nextn_predict_layers != 0')
PY

if [[ -f "$PATCH_FILE" ]]; then
    echo "PATCH_FILE=$PATCH_FILE"
    sha256sum "$PATCH_FILE"
    if git -C "$LLAMA_ROOT" diff --quiet; then
        echo "NOTE: llama.cpp working tree is clean; testing patch applicability."
        git -C "$LLAMA_ROOT" apply --check "$PATCH_FILE" || fail "patch does not apply cleanly to tested base tree"
    else
        echo "NOTE: llama.cpp working tree is modified; patch applicability check skipped."
    fi
else
    echo "NOTE: exact patch file not found at $PATCH_FILE"
fi

echo "RELEASE_VERIFICATION_OK"
