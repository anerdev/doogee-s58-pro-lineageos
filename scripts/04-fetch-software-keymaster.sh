#!/usr/bin/env bash
# Extract an AOSP software keymaster 3.0 from Google's Android 10 arm64 emulator image.
#
# Why: this device's TrustKernel TEE refuses to serve keymaster once the bootloader is
# unlocked, so keystore2 hangs forever and the phone never finishes booting. There is no
# software keymaster in the stock vendor, so we borrow one from Google's own Android 10
# system image: same API level, same VNDK (29), so the libraries match the vendor.
#
#   usage: ./04-fetch-software-keymaster.sh [outdir]      (default: ./keymaster-sw)
#
# Produces:
#   keymaster-sw/android.hardware.keymaster@3.0-service        (vendor/bin/hw)
#   keymaster-sw/lib64/hw/android.hardware.keymaster@3.0-impl.so
#   keymaster-sw/lib64/*.so                                    (VNDK-29 support libs)
set -euo pipefail

URL="https://dl.google.com/android/repository/sys-img/android/arm64-v8a-29_r08.zip"
ZIP="arm64-v8a-29_r08.zip"
OUT="${1:-keymaster-sw}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT/lib64/hw" work && cd work

[ -f "$ZIP" ] || { echo ">>> Downloading Android 10 arm64 emulator image (~500 MB)"; curl -L -o "$ZIP" "$URL"; }
python3 - "$ZIP" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.endswith(("/vendor.img", "/system.img")):
        z.extract(n); print("extracted", n)
PY

cleanup() { sudo umount /tmp/emu-vendor /tmp/emu-system 2>/dev/null || true
            sudo losetup -D 2>/dev/null || true; }
trap cleanup EXIT
sudo mkdir -p /tmp/emu-vendor /tmp/emu-system

# vendor.img is a GPT container -> attach with partition scanning
LOOP=$(sudo losetup -fP --show arm64-v8a/vendor.img)
sudo mount -o ro "${LOOP}p1" /tmp/emu-vendor

# system.img is a 'super' container -> use the LP extractor
python3 "$HERE/03-extract-logical-partition.py" arm64-v8a/system.img system emu_system.img
sudo mount -o ro,loop emu_system.img /tmp/emu-system

cd "$HERE"
sudo cp /tmp/emu-vendor/bin/hw/android.hardware.keymaster@3.0-service          "$OUT/"
sudo cp /tmp/emu-vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so        "$OUT/lib64/hw/"
sudo cp /tmp/emu-vendor/lib64/libkeymaster3device.so                           "$OUT/lib64/"
for l in android.hardware.keymaster@3.0 libsoftkeymasterdevice \
         libpuresoftkeymasterdevice libkeymaster_portable libkeymaster_messages; do
  sudo cp "/tmp/emu-system/system/lib64/vndk-29/$l.so" "$OUT/lib64/"
done
sudo chown -R "$(id -u):$(id -g)" "$OUT"

echo
echo ">>> Collected in $OUT:"
find "$OUT" -type f -printf '  %8s  %p\n'
