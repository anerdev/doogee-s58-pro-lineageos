#!/usr/bin/env python3
"""
Force the next boot into fastbootd by writing the Bootloader Control Block (BCB)
directly into the misc/para partition over MediaTek BROM.

When to use this: the device is stuck (boot loop, recovery you cannot navigate, black
screen) and you cannot reach fastbootd from the UI. Since BROM answers even on a device
that will not boot, this always works.

    usage: sudo venv/bin/python 98-set-fastbootd-bcb.py [--wipe-cache]
           (phone in BROM mode: power off -> hold Vol Up + Vol Down -> plug USB)

The BCB is a simple structure at the start of the 'para' partition:
    offset  0   command[32]   "boot-recovery"
    offset 64   recovery[768] "recovery\n<args...>"
Writing "--fastboot" as an argument makes recovery hand control to fastbootd.

PARA_OFFSET below is the byte offset of 'para' on THIS device's eMMC (from the GPT:
`mtk.py printgpt`). Check it against your own dump before running - writing the BCB to
the wrong offset would corrupt another partition.
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/firmware-doogee/mtkclient"))
os.chdir(os.path.expanduser("~/firmware-doogee/mtkclient"))
from mtk_api import init, connect   # noqa: E402

PARA_OFFSET = 0x2108000       # Doogee S58 Pro - verify with `mtk.py printgpt`
CACHE_OFFSET = 0x124000000
BLOCK = 4096


def main() -> None:
    mtk = init(preloader=None, loader=None)
    mtk, handler = connect(mtk=mtk, directory=".")
    if mtk is None:
        raise SystemExit("could not connect - is the phone in BROM mode?")

    def read(addr, length):
        return handler.da_rs(start=addr // 512, sectors=length // 512,
                             filename="", parttype="user", display=False)

    def write(addr, data):
        return mtk.daloader.writeflash(addr=addr, length=len(data), filename="",
                                       offset=0, parttype="user", wdata=data, display=False)

    para = read(PARA_OFFSET, BLOCK)
    print("para currently starts with:", bytes(para[:16]))

    bcb = bytearray(2048)
    bcb[0:14] = b"boot-recovery\0"
    args = b"recovery\n--fastboot\n"
    bcb[64:64 + len(args)] = args
    new = bytes(bcb) + bytes(para[2048:])

    print("writing BCB (boot-recovery / --fastboot):", write(PARA_OFFSET, new))
    print("read back:", "OK" if read(PARA_OFFSET, BLOCK) == new else "MISMATCH")

    if "--wipe-cache" in sys.argv:
        print("zeroing the first MB of cache:", write(CACHE_OFFSET, b"\0" * (1 << 20)))

    try:
        mtk.daloader.shutdown(bootmode=0)
    except Exception as exc:                                  # noqa: BLE001
        print("reset:", exc)
    print("Unplug, then press Power. The device should come up in fastbootd.")


if __name__ == "__main__":
    main()
