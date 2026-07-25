#!/usr/bin/env python3
"""Generate the RTSP Mixer "crescent level-meter" mark.

The mark is a crescent of rounded bars whose lengths ease in and out along an
arc, over a solid centre dot: a level meter bent into a moon, for an app that
listens to a room at night.

No SVG rasterizer exists in this environment (rsvg-convert, inkscape,
imagemagick, and cairosvg are all absent), so the geometry below is the single
source of truth and is rendered two ways from the same constants: an SVG master
for humans to read and edit, and PNGs drawn numerically with Pillow.

Determinism: the drawing is pure arithmetic with no randomness, no timestamps,
and no font dependency. Running this twice produces byte-identical output.

Run:  python3 tool/branding/generate_mark.py
Then: python3 tool/branding/verify_assets.py
"""

from __future__ import annotations

import math
import pathlib
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print("FAIL: Pillow is required. Install with: python3 -m pip install pillow")
    sys.exit(1)

# ---------------------------------------------------------------------------
# GEOMETRY — the single source of truth. Keep this block in sync with any hand
# edit to assets/branding/mark.svg (the SVG is regenerated from here anyway).
# All values are in design units on a 100x100 canvas centred at (50, 50).
# ---------------------------------------------------------------------------
CANVAS = 100.0
CENTER = 50.0

BAR_COUNT = 15
ARC_START_DEG = -118.0  # 0 deg = 12 o'clock, positive clockwise
ARC_END_DEG = 118.0
ARC_RADIUS = 33.0  # the arc the bars are CENTRED on, so length variation shows
# on both the inner and outer rim and the inner ends stay spread apart
BAR_LEN_MIN = 9.0
BAR_LEN_MAX = 21.0
STROKE_WIDTH = 4.2
DOT_RADIUS = 6.0

# Density check (why the constants above are what they are): the bars crowd
# together at their INNER ends, and the worst case is the longest bar in the
# middle of the sweep. Angular pitch is (ARC_END-ARC_START)/(BAR_COUNT-1) =
# 16.86 deg = 0.2942 rad; the longest bar's inner end sits at
# ARC_RADIUS - BAR_LEN_MAX/2 = 22.5, so neighbouring centres are 0.2942*22.5 =
# 6.62 apart and the ink gap is 6.62 - 4.2 = 2.4 units. Anything at or below
# zero fuses the crescent into a solid fan, which is what 22 bars of stroke 5.4
# on a radius-40 arc did. Keep this margin if you retune.

# ---------------------------------------------------------------------------
# PALETTE (Roomtone)
# ---------------------------------------------------------------------------
TEAL = (0x3F, 0xBF, 0xAD, 0xFF)  # dark-mode accent
TEAL_DARK = (0x0B, 0x85, 0x78, 0xFF)  # light-mode accent, for a light splash
PETROL = (0x0B, 0x16, 0x18, 0xFF)  # ground
MONO_INK = (0x0F, 0x1F, 0x21, 0xFF)  # Android 13 themed/monochrome layer
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)  # status-bar notification icon
TRANSPARENT = (0, 0, 0, 0)

SUPERSAMPLE = 4  # Pillow has no round line caps; draw big, then LANCZOS down

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
BRANDING_DIR = REPO_ROOT / "assets" / "branding"
ANDROID_RES = REPO_ROOT / "android" / "app" / "src" / "main" / "res"


def bars() -> list[tuple[float, float, float, float]]:
    """The bar segments as ((x0, y0), (x1, y1)) pairs in design units."""
    segments = []
    for i in range(BAR_COUNT):
        t = i / (BAR_COUNT - 1)
        angle = math.radians(ARC_START_DEG + (ARC_END_DEG - ARC_START_DEG) * t)
        # sin(t*pi) eases the length in and out, so the crescent tapers at both
        # tips and peaks in the middle.
        length = BAR_LEN_MIN + (BAR_LEN_MAX - BAR_LEN_MIN) * math.sin(t * math.pi)
        sin_a, cos_a = math.sin(angle), math.cos(angle)
        outer = ARC_RADIUS + length / 2.0
        inner = ARC_RADIUS - length / 2.0
        segments.append(
            (
                CENTER + outer * sin_a,
                CENTER - outer * cos_a,
                CENTER + inner * sin_a,
                CENTER - inner * cos_a,
            )
        )
    return segments


def ink_bounds() -> tuple[float, float, float, float]:
    """Bounding box of everything actually painted, in design units.

    The arc's geometric centre is (50, 50) but the crescent's *ink* is not
    centred there — the gap at the bottom means the mark is top-heavy by about
    ten units. Framing on the arc centre instead of the ink would push the
    launcher icon visibly high in its mask, so every PNG is fitted to this box.
    """
    cap = STROKE_WIDTH / 2.0
    xs: list[float] = [CENTER - DOT_RADIUS, CENTER + DOT_RADIUS]
    ys: list[float] = [CENTER - DOT_RADIUS, CENTER + DOT_RADIUS]
    for x0, y0, x1, y1 in bars():
        for x, y in ((x0, y0), (x1, y1)):
            xs += [x - cap, x + cap]
            ys += [y - cap, y + cap]
    return min(xs), min(ys), max(xs), max(ys)


def render_png(
    size: int,
    *,
    fg: tuple[int, int, int, int],
    bg: tuple[int, int, int, int],
    fill: float,
) -> Image.Image:
    """Draw the mark at `size` px, its ink spanning `fill` of the canvas."""
    hi = size * SUPERSAMPLE
    image = Image.new("RGBA", (hi, hi), bg)
    draw = ImageDraw.Draw(image)

    min_x, min_y, max_x, max_y = ink_bounds()
    span = max(max_x - min_x, max_y - min_y)
    unit = hi * fill / span  # design units -> supersampled pixels
    origin_x = hi / 2.0 - (min_x + max_x) / 2.0 * unit
    origin_y = hi / 2.0 - (min_y + max_y) / 2.0 * unit

    def px(v: float) -> float:
        return origin_x + v * unit

    def py(v: float) -> float:
        return origin_y + v * unit

    stroke = STROKE_WIDTH * unit
    cap = stroke / 2.0

    for x0, y0, x1, y1 in bars():
        a = (px(x0), py(y0))
        b = (px(x1), py(y1))
        draw.line([a, b], fill=fg, width=max(1, round(stroke)))
        # Round caps by hand: Pillow's line primitive has none.
        for cx, cy in (a, b):
            draw.ellipse([cx - cap, cy - cap, cx + cap, cy + cap], fill=fg)

    dot = DOT_RADIUS * unit
    cx, cy = px(CENTER), py(CENTER)
    draw.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=fg)

    return image.resize((size, size), Image.LANCZOS)


def svg(fg_hex: str, bg_hex: str | None) -> str:
    """The same geometry as a human-readable master."""
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<!-- GENERATED by tool/branding/generate_mark.py — edit the geometry",
        "     constants in that script and re-run, do not hand-edit here. -->",
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS:.0f} '
        f'{CANVAS:.0f}" width="{CANVAS:.0f}" height="{CANVAS:.0f}">',
    ]
    if bg_hex:
        lines.append(f'  <rect width="{CANVAS:.0f}" height="{CANVAS:.0f}" fill="{bg_hex}"/>')
    lines.append(
        f'  <g stroke="{fg_hex}" stroke-width="{STROKE_WIDTH}" stroke-linecap="round" fill="none">'
    )
    for x0, y0, x1, y1 in bars():
        lines.append(
            f'    <line x1="{x0:.3f}" y1="{y0:.3f}" x2="{x1:.3f}" y2="{y1:.3f}"/>'
        )
    lines.append("  </g>")
    lines.append(
        f'  <circle cx="{CENTER:.0f}" cy="{CENTER:.0f}" r="{DOT_RADIUS}" fill="{fg_hex}"/>'
    )
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def write(path: pathlib.Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # optimize=True is deterministic; Pillow writes no tIME chunk by default.
    image.save(path, "PNG", optimize=True)
    print(f"wrote {path.relative_to(REPO_ROOT)}  ({image.width}x{image.height})")


def write_text(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    print(f"wrote {path.relative_to(REPO_ROOT)}")


def main() -> int:
    # --- SVG masters ---
    write_text(BRANDING_DIR / "mark.svg", svg("#3FBFAD", "#0B1618"))
    write_text(BRANDING_DIR / "mark-mono.svg", svg("#0F1F21", None))

    # --- Source PNGs ---
    # Full-colour square source: what the legacy launcher icon is cut from.
    write(
        BRANDING_DIR / "mark-1024.png",
        render_png(1024, fg=TEAL, bg=PETROL, fill=0.78),
    )
    # Adaptive foreground: transparent, inset to ~66% so the launcher's mask
    # (which can crop to a circle, squircle, or rounded square) never clips it.
    write(
        BRANDING_DIR / "mark-foreground-1024.png",
        render_png(1024, fg=TEAL, bg=TRANSPARENT, fill=0.66),
    )
    # Android 13 themed icon layer: one flat colour, system-tinted.
    write(
        BRANDING_DIR / "mark-monochrome-1024.png",
        render_png(1024, fg=MONO_INK, bg=TRANSPARENT, fill=0.66),
    )
    # Splash art, one per brightness — teal reads on petrol, the darker teal
    # reads on the light ground.
    write(
        BRANDING_DIR / "mark-splash-dark.png",
        render_png(1024, fg=TEAL, bg=TRANSPARENT, fill=0.66),
    )
    write(
        BRANDING_DIR / "mark-splash-light.png",
        render_png(1024, fg=TEAL_DARK, bg=TRANSPARENT, fill=0.66),
    )

    # --- Status-bar notification icon ---
    # Android tints small icons by their alpha, so these are drawn white on
    # transparent and rendered per density directly into the Android res tree.
    for density, size in (
        ("mdpi", 24),
        ("hdpi", 36),
        ("xhdpi", 48),
        ("xxhdpi", 72),
        ("xxxhdpi", 96),
    ):
        write(
            ANDROID_RES / f"drawable-{density}" / "ic_stat_monitor.png",
            render_png(size, fg=WHITE, bg=TRANSPARENT, fill=0.90),
        )

    print("\nMark generated. Now run: python3 tool/branding/verify_assets.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
