# Changelog

## 2026-09-21 — first working installation

- LineageOS 21 (`lineage-21.0-20260916-UNOFFICIAL-gsi_arm64_gN-signed`) booting on a
  Doogee S58 Pro EEA, Android 14 with September 2026 security patches.
- Solved: mandatory `product` mount in the first-stage fstab (boot ramdisk repacked).
- Solved: TrustKernel TEE refusing keymaster/gatekeeper with an unlocked bootloader,
  which hung `keystore2` and left the device on the boot animation forever — replaced
  with AOSP software keymaster 3.0 and `libSoftGatekeeper`.
- Solved: `com.android.bluetooth` crash loop caused by two HCI commands the MediaTek
  firmware advertises but does not implement (`bluetooth.hci.disabled_commands=182,183`).
- Solved: SELinux labels destroyed by `sed -i` on vendor fstabs, which silently broke
  `nvram_daemon`, the modem and the Bluetooth HAL.
- Verified on hardware: GNSS (24 satellites, 2.1 m, multi-constellation), camera
  (15.9 MP), NFC, Wi-Fi, dual-SIM LTE, sensors, deep sleep.

## 2026-09-21 — tuning

- `ro.audio.flinger_standbytime_ms=20000` to stop the audio path from cooling down
  between navigation prompts (the Android 10 HAL takes ~47 ms per write against a
  5.33 ms mixer period; 88 underruns observed).
- Silenced two log floods: `ADSC` (12,147 lines in 10 h) and `WifiStaIfaceHidlImpl`.

## 2026-09-23

- Documented how to silence the "device isn't Play Protect certified" notification
  (channel `uncertified_device`) instead of the dangerous "just re-lock the bootloader"
  advice found elsewhere.

## 2026-09-30

- About a week after installation the Play Store started blocking every install with a
  full-screen "This device isn't Play Protect certified" page (only a *Close* button).
  Fixed by registering the GSF Android ID at google.com/android/uncertified, then clearing
  the data of **both** Play Store and Play Services and rebooting. Registration alone,
  cache-only clearing, or clearing Play Store data alone were each tested and were not
  enough. Documented as a required post-install step.
