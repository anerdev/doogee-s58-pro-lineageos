#!/usr/bin/env bash
# Flash the patched vendor + LineageOS GSI through fastbootd.
#
# usage: ./06-flash-lineage.sh <vendor_mod.img> <lineage-gsi.img> [vbmeta.img]
#
# Requires an unlocked bootloader. Wipes /data on first boot.
set -euo pipefail

VENDOR="${1:?usage: $0 <vendor_mod.img> <lineage-gsi.img> [vbmeta.img]}"
SYSTEM="${2:?usage: $0 <vendor_mod.img> <lineage-gsi.img> [vbmeta.img]}"
VBMETA="${3:-vbmeta.img}"

for f in "$VENDOR" "$SYSTEM"; do
  if [ ! -f "$f" ]; then
    echo "missing: $f"
    exit 1
  fi
done

echo ">>> Waiting for fastboot..."
if ! fastboot getvar unlocked 2>&1 | grep -q "unlocked: yes"; then
  echo "Bootloader is NOT unlocked. Run: fastboot flashing unlock"
  exit 1
fi

if [ -f "$VBMETA" ]; then
  echo ">>> Flashing vbmeta with verification disabled"
  fastboot --disable-verification --disable-verity flash vbmeta "$VBMETA"
fi

echo ">>> Rebooting into fastbootd (userspace fastboot)"
fastboot reboot fastboot
for _ in $(seq 1 30); do
  if fastboot getvar is-userspace 2>&1 | grep -q "is-userspace: yes"; then
    break
  fi
  sleep 3
done

if ! fastboot getvar is-userspace 2>&1 | grep -q "is-userspace: yes"; then
  echo "Not in fastbootd. Logical partitions cannot be flashed from bootloader fastboot."
  exit 1
fi

echo ">>> Deleting 'product' to free space in super (stock product is ~1.7 GB)"
fastboot delete-logical-partition product || true

echo ">>> Flashing vendor"
fastboot flash vendor "$VENDOR"

echo ">>> Flashing system (several minutes)"
fastboot flash system "$SYSTEM"
fastboot reboot

cat <<'NOTE'

>>> Done. The first boot lands in recovery asking to wipe:
      "Can't load Android system" / enablefilecrypto_failed
    This is expected: /data is still encrypted from stock while the new vendor
    has file-based encryption disabled.

    Choose "Factory data reset", then "Reboot system now".
    First boot then takes 3-5 minutes.
NOTE
