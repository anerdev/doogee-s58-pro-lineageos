#!/usr/bin/env bash
# Build the patched vendor image that makes a GSI bootable on the Doogee S58 Pro.
#
#   usage: ./05-build-patched-vendor.sh vendor_stock.img vendor_mod.img [keymaster-sw-dir]
#
# Five changes, each explained inline below:
#   a) gatekeeper  -> libSoftGatekeeper.so (already present in the vendor)
#   b) keymaster   -> AOSP software keymaster 3.0 + VINTF manifest 4.0 -> 3.0
#   c) /data       -> file-based encryption removed from both fstabs
#   d) SELinux     -> labels restored on every file touched  (CRITICAL - see README)
#   e) build.prop  -> Bluetooth HCI workaround + audio standby time
set -euo pipefail

SRC="${1:?usage: $0 <vendor_stock.img> <vendor_mod.img> [keymaster-sw-dir]}"
DST="${2:?usage: $0 <vendor_stock.img> <vendor_mod.img> [keymaster-sw-dir]}"
KM="${3:-keymaster-sw}"
MNT=/tmp/vendor-mod

[ -d "$KM/lib64" ] || { echo "software keymaster not found in '$KM' - run 04-fetch-software-keymaster.sh"; exit 1; }
command -v setfattr >/dev/null || { echo "install 'attr' (sudo apt install attr)"; exit 1; }

echo ">>> Copying and growing the image (stock vendor is 100% full)"
cp --reflink=auto "$SRC" "$DST"
truncate -s 356M "$DST"
e2fsck -fy "$DST" >/dev/null 2>&1 || true
resize2fs "$DST"

sudo mkdir -p "$MNT"
sudo umount "$MNT" 2>/dev/null || true
sudo mount -o loop,rw "$DST" "$MNT"
trap 'sync; sudo umount "$MNT" 2>/dev/null || true' EXIT

echo ">>> (a) gatekeeper -> software implementation"
sudo ln -sfn libSoftGatekeeper.so "$MNT/lib64/hw/gatekeeper.mt6765.so"
sudo ln -sfn libSoftGatekeeper.so "$MNT/lib64/hw/gatekeeper.k62v1_64_bsp.so"

echo ">>> (b) keymaster: disable TrustKernel service, install software keymaster 3.0"
sudo mv "$MNT/etc/init/android.hardware.keymaster@4.0-service.trustkernel.rc" \
        "$MNT/etc/init/android.hardware.keymaster@4.0-service.trustkernel.rc.disabled"
sudo cp "$KM/android.hardware.keymaster@3.0-service"        "$MNT/bin/hw/"
sudo cp "$KM/lib64/hw/android.hardware.keymaster@3.0-impl.so" "$MNT/lib64/hw/"
sudo cp "$KM"/lib64/*.so                                     "$MNT/lib64/"
sudo tee "$MNT/etc/init/android.hardware.keymaster@3.0-service.rc" >/dev/null <<'RC'
service vendor.keymaster-3-0 /vendor/bin/hw/android.hardware.keymaster@3.0-service
    class early_hal
    user system
    group system drmrpc
RC
sudo chown root:2000 "$MNT/bin/hw/android.hardware.keymaster@3.0-service"
sudo chmod 755      "$MNT/bin/hw/android.hardware.keymaster@3.0-service"

echo ">>> (b) VINTF manifest: keymaster 4.0 -> 3.0"
sudo python3 - "$MNT/etc/vintf/manifest.xml" <<'PY'
import sys
p = sys.argv[1]; x = open(p).read()
old = """<name>android.hardware.keymaster</name>
        <transport>hwbinder</transport>
        <version>4.0</version>"""
if old not in x:
    raise SystemExit("keymaster 4.0 entry not found in manifest - already patched?")
x = x.replace(old, old.replace("<version>4.0</version>", "<version>3.0</version>"))
x = x.replace("@4.0::IKeymasterDevice/default", "@3.0::IKeymasterDevice/default")
open(p, "w").write(x); print("    manifest updated")
PY

echo ">>> (c) removing file-based encryption from fstabs"
for f in "$MNT/etc/fstab.mt6762" "$MNT/etc/fstab.mt6765"; do
  sudo sed -i 's/,fileencryption=aes-256-xts//' "$f"
done

echo ">>> (e) build.prop properties"
grep -q "disabled_commands" "$MNT/build.prop" 2>/dev/null || sudo tee -a "$MNT/build.prop" >/dev/null <<'PROP'

# The MTK Bluetooth firmware advertises HCI Read/Write Default Erroneous Data
# Reporting (0x0C5A/0x0C5B) but does not implement them; the Android 14 stack
# asserts on the reply and com.android.bluetooth crash-loops.
bluetooth.hci.disabled_commands=182,183

# The Android 10 audio HAL needs ~47 ms per write against the mixer's 5.33 ms
# period, so the audio path glitches while warming up. Default standby is 3 s,
# which makes every widely-spaced navigation prompt restart from cold.
ro.audio.flinger_standbytime_ms=20000
PROP

echo ">>> (d) restoring SELinux labels - sed -i destroys them, and an unlabeled"
echo "        fstab breaks nvram_daemon -> no modem and no Bluetooth, silently"
for f in "$MNT/etc/fstab.mt6762" "$MNT/etc/fstab.mt6765" \
         "$MNT/etc/init/android.hardware.keymaster@3.0-service.rc"; do
  sudo setfattr -n security.selinux -v "u:object_r:vendor_configs_file:s0" "$f"
done
sudo setfattr -n security.selinux -v "u:object_r:hal_keymaster_default_exec:s0" \
     "$MNT/bin/hw/android.hardware.keymaster@3.0-service"
for f in "$MNT"/lib64/*keymaster*.so "$MNT/lib64/hw/android.hardware.keymaster@3.0-impl.so"; do
  sudo setfattr -n security.selinux -v "u:object_r:vendor_file:s0" "$f"
done
sudo setfattr -n security.selinux -v "u:object_r:vendor_file:s0" "$MNT/build.prop"

echo ">>> verification"
for f in "$MNT/etc/fstab.mt6765" "$MNT/bin/hw/android.hardware.keymaster@3.0-service" "$MNT/build.prop"; do
  printf '    %-70s %s\n' "${f#$MNT}" \
    "$(sudo getfattr -n security.selinux --only-values "$f" 2>/dev/null)"
done
sudo grep -c fileencryption "$MNT/etc/fstab.mt6765" | xargs -I{} echo "    fileencryption occurrences left: {} (must be 0)"

sync; sudo umount "$MNT"; trap - EXIT
e2fsck -fn "$DST" 2>&1 | tail -1
echo ">>> $DST ready ($(du -h "$DST" | cut -f1))"
