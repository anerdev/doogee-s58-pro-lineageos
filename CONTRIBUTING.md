# Contributing

This was produced on a single Doogee S58 Pro (EEA variant, stock build
`DOOGEE-S58Pro-Android10.0-20220221`). Reports from other units are the most valuable
contribution, especially:

- **other regional variants** (non-EEA) or a different stock build number;
- the **Doogee S58** (non-Pro), which shares the MT6762 platform but has not been tested;
- results with **newer GSIs** (LineageOS 22/23, crDroid, Android 15/16) — in particular
  whether the GNSS HAL and telephony survive, which is the usual breaking point on this
  old vendor blob;
- anything that fails at a different point than described here.

When opening an issue, please include:

```
adb shell getprop ro.build.fingerprint
adb shell getprop ro.vndk.version
adb shell getprop ro.lineage.version
```

and, if the device does not boot, the interesting part of the kernel log pulled over
BROM:

```
sudo venv/bin/python mtk.py r expdb expdb.bin
strings expdb.bin | grep -E "init:|libfs_mgr|Restarting system|avc:  denied" | tail -50
```

Corrections to the documentation are welcome as pull requests. If something here is
wrong, saying so plainly is more useful than being polite about it.
