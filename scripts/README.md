# Scripts

Run them in order. Every script prints what it is doing and stops on the first error.

| Script | Purpose | Device state |
|---|---|---|
| `01-backup-stock.sh` | Full stock backup (~5.4 GB). **Do not skip.** | BROM |
| `02-patch-boot-ramdisk.py` | Removes the mandatory `product` mount from the boot ramdisk fstab | offline (file) |
| `03-extract-logical-partition.py` | Pulls `system`/`vendor`/`product` out of a `super` dump | offline (file) |
| `04-fetch-software-keymaster.sh` | Downloads Google's Android 10 emulator image and extracts a software keymaster 3.0 | offline (file) |
| `05-build-patched-vendor.sh` | Builds the patched vendor: software keymaster + gatekeeper, no FBE, SELinux labels, properties | offline (file) |
| `06-flash-lineage.sh` | Flashes vbmeta, vendor and the GSI through fastbootd | fastboot |
| `07-post-install-tweaks.sh` | Optional tuning (log noise, Doze whitelist, de-bloat) | booted, adb |
| `98-set-fastbootd-bcb.py` | Emergency: force the next boot into fastbootd via the BCB | BROM |
| `99-restore-stock.sh` | Puts the stock firmware back | BROM |

## Typical run

```bash
# layout assumed by the defaults:
#   ./mtkclient/        git clone of bkerler/mtkclient
#   ./venv/             python venv with mtkclient's requirements
#   ./backup/           created by script 01
export MTK_DIR="$PWD/mtkclient" PYTHON="$PWD/venv/bin/python"

scripts/01-backup-stock.sh backup

adb reboot bootloader && fastboot flashing unlock      # confirm on the phone

scripts/02-patch-boot-ramdisk.py backup/boot.bin boot_noproduct.img
( cd mtkclient && sudo "$PYTHON" mtk.py w boot ../boot_noproduct.img )   # phone in BROM

scripts/03-extract-logical-partition.py backup/super.bin vendor vendor_stock.img
scripts/04-fetch-software-keymaster.sh
scripts/05-build-patched-vendor.sh vendor_stock.img vendor_mod.img

scripts/06-flash-lineage.sh vendor_mod.img lineage-21.0-*-gN-signed.img vbmeta.img
# -> first boot: Factory data reset, then Reboot system now

scripts/07-post-install-tweaks.sh
```

## Notes

- `02` and `03` only read and write files; they never touch the device, so they are safe
  to experiment with.
- `05` needs `sudo` to mount the image and to set SELinux xattrs (`attr` package).
- `98` has the `para` partition offset hardcoded for the Doogee S58 Pro. **Check it against
  your own `mtk.py printgpt` before running it**, since writing to the wrong offset would
  corrupt a different partition.
- `01` and `99` shell out to mtkclient; set `MTK_DIR` and `PYTHON` if your layout differs.
