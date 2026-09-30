# LineageOS 21 (Android 14) on the Doogee S58 Pro

The Doogee S58 Pro shipped with Android 10 and was abandoned by the vendor in February 2022
(`DOOGEE-S58Pro-Android10.0-20220221`, security patch level **2022-01-05**). No official update
will ever arrive. This repository documents a **working path to Android 14 with current security
patches** using a Project Treble GSI.

This is not a "flash a GSI and you're done" device. Three device-specific problems have to be
solved first, and I could not find any of them documented elsewhere. All three are solved here,
with the scripts in [`scripts/`](scripts/).

> **Device:** Doogee S58 Pro (EEA variant) · MediaTek MT6762 / Helio P22 · 6 GB RAM · 64 GB
> · vendor Android 10 (VNDK 29) · A-only with dynamic partitions (`super`)

Verified end to end on one physical unit in September 2026.

> **Who wrote this.** The diagnosis, the patched images, the scripts and this guide were
> produced by **Claude**, Anthropic's AI assistant (models Claude Opus 5 and Claude Fable
> 5.1, running in Claude Code), working on the device over several sessions in September
> 2026. The device owner ([anerdev](https://github.com/anerdev)) provided the hardware,
> performed the physical steps (BROM key combinations, cabling) and made the calls on
> what to accept or reject. Everything else — reading the kernel logs, identifying the
> TEE problem, building the patched vendor, writing these scripts — was done by Claude.
> Details, including **what was not tested**, in [About this documentation](#about-this-documentation).

---

## Contents

1. [Result](#1-result)
2. [Read this first](#2-read-this-first)
3. [Prerequisites](#3-prerequisites)
4. [Step 1 — Full backup](#4-step-1--full-backup-do-not-skip)
5. [Step 2 — Unlock the bootloader](#5-step-2--unlock-the-bootloader)
6. [Step 3 — Patch the boot image](#6-step-3--patch-the-boot-image)
7. [Step 4 — Patch the vendor image](#7-step-4--patch-the-vendor-image)
8. [Step 5 — Flash](#8-step-5--flash)
9. [Step 6 — Post-install](#9-step-6--post-install)
10. [Known issues](#10-known-issues-cosmetic-or-unavoidable)
11. [Restoring stock](#11-restoring-stock)
12. [Debugging a device that will not boot](#12-debugging-a-device-that-will-not-boot)

---

## 1. Result

| Component | Status |
|---|---|
| Boot, UI, Play Store, Play Services | Working |
| Wi-Fi, Bluetooth, NFC | Working |
| Mobile data, dual SIM, LTE, VoLTE registration | Working |
| GNSS | Working — 24 satellites, 2.1 m accuracy, multi-constellation (GPS + GLONASS + Galileo) |
| Camera | Working — 3 sensors detected, 15.9 MP stills (3456×4608) via LineageOS Aperture |
| Sensors | Accelerometer, magnetometer, light, proximity, orientation (no gyroscope in this hardware) |
| Deep sleep | Working |
| Face unlock | **Lost** — vendor app, Android 10 only |
| Play Integrity / SafetyNet | **Fails** — Google Wallet, banking apps and DRM HD video will not work |
| Hardware-backed keystore | **Lost** — see [security](#the-tee-is-the-whole-problem) |

Free memory at idle improved over stock: **4.5 GB vs 3.7 GB**, with no swap in use (stock was
already 742 MB into swap right after boot), mostly because the GSI does not carry Doogee's
preinstalled software.

---

## 2. Read this first

### The TEE is the whole problem

This device uses a **TrustKernel** TEE. With the bootloader unlocked, the TEE refuses to serve
keymaster and gatekeeper, logging `TrustKernel OS running on un-verified devices`. The consequence
is not cosmetic: `keystore2` never finishes starting — it loops forever negotiating a shared HMAC
secret — and **the device hangs on the boot animation indefinitely**. Every GSI will do this until
keymaster and gatekeeper are replaced with software implementations, which is what
[step 4](#7-step-4--patch-the-vendor-image) does.

After this procedure:

- cryptographic keys live in software, not in the TEE — malware with root could extract them;
- **`/data` is not encrypted** (file-based encryption requires a working keymaster);
- the screen lock is verified in software, so brute-force rate limiting is weaker.

If any of that is unacceptable to you, stop here and stay on Android 10.

### Re-locking the bootloader will brick the phone

Once LineageOS is installed, `fastboot flashing lock` leaves a device that **refuses to boot** —
verified boot rejects a system not signed by Doogee. Recovery requires restoring the complete
stock firmware from your backup. Do not do it. The orange "your device has been unlocked" splash
stays forever; that is the price of admission.

### Everything is wiped

Unlocking the bootloader erases `/data`.

---

## 3. Prerequisites

A **Linux** machine (this was done on Ubuntu 26.04; Windows is not covered):

```bash
sudo apt install adb fastboot android-sdk-libsparse-utils attr python3-venv git rsync
git clone https://github.com/bkerler/mtkclient
python3 -m venv venv
venv/bin/pip install -r mtkclient/requirements.txt
sudo cp mtkclient/Setup/Linux/*.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Downloads:

| What | Where |
|---|---|
| **GSI** `lineage-21.0-<date>-UNOFFICIAL-gsi_arm64_gN-signed.img` | [AndyYan builds](https://sourceforge.net/projects/andyyan-gsi/files/lineage-21-pre-qpr2-light/) |
| **vbmeta** with verification disabled | `https://dl.google.com/developers/android/qt/images/gsi/vbmeta.img` |
| **Android 10 arm64 emulator image** (source of the software keymaster) | `https://dl.google.com/android/repository/sys-img/android/arm64-v8a-29_r08.zip` |

**Why this specific GSI branch.** Use `lineage-21-pre-qpr2`. Its maintainer keeps that branch
alive precisely because Android 14 QPR2 and later removed support for several legacy HALs, which
breaks devices with old vendor blobs — exactly our case. The `gN` variant includes Google Apps;
`vN` is vanilla. Android 15/16 GSIs are a gamble on this hardware; the GNSS HAL in particular is
the component most likely to stop working.

**Entering BROM mode** (needed by mtkclient): power the phone off, unplug it, hold **Volume Up +
Volume Down**, plug the USB cable in and keep holding ~5 seconds. The screen stays black — that is
correct. Nothing is ever truly lost here: BROM lives in mask ROM and answers even when the device
will not boot, which makes every step below recoverable.

---

## 4. Step 1 — Full backup (do not skip)

```bash
scripts/01-backup-stock.sh          # phone in BROM mode
```

Produces ~5.4 GB of images: `super.bin`, `boot.bin`, `vbmeta*.bin`, `lk.bin`, `tee*.bin` and — most
importantly — `nvram.bin`, `nvdata.bin`, `proinfo.bin`, which hold your **IMEI, Wi-Fi/Bluetooth MAC
addresses and RF calibration**. Losing those is the one genuinely unrecoverable mistake available
in this procedure. Keep a copy on another machine.

---

## 5. Step 2 — Unlock the bootloader

Enable *Developer options* → **OEM unlocking** and **USB debugging**, then:

```bash
adb reboot bootloader
fastboot flashing unlock        # confirm on the phone with Volume Up
fastboot getvar unlocked        # must print: unlocked: yes
```

---

## 6. Step 3 — Patch the boot image

The GSI system image is ~3.5 GB; `super` is 4 GB, of which stock `product` takes 1.7 GB. `product`
has to go — but the **first-stage fstab inside the boot ramdisk** lists it as a mandatory mount, so
deleting the partition alone produces a boot failure.

```bash
scripts/02-patch-boot-ramdisk.py backup/boot.bin boot_noproduct.img
sudo ../venv/bin/python mtk.py w boot boot_noproduct.img     # phone in BROM mode
```

The script strips the `product` line from both fstab files in the ramdisk and repacks, preserving
kernel, DTB and every other section byte for byte. Note this is a **boot header v2** image: the
DTB size lives at offset `0x670`, *after* `header_size`. Reading it from the wrong offset silently
truncates the device tree and the phone will not boot — the script asserts on this.

---

## 7. Step 4 — Patch the vendor image

This is the part that makes the device bootable at all. Five changes:

| # | Change | Why |
|---|---|---|
| a | Gatekeeper → `libSoftGatekeeper.so` (already in the vendor) | TEE gatekeeper refuses to serve |
| b | Keymaster TrustKernel → **AOSP software keymaster 3.0** + VINTF manifest 4.0→3.0 | otherwise `keystore2` hangs and the device never boots |
| c | Remove `fileencryption` from both fstabs | software keymaster cannot serve FBE |
| d | **Restore SELinux labels** on every file touched | see the warning below |
| e | Two properties in `build.prop` | Bluetooth and audio fixes |

```bash
scripts/03-extract-logical-partition.py backup/super.bin vendor vendor_stock.img
scripts/04-fetch-software-keymaster.sh          # downloads + extracts the emulator image
scripts/05-build-patched-vendor.sh vendor_stock.img vendor_mod.img
```

> ### ⚠️ The trap that cost me hours
> `sed -i` **rewrites the file and destroys its `security.selinux` xattr.** An unlabeled
> `fstab.mt6762` makes `nvram_daemon` fail → `vendor.service.nvram_init` is never set → the modem
> and the Bluetooth HAL wait forever. The symptom is *no mobile network and no Bluetooth*, with no
> error message pointing at the cause. Always `setfattr -n security.selinux -v
> u:object_r:vendor_configs_file:s0` (or `restorecon` on the running device) after editing
> anything under `/vendor`. Script `05` does this for you; verify with
> `getfattr -n security.selinux --absolute-names <file>` before unmounting.

The two properties, and the reasoning behind them:

```properties
# The MTK Bluetooth firmware advertises HCI Read/Write Default Erroneous Data
# Reporting (0x0C5A/0x0C5B) but does not implement them. The Android 14 stack
# asserts on the malformed command-complete event and com.android.bluetooth
# crashes in a loop, so Bluetooth can never be turned on.
bluetooth.hci.disabled_commands=182,183

# The Android 10 audio HAL needs ~47 ms per write against the mixer's 5.33 ms
# period (88 underruns observed, plus 455 pcm_get_htimestamp failures), so the
# audio path is slow to warm up and glitches on the first sound. Default standby
# is 3 s, which means every widely-spaced navigation prompt restarts from cold.
ro.audio.flinger_standbytime_ms=20000
```

---

## 8. Step 5 — Flash

`fastbootd` (userspace fastboot) is required to touch logical partitions. If `fastboot flash
system` reports *"This partition doesn't exist"*, you are in bootloader fastboot, not fastbootd.

```bash
scripts/06-flash-lineage.sh vendor_mod.img lineage-21.0-<date>-...-gN-signed.img vbmeta.img
```

or manually:

```bash
fastboot --disable-verification --disable-verity flash vbmeta vbmeta.img
fastboot reboot fastboot
fastboot getvar is-userspace            # must print: is-userspace: yes
fastboot delete-logical-partition product
fastboot flash vendor vendor_mod.img
fastboot flash system lineage-21.0-<date>-UNOFFICIAL-gsi_arm64_gN-signed.img
fastboot reboot
```

First boot lands in recovery asking to wipe — `enablefilecrypto_failed` is expected, since `/data`
is still encrypted from stock. Choose **Factory data reset**, then **Reboot system now**. First
boot takes 3–5 minutes.

If you get stuck and cannot reach fastbootd from the UI, `scripts/98-set-fastbootd-bcb.py` writes
the boot command block in the `misc`/`para` partition over BROM, so the next boot lands in
fastbootd.

---

## 9. Step 6 — Post-install

### Register the device with Google (required)

Without this, the Play Store eventually replaces every app page with *"This device isn't Play
Protect certified — your device isn't certified to run Google apps or use Google services"* and
a single **Close** button: nothing can be installed. On the test unit the Play Store worked for
about a week after installation and then started blocking; the notification alone had been
there from day one. Registering with Google's own page for custom ROMs lifts the block.

Read the Google Services Framework Android ID (needs `adb root`, available on this userdebug
build):

```bash
adb root
```
```bash
adb shell sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select value from main where name='android_id';"
```

Open **https://www.google.com/android/uncertified/** in any browser, sign in with **the same
Google account used on the phone**, paste the number, solve the captcha, press **Register**.

Registering alone did not lift the block on the test unit: Play Store and Play Services cache
the failed check. Clear the data of both, then reboot:

```bash
adb shell am force-stop com.android.vending
```
```bash
adb shell am force-stop com.google.android.gms
```
```bash
adb shell pm clear com.android.vending
```
```bash
adb shell pm clear com.google.android.gms
```
```bash
adb reboot
```

Clearing only the caches, or only the Play Store data, was **not** enough — both data sets had
to go. Your Google account stays signed in; Play Services forgets some local preferences (you
may be asked again about location accuracy).

> **Do not clear the data of Google Services Framework (`com.google.android.gsf`).** That is
> where the Android ID lives: clearing it generates a new ID and silently voids the
> registration you just made.

### Optional tuning

```bash
scripts/07-post-install-tweaks.sh        # all optional, see the script for what each line does
```

The **Treble settings** panel (first entry in Settings) carries phh's GSI workarounds. On this
device the relevant ones are:

- **Disable A2DP offload** — first thing to try if Bluetooth audio stutters;
- *Use alternative audio policy*, *Disable soundvolume effect* — further audio levers (the second
  may reduce maximum loudness);
- *Disable SF HWC backpressure* — may improve UI smoothness.

None of these were needed on the test unit, so none are applied by default.

---

## 10. Known issues (cosmetic or unavoidable)

**"This device isn't Play Protect certified" notification, repeatedly.** A consequence of the
unlocked bootloader. If the Play Store *also* refuses to install apps, that is not cosmetic —
see [Register the device with Google](#register-the-device-with-google-required). The
notification alone can be silenced by turning off just that channel: Settings → Apps → Google
Play Services → Notifications → **Play Protect** (internal id `uncertified_device`). Other Play
Protect warnings keep working. Note that registration fixes the Play Store, not Play Integrity:
banking apps and Google Wallet still refuse to run.

**Play Services throws `SecurityException: Permission denial to mutate flag` in bursts.** Its
`PlatformConfigurator` lacks `WRITE_DEVICE_CONFIG` because GMS runs from `/data/app` rather than as
a privileged app. About 7,000 exceptions in 10 hours, confined to ~180 seconds in total. Harmless;
`pm grant` cannot fix it (signature permission), and moving GMS to `/system/priv-app` would break
Play Store updates.

**A SIM shows "unknown" as phone number.** Only if the number is not written to the UICC itself.
Writing `number`, `phone_number_source_carrier` and `phone_number_source_ims` into the `siminfo`
table does **not** help: the UI only trusts the value read from the SIM or one set by a
carrier-privileged app. Behaves identically on stock. Workaround: rename the SIM to include the
number.

**`load average` around 22 while the CPU is ~90% idle.** Normal here: 23 MediaTek kernel threads
(`mdrt_thread`, `ccci_*`, `battery_thread`, `disp_check`…) sit permanently in uninterruptible
sleep and Linux counts them in the load figure. Not a performance problem.

**Battery gauge reports 2,946 mAh against 5,180 mAh advertised.** That value comes from the gauge
profile in the stock kernel device tree, so it reads the same on stock. Not caused by the GSI.

**Two log floods**, silenced by `scripts/07`: `ADSC` (dual-SIM auto data switch controller,
12,147 × "Unexpected event 4" in 10 hours) and `WifiStaIfaceHidlImpl` (Android 14 asking for
link-layer stats the Android 10 Wi-Fi HAL does not expose). Both harmless, both pure noise.

---

## 11. Restoring stock

```bash
scripts/99-restore-stock.sh backup/       # phone in BROM mode
```

`super`, `boot`, `vbmeta`, `nvram`, `nvdata` and `proinfo` are the ones that matter. Only after
**every** stock partition is restored is `fastboot flashing lock` safe again.

---

## 12. Debugging a device that will not boot

With no adb and a black screen you are not blind — MediaTek keeps a kernel log in the `expdb`
partition, readable over BROM:

```bash
sudo ../venv/bin/python mtk.py r expdb expdb.bin
strings expdb.bin | grep -E "init:|libfs_mgr|Restarting system|avc:  denied"
```

That is how the keystore hang was found: `keystore2` retrying
`shared_secret_negotiation … Error::Km(HARDWARE_TYPE_UNAVAILABLE)` forever, while the TEE logged
`TrustKernel OS running on un-verified devices`.

For a device that boots but misbehaves before adb comes up, flash a temporary copy of the GSI
carrying an init service that periodically dumps `getprop`, `ps`, `dmesg` and `logcat` into the
unused `cache` partition, then read `cache` back over BROM. Remember to reflash the pristine signed
system image afterwards.

---

## About this documentation

**This guide and every script in it were written by Claude** (Anthropic's AI assistant),
using models **Claude Opus 5** and **Claude Fable 5.1** in Claude Code, while performing
this installation on a real Doogee S58 Pro across several sessions in September 2026.

The division of labour was:

| Done by Claude | Done by the device owner |
|---|---|
| Reading the kernel log out of `expdb` over BROM and diagnosing the TEE/keymaster hang | Owning the phone and accepting the risk |
| Extracting the software keymaster from Google's emulator image and building the patched vendor | Pressing the BROM key combination, plugging cables |
| Repacking the boot ramdisk, finding the header-v2 DTB offset bug | Deciding what was acceptable (security trade-offs, what to remove) |
| Diagnosing the Bluetooth HCI crash loop and the SELinux label breakage | Field-testing GPS, audio and daily use |
| Writing these scripts and this documentation | Publishing it |

What that means for you, so you can judge the material:

- Every command, property value, log excerpt and measurement here was taken from that
  session on real hardware — nothing is quoted from memory or copied from other guides.
- The TEE/keymaster diagnosis came from the kernel log in the `expdb` partition and from
  a temporary instrumented build that dumped state into the `cache` partition. It is not
  a guess.
- Items marked as untested are genuinely untested. On the test unit, **voice calls, the
  microphone during a call, and Bluetooth audio to a headset were never verified.**
- The procedure was carried out on **one** device. A different unit, regional variant or
  stock build may behave differently.
- An AI wrote this, so read it critically: check the `para` offset in script `98` against
  your own GPT, and keep the backup from step 1 within reach at all times.

Corrections and reports from other units are welcome — open an issue.

## Credits

- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/) — the LineageOS GSI builds
- [bkerler/mtkclient](https://github.com/bkerler/mtkclient) — MediaTek BROM tooling; the whole
  procedure is recoverable because of it
- [phhusson](https://github.com/phhusson/treble_experimentations) and the TrebleDroid project —
  the GSI patches everything else builds on

## License

[MIT](LICENSE) © 2026 anerdev — use it, change it, sell it if you want; just keep
the copyright line. No warranty of any kind: flashing firmware can brick a device, and
you do it at your own risk.
