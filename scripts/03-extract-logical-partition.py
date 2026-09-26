#!/usr/bin/env python3
"""
Extract one logical partition (system / vendor / product) from a raw dump of the
'super' partition, by parsing the Android LP metadata.

    usage: ./03-extract-logical-partition.py backup/super.bin vendor vendor_stock.img
           ./03-extract-logical-partition.py backup/super.bin --list

Useful both for pulling the stock vendor out of a mtkclient backup, and for pulling
'system' out of the Android emulator image (which is itself a super container).

Layout: 4096-byte geometry block at offset 4096 (magic 'gDla'), then two metadata
slots; the primary header sits at 4096*3 (magic '0PLA'), and the descriptor offsets
live at header+80.
"""
import struct
import sys

GEOMETRY_MAGIC = b"gDla"   # 0x616c4467 little-endian
HEADER_MAGIC = b"0PLA"     # 0x414c5030 little-endian


def read_metadata(f):
    f.seek(4096)
    if f.read(4) != GEOMETRY_MAGIC:
        raise SystemExit("geometry magic not found - is this really a super image?")
    base = 4096 * 3
    f.seek(base)
    hdr = f.read(256)
    if hdr[:4] != HEADER_MAGIC:
        raise SystemExit("metadata header magic not found")
    header_size = struct.unpack("<I", hdr[8:12])[0]
    d = struct.unpack("<12I", hdr[80:128])
    part_off, part_num, part_entry = d[0:3]
    ext_off, ext_num, ext_entry = d[3:6]
    group_off, group_num, group_entry = d[6:9]
    tables = base + header_size

    f.seek(tables + ext_off)
    extents = [struct.unpack("<QIQI", f.read(ext_entry)[:24]) for _ in range(ext_num)]

    f.seek(tables + group_off)
    groups = []
    for _ in range(group_num):
        g = f.read(group_entry)
        groups.append((g[:36].split(b"\0")[0].decode(),
                       struct.unpack("<Q", g[40:48])[0]))

    f.seek(tables + part_off)
    parts = {}
    for _ in range(part_num):
        p = f.read(part_entry)
        name = p[:36].split(b"\0")[0].decode()
        _attr, first_extent, num_extents, group_index = struct.unpack("<IIII", p[36:52])
        parts[name] = (extents[first_extent:first_extent + num_extents],
                       groups[group_index][0] if group_index < len(groups) else "?")
    return parts, groups


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    super_path = sys.argv[1]
    with open(super_path, "rb") as f:
        parts, groups = read_metadata(f)

        if sys.argv[2] == "--list":
            print("groups:", ", ".join(f"{n} ({m // 2**20} MB max)" for n, m in groups))
            for name, (exts, grp) in parts.items():
                size = sum(e[0] for e in exts) * 512
                print(f"  {name:12s} {size / 2**20:9.1f} MB   group={grp}")
            return

        want, out_path = sys.argv[2], sys.argv[3]
        if want not in parts:
            raise SystemExit(f"'{want}' not found. Available: {', '.join(parts)}")
        exts, _ = parts[want]
        total = sum(e[0] for e in exts) * 512
        with open(out_path, "wb") as o:
            for num_sectors, _target_type, target_data, _ in exts:
                f.seek(target_data * 512)
                remaining = num_sectors * 512
                while remaining:
                    chunk = f.read(min(remaining, 1 << 24))
                    if not chunk:
                        raise SystemExit("unexpected EOF while reading extents")
                    o.write(chunk)
                    remaining -= len(chunk)
        print(f"{want} -> {out_path} ({total / 2**20:.1f} MB)")


if __name__ == "__main__":
    main()
