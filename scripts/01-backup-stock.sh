#!/usr/bin/env bash
# Full stock firmware backup of a Doogee S58 Pro over MediaTek BROM.
#
# THIS IS YOUR ONLY WAY BACK. Do not skip it, and keep a copy on a second machine.
# Dumps every partition except userdata (~5.4 GB, ~10 minutes), including nvram /
# nvdata / proinfo which hold IMEI, MAC addresses and RF calibration.
#
# Put the phone in BROM mode first:
#   power off -> unplug -> hold Volume Up + Volume Down -> plug USB -> keep holding ~5 s
# The screen stays black. That is correct.
set -euo pipefail

MTK_DIR="${MTK_DIR:-$PWD/mtkclient}"
PYTHON="${PYTHON:-$PWD/venv/bin/python}"
OUT="${1:-backup}"

[ -d "$MTK_DIR" ] || { echo "mtkclient not found at $MTK_DIR (set MTK_DIR)"; exit 1; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

echo ">>> Waiting for the phone in BROM mode..."
( cd "$MTK_DIR" && sudo "$PYTHON" mtk.py rl "$OUT" --skip userdata )

cd "$OUT"
sudo chown "$(id -u):$(id -g)" ./* 2>/dev/null || true
sha256sum ./*.bin > SHA256SUMS
echo
echo ">>> Backup complete: $(du -sh "$OUT" | cut -f1) in $OUT"
echo ">>> Critical files: nvram.bin nvdata.bin proinfo.bin super.bin boot.bin vbmeta.bin"
echo ">>> Copy this directory somewhere safe NOW."
