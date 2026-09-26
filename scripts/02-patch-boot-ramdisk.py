#!/usr/bin/env python3
"""
Remove the mandatory 'product' mount from the first-stage fstab inside a MediaTek
boot image, and repack it byte-identically otherwise.

Why: the LineageOS GSI system image is ~3.5 GB while 'super' is 4 GB, of which stock
'product' occupies 1.7 GB. Deleting the product partition is the only way to make room,
but the ramdisk fstab lists it as a mandatory first-stage mount, so the device will not
boot unless the entry is removed too.

    usage: ./02-patch-boot-ramdisk.py backup/boot.bin boot_noproduct.img
    then:  sudo venv/bin/python mtk.py w boot boot_noproduct.img   (phone in BROM)

Header layout note (this is what bites people): the image uses boot header v2, where
  0x660  recovery_dtbo_size (u32) + recovery_dtbo_offset (u64)
  0x66C  header_size        (u32)      <-- NOT the dtb size
  0x670  dtb_size           (u32) + dtb_addr (u64)
Reading dtb_size from 0x66C yields the header size (1660) instead of the real value
(~100 KB): the DTB then gets truncated, and the phone dies silently at boot.
"""
import gzip
import struct
import sys


def patch(src_path: str, out_path: str) -> None:
    b = open(src_path, "rb").read()
    if b[:8] != b"ANDROID!":
        raise SystemExit("not an Android boot image")

    ks, _ka, rs, _ra, ss, _sa, _tl, ps = struct.unpack("<8I", b[8:40])
    (hv,) = struct.unpack("<I", b[40:44])
    if hv != 2:
        raise SystemExit(f"expected boot header v2, got v{hv}")

    rds, _rdo = struct.unpack("<IQ", b[1632:1644])   # recovery_dtbo
    (_hsz,) = struct.unpack("<I", b[1644:1648])      # header_size
    dts, _dto = struct.unpack("<IQ", b[1648:1660])   # dtb  <- offset 0x670

    def al(x: int) -> int:
        return (x + ps - 1) // ps * ps

    o = ps
    kernel = b[o:o + ks];   o += al(ks)
    ramdisk = b[o:o + rs];  o += al(rs)
    second = b[o:o + ss];   o += al(ss)
    rec_dtbo = b[o:o + rds]; o += al(rds)
    dtb = b[o:o + dts]

    print(f"kernel={ks} ramdisk={rs} second={ss} recovery_dtbo={rds} dtb={dts} pagesize={ps}")
    if dtb[:4] != bytes.fromhex("d7b7ab1e") and dtb[:4] != bytes.fromhex("d00dfeed"):
        print(f"warning: unexpected DTB magic {dtb[:4].hex()}")

    # Walk the newc cpio archive and rewrite every fstab.* entry.
    data = gzip.decompress(ramdisk)
    i, out, removed = 0, bytearray(), 0
    while i < len(data):
        if data[i:i + 6] != b"070701":
            raise SystemExit(f"cpio desync at offset {i}")
        name_size = int(data[i + 94:i + 102], 16)
        file_size = int(data[i + 54:i + 62], 16)
        name = data[i + 110:i + 110 + name_size - 1].decode()
        hdr_size = (110 + name_size + 3) & ~3
        total = (hdr_size + file_size + 3) & ~3
        entry = data[i:i + total]

        if name.startswith("fstab."):
            lines = data[i + hdr_size:i + hdr_size + file_size].decode().splitlines(True)
            kept = [ln for ln in lines if not ln.split() or ln.split()[0] != "product"]
            dropped = len(lines) - len(kept)
            removed += dropped
            payload = "".join(kept).encode()
            hdr = bytearray(data[i:i + hdr_size])
            hdr[54:62] = b"%08x" % len(payload)
            entry = bytes(hdr) + payload
            entry += b"\0" * ((-len(entry)) % 4)
            print(f"  patched {name}: removed {dropped} line(s)")

        out += entry
        if name == "TRAILER!!!":
            break
        i += total

    if removed != 2:
        raise SystemExit(f"expected to patch 2 fstab files, patched {removed} line(s) - aborting")

    new_ramdisk = gzip.compress(bytes(out), 9)
    hdr = bytearray(b[:ps])
    hdr[16:20] = struct.pack("<I", len(new_ramdisk))

    img = (bytes(hdr)
           + kernel      + b"\0" * (al(ks) - ks)
           + new_ramdisk + b"\0" * (al(len(new_ramdisk)) - len(new_ramdisk))
           + second      + b"\0" * (al(ss) - ss)
           + rec_dtbo    + b"\0" * (al(rds) - rds)
           + dtb         + b"\0" * (al(dts) - dts))
    open(out_path, "wb").write(img)

    # Read it back and prove the DTB survived and 'product' is gone.
    c = open(out_path, "rb").read()
    ks2, _, rs2 = struct.unpack("<3I", c[8:20])
    dts2 = struct.unpack("<I", c[1648:1652])[0]
    off = ps + al(ks2) + al(rs2) + al(struct.unpack("<I", c[24:28])[0])
    check = gzip.decompress(c[ps + al(ks2):ps + al(ks2) + rs2])
    print(f"written {out_path} ({len(img)} bytes)")
    print(f"verify: dtb_size={dts2} (was {dts}), "
          f"'product' still present in ramdisk: {b'product ' in check}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    patch(sys.argv[1], sys.argv[2])
