#!/usr/bin/env python3
"""Verify the generated branding PNGs are valid, correctly sized, and not blank.

A silently blank or mis-sized icon looks like a successful build and then ships
a white square to the launcher. This gate makes that a build failure.

Run:  python3 tool/branding/verify_assets.py
"""

from __future__ import annotations

import pathlib
import sys

try:
    from PIL import Image, ImageStat
except ImportError:  # pragma: no cover
    print("FAIL: Pillow is required. Install with: python3 -m pip install pillow")
    sys.exit(1)

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
BRANDING_DIR = REPO_ROOT / "assets" / "branding"
ANDROID_RES = REPO_ROOT / "android" / "app" / "src" / "main" / "res"

# path (relative to repo root) -> expected (width, height)
EXPECTED: dict[str, tuple[int, int]] = {
    "assets/branding/mark-1024.png": (1024, 1024),
    "assets/branding/mark-foreground-1024.png": (1024, 1024),
    "assets/branding/mark-monochrome-1024.png": (1024, 1024),
    "assets/branding/mark-splash-dark.png": (1024, 1024),
    "assets/branding/mark-splash-light.png": (1024, 1024),
    "android/app/src/main/res/drawable-mdpi/ic_stat_monitor.png": (24, 24),
    "android/app/src/main/res/drawable-hdpi/ic_stat_monitor.png": (36, 36),
    "android/app/src/main/res/drawable-xhdpi/ic_stat_monitor.png": (48, 48),
    "android/app/src/main/res/drawable-xxhdpi/ic_stat_monitor.png": (72, 72),
    "android/app/src/main/res/drawable-xxxhdpi/ic_stat_monitor.png": (96, 96),
}

# The five stock Flutter ic_launcher.png md5 sums recorded before this task,
# smallest density first. None of them may survive under mipmap-*.
STOCK_LAUNCHER_MD5 = {
    "6270344430679711b81476e29878caa7",
    "13e9c72ec37fac220397aa819fa1ef2d",
    "a0a8db5985280b3679d99a820ae2db79",
    "afe1b655b9f32da22f9a4301bb8e6ba8",
    "57838d52c318faff743130c3fcfae0c6",
}


def check_image(rel: str, expected: tuple[int, int], failures: list[str]) -> None:
    path = REPO_ROOT / rel
    if not path.is_file():
        failures.append(f"{rel}: missing")
        return

    try:
        with Image.open(path) as img:
            img.load()
            size = img.size
            rgba = img.convert("RGBA")
    except Exception as e:  # noqa: BLE001 — any decode failure is a failure
        failures.append(f"{rel}: not a readable image ({e})")
        return

    if size != expected:
        failures.append(f"{rel}: expected {expected}, got {size}")
        return

    colours = rgba.getcolors(maxcolors=1 << 24)
    if colours is not None and len(colours) < 2:
        failures.append(f"{rel}: blank — only one distinct colour")
        return

    stddev = ImageStat.Stat(rgba).stddev
    if not any(s > 0 for s in stddev):
        failures.append(f"{rel}: blank — zero standard deviation on every channel")
        return

    n_colours = "many" if colours is None else len(colours)
    print(f"ok   {rel}  ({size[0]}x{size[1]}, {n_colours} colours)")


def check_stock_icon_gone(failures: list[str]) -> None:
    import hashlib

    survivors = []
    checked = 0
    for path in sorted(ANDROID_RES.glob("mipmap-*/*.png")):
        checked += 1
        digest = hashlib.md5(path.read_bytes()).hexdigest()  # noqa: S324
        if digest in STOCK_LAUNCHER_MD5:
            survivors.append(f"{path.relative_to(REPO_ROOT)} ({digest})")

    if checked == 0:
        failures.append("no launcher PNGs found under android/.../res/mipmap-*")
        return

    if survivors:
        failures.append(
            "stock Flutter launcher icon still present in: " + ", ".join(survivors)
        )
        return

    print(f"ok   {checked} mipmap PNGs, none matching a stock Flutter icon md5")


def main() -> int:
    failures: list[str] = []

    if not BRANDING_DIR.is_dir():
        print(f"FAIL: branding directory missing: {BRANDING_DIR}")
        return 1

    for rel, expected in EXPECTED.items():
        check_image(rel, expected, failures)

    # Any extra PNG dropped into assets/branding/ still has to be a real image.
    for path in sorted(BRANDING_DIR.glob("*.png")):
        rel = str(path.relative_to(REPO_ROOT))
        if rel not in EXPECTED:
            failures.append(f"{rel}: unexpected PNG — add it to EXPECTED or remove it")

    check_stock_icon_gone(failures)

    if failures:
        print()
        for f in failures:
            print(f"FAIL: {f}")
        return 1

    print("\nAll branding assets verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
