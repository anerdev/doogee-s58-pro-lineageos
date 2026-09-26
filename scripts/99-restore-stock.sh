#!/usr/bin/env bash
# Restore the stock firmware from a backup made by 01-backup-stock.sh.
# Phone must be in BROM mode (power off -> hold Vol Up + Vol Down -> plug USB).
#
# Only after EVERY stock partition is back is `fastboot flashing lock` safe again.
# Re-locking with a GSI still installed leaves an unbootable device.
set -euo pipefail

MTK_DIR="${MTK_DIR:-$PWD/mtkclient}"
PYTHON="${PYTHON:-$PWD/venv/bin/python}"
BACKUP="${1:?usage: $0 <backup-dir>}"
BACKUP="$(realpath "$BACKUP")"

if [ ! -f "$BACKUP/super.bin" ]; then
  echo "super.bin not found in $BACKUP"
  exit 1
fi

if [ -f "$BACKUP/SHA256SUMS" ]; then
  echo ">>> Verifying backup integrity..."
  cd "$BACKUP"
  if ! sha256sum -c SHA256SUMS --quiet; then
    echo "CHECKSUM MISMATCH - aborting"
    exit 1
  fi
  cd - >/dev/null
fi

echo ">>> Restoring all partitions from $BACKUP (this takes a while)"
read -rp "Type RESTORE to continue: " c
if [ "$c" != RESTORE ]; then
  exit 1
fi

cd "$MTK_DIR"
sudo "$PYTHON" mtk.py wl "$BACKUP"
echo ">>> Done. Boot the phone and verify IMEI (*#06#) and mobile network before re-locking."
