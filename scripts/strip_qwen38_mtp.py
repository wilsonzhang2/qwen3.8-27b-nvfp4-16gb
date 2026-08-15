#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path
import gguf

if len(sys.argv) != 3:
    raise SystemExit("Usage: strip_qwen38_mtp.py INPUT.gguf OUTPUT.gguf")

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

if not src.is_file():
    raise SystemExit(f"ERROR: source not found: {src}")
if dst.exists():
    raise SystemExit(f"ERROR: destination already exists: {dst}")

reader = gguf.GGUFReader(src, "r")

def get(name):
    f = reader.get_field(name)
    return f.contents() if f else None

arch = get(gguf.Keys.General.ARCHITECTURE)
if not arch:
    raise SystemExit("ERROR: general.architecture missing")

block_key = f"{arch}.block_count"
nextn_key = f"{arch}.nextn_predict_layers"

old_blocks = get(block_key)
nextn = get(nextn_key)

if old_blocks is None or nextn is None:
    raise SystemExit("ERROR: missing block_count or nextn_predict_layers metadata")

old_blocks = int(old_blocks)
nextn = int(nextn)
if nextn <= 0:
    raise SystemExit(f"ERROR: nextn_predict_layers={nextn}")

new_blocks = old_blocks - nextn

remove_names = set()
remove_bytes = 0
for t in reader.tensors:
    m = re.match(r"^blk\.(\d+)\.", t.name)
    if m and int(m.group(1)) >= new_blocks:
        remove_names.add(t.name)
        remove_bytes += t.n_bytes

if not remove_names:
    raise SystemExit("ERROR: no MTP tensors found")

print("architecture         =", arch)
print("block_count          =", old_blocks, "->", new_blocks)
print("nextn_predict_layers =", nextn, "-> 0")
print("MTP tensors          =", len(remove_names))
print("MTP size             = %.2f MiB" % (remove_bytes / 1024 / 1024))

writer = gguf.GGUFWriter(dst, arch=arch, endianess=reader.endianess)

alignment = get(gguf.Keys.General.ALIGNMENT)
if alignment is not None:
    writer.data_alignment = int(alignment)

for field in reader.fields.values():
    if field.name == gguf.Keys.General.ARCHITECTURE or field.name.startswith("GGUF."):
        continue

    val_type = field.types[0]
    sub_type = field.types[-1] if val_type == gguf.GGUFValueType.ARRAY else None
    value = field.contents()

    if field.name == block_key:
        value = new_blocks
    elif field.name == nextn_key:
        value = 0
    elif field.name.startswith(f"{arch}.") and val_type == gguf.GGUFValueType.ARRAY:
        try:
            if len(value) == old_blocks:
                value = value[:new_blocks]
        except TypeError:
            pass

    writer.add_key_value(field.name, value, val_type, sub_type=sub_type)

kept = []
for t in reader.tensors:
    if t.name in remove_names:
        continue
    writer.add_tensor_info(t.name, t.data.shape, t.data.dtype, t.data.nbytes, t.tensor_type)
    kept.append(t)

writer.write_header_to_file()
writer.write_kv_data_to_file()
writer.write_ti_data_to_file()

for i, t in enumerate(kept, 1):
    writer.write_tensor_data(t.data, tensor_endianess=reader.endianess)
    if i % 100 == 0 or i == len(kept):
        print(f"tensor {i}/{len(kept)}")

writer.close()

print("DONE:", dst)
print("Removed %.2f MiB" % (remove_bytes / 1024 / 1024))
