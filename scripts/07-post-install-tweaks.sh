#!/usr/bin/env bash
# Optional post-install tweaks. Nothing here is required for the phone to work.
# Read each block and comment out what you do not want.
set -euo pipefail
adb wait-for-device

echo ">>> Silencing two log floods specific to this hardware"
# ADSC: dual-SIM Auto Data Switch Controller in com.android.phone, logs
#       "Unexpected event 4" ~20x/minute (12,147 times in 10 hours here).
# WifiStaIfaceHidlImpl: Android 14 asks for link-layer stats that the Android 10
#       Wi-Fi HAL does not implement -> ERROR_NOT_SUPPORTED on every poll.
adb shell setprop persist.log.tag.ADSC S
adb shell setprop persist.log.tag.WifiStaIfaceHidlImpl S

echo ">>> Exempting navigation apps from Doze so they survive in the background"
adb shell cmd deviceidle whitelist +com.google.android.apps.maps +net.osmand || true

echo ">>> Disabling Perfetto tracing daemons (system diagnostics, not needed here)"
adb shell setprop persist.traced.enable 0

echo ">>> Turning off always-on Wi-Fi/BLE scanning (position via GPS instead)"
adb shell settings put global wifi_scan_always_enabled 0
adb shell settings put global ble_scan_always_enabled 0

echo ">>> Pre-compiling all apps now instead of waiting for the nightly job"
adb shell cmd package bg-dexopt-job || true

# --- purely a matter of taste, uncomment what you like -----------------------
# adb shell settings put global window_animation_scale 0
# adb shell settings put global transition_animation_scale 0
# adb shell settings put global animator_duration_scale 0
# adb shell settings put system sound_effects_enabled 0
# adb shell settings put system screen_off_timeout 2147483647   # never sleep
# adb shell settings put secure doze_always_on 0                # no always-on display

# --- de-bloat: remove Google apps for the current user (reversible with
# --- `adb shell cmd package install-existing <pkg>`). Keep TTS if you use
# --- spoken navigation, and never remove gms/vending/gsf.
# for p in com.google.android.googlequicksearchbox com.google.android.projection.gearhead \
#          com.google.android.apps.wellbeing com.google.android.marvin.talkback \
#          com.google.android.feedback com.google.android.partnersetup \
#          com.google.android.apps.restore com.google.android.verifier \
#          com.google.android.safetycore com.google.android.markup \
#          com.google.android.gm.exchange com.android.DeviceAsWebcam; do
#   adb shell pm uninstall --user 0 "$p" || true
# done

echo ">>> Done."
