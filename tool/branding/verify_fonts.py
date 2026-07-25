#!/usr/bin/env python3
"""Verify the vendored TTFs in assets/fonts/ are real fonts.

Why this exists: the fonts are fetched over a proxied network. A proxy error
page, a redirect to an HTML login, or a truncated download all happily save
with a .ttf extension and then render nothing at runtime — a blank app, not a
degraded one. Shipping a corrupt font is not an acceptable degraded mode, so
this gate fails loudly and exits non-zero.

Run:  python3 tool/branding/verify_fonts.py
"""

from __future__ import annotations

import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
FONT_DIR = REPO_ROOT / "assets" / "fonts"

EXPECTED_FILES = [
    "Outfit-SemiBold.ttf",
    "NunitoSans-Regular.ttf",
    "NunitoSans-SemiBold.ttf",
    "NunitoSans-Bold.ttf",
    "RobotoMono-Regular.ttf",
    "RobotoMono-Medium.ttf",
]

# A real TrueType file opens with the sfnt version tag 0x00010000, or the
# ASCII 'true' used by some (mostly Apple) builds. HTML ('<'), JSON ('{'), and
# a WOFF2 ('wOF2') all fail here.
VALID_MAGIC = (b"\x00\x01\x00\x00", b"true")

MIN_BYTES = 20 * 1024


def main() -> int:
    failures: list[str] = []

    if not FONT_DIR.is_dir():
        print(f"FAIL: font directory missing: {FONT_DIR}")
        return 1

    found = sorted(p.name for p in FONT_DIR.glob("*.ttf"))

    if len(found) != len(EXPECTED_FILES):
        failures.append(
            f"expected {len(EXPECTED_FILES)} .ttf files, found {len(found)}: {found}"
        )

    for name in EXPECTED_FILES:
        path = FONT_DIR / name
        if not path.is_file():
            failures.append(f"{path}: missing")
            continue

        size = path.stat().st_size
        head = path.read_bytes()[:4]

        if not head.startswith(VALID_MAGIC):
            failures.append(
                f"{path}: bad magic bytes {head!r} (size {size} bytes) — "
                "this is not a TrueType font, likely an error page"
            )
            continue

        if size < MIN_BYTES:
            failures.append(
                f"{path}: implausibly small ({size} bytes < {MIN_BYTES}) — "
                "likely a truncated download"
            )
            continue

        print(f"ok   {name}  ({size:,} bytes, magic {head.hex()})")

    if failures:
        print()
        for f in failures:
            print(f"FAIL: {f}")
        return 1

    print(f"\nAll {len(EXPECTED_FILES)} vendored fonts verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
