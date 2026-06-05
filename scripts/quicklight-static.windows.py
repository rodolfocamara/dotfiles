"""Set ROBOBLOQ / DX-LIGHT Quiklight USB strips to a static color and exit.

Protocol partially reverse-engineered from https://github.com/shim80/hypr-quicklight.
Uses the "set section color" command (action 134) for each section (1, 2, 3),
which paints every LED in that section uniformly — no per-pixel sync needed.
"""

from __future__ import annotations

import sys
import time
from typing import Iterable

import hid

VID = 0x1A86
PID = 0xFE07
CONTROL_USAGE_PAGE = 0xFF00

COLOR = (0xE8, 0x8B, 0x05)
BRIGHTNESS = 38
SECTIONS = (1, 2, 3)

ACTION_SET_OPEN_URL = 147
ACTION_SET_BRIGHTNESS = 135
ACTION_SET_SECTION_LED = 134

SECTION_TAIL = (63, 64, 0, 0, 0, 254)


def checksum8(data: Iterable[int]) -> int:
    return sum(data) & 0xFF


def build_rb(msg_id: int, action: int, payload: Iterable[int]) -> bytes:
    payload = list(payload)
    total_len = 2 + 1 + 1 + 1 + len(payload) + 1
    pkt = bytearray([ord("R"), ord("B"), total_len, msg_id, action, *payload])
    pkt.append(checksum8(pkt))
    return bytes(pkt)


def hid_write(dev: hid.device, packet: bytes) -> None:
    offset = 0
    while offset < len(packet):
        chunk = packet[offset : offset + 64]
        report = bytes([0x00]) + chunk + bytes(64 - len(chunk))
        if dev.write(report) < 0:
            raise RuntimeError(f"hid_write failed: {dev.error()}")
        offset += 64


def find_control_paths() -> list[bytes]:
    return [
        d["path"]
        for d in hid.enumerate(VID, PID)
        if d.get("usage_page") == CONTROL_USAGE_PAGE
    ]


def apply_static_color(path: bytes, *, off: bool = False) -> None:
    r, g, b = (0, 0, 0) if off else COLOR
    brightness = 0 if off else BRIGHTNESS
    dev = hid.device()
    dev.open_path(path)
    try:
        msg_id = 0
        hid_write(dev, build_rb(msg_id, ACTION_SET_OPEN_URL, [0])); msg_id += 1
        hid_write(dev, build_rb(msg_id, ACTION_SET_BRIGHTNESS, [brightness])); msg_id += 1
        for section in SECTIONS:
            payload = [section, r, g, b, *SECTION_TAIL]
            hid_write(dev, build_rb(msg_id, ACTION_SET_SECTION_LED, payload))
            msg_id += 1
            time.sleep(0.05)
    finally:
        dev.close()


def main(argv: list[str]) -> int:
    off = "--off" in argv[1:]
    paths = find_control_paths()
    if not paths:
        print("No Quiklight strip found", file=sys.stderr)
        return 1
    for path in paths:
        try:
            apply_static_color(path, off=off)
        except OSError as exc:
            print(f"Failed on {path!r}: {exc}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
