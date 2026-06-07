"""Generate Race Mate app icons.

Outputs:
  assets/branding/icon.png            1024x1024, opaque, used for iOS + generic
  assets/branding/icon_foreground.png 1024x1024, transparent, Android adaptive
                                       (sail-only on transparent background)
"""

from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT_DIR = os.path.join(os.path.dirname(__file__), os.pardir, "assets", "branding")

# Deep ocean blue palette
TOP = (10, 58, 110)      # #0A3A6E
BOTTOM = (4, 28, 60)     # #041C3C
SAIL = (250, 252, 255)
HULL = (235, 240, 245)
WAVE = (255, 255, 255, 60)


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def draw_sail(draw: ImageDraw.ImageDraw, scale: float = 1.0, cx: float = 0.5, cy: float = 0.52) -> None:
    """Draws a stylized main + jib sail centered around (cx, cy)."""
    s = SIZE
    # Mast position
    mast_x = cx * s
    top_y = (cy - 0.32 * scale) * s
    bot_y = (cy + 0.30 * scale) * s

    # Mainsail (right of mast)
    main = [
        (mast_x, top_y),
        (mast_x, bot_y),
        (mast_x + 0.34 * scale * s, bot_y),
    ]
    draw.polygon(main, fill=SAIL)

    # Jib (left of mast, smaller)
    jib = [
        (mast_x, top_y + 0.06 * scale * s),
        (mast_x, bot_y - 0.04 * scale * s),
        (mast_x - 0.22 * scale * s, bot_y - 0.04 * scale * s),
    ]
    draw.polygon(jib, fill=SAIL)

    # Hull (simple arc-like trapezoid below sails)
    hull_top = bot_y + 0.012 * s
    hull = [
        (mast_x - 0.32 * scale * s, hull_top),
        (mast_x + 0.36 * scale * s, hull_top),
        (mast_x + 0.24 * scale * s, hull_top + 0.07 * scale * s),
        (mast_x - 0.20 * scale * s, hull_top + 0.07 * scale * s),
    ]
    draw.polygon(hull, fill=HULL)


def draw_waves(img: Image.Image) -> None:
    """Soft white wave hints under the boat."""
    s = SIZE
    overlay = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    base_y = 0.78 * s
    for i, (amp, y_off, alpha) in enumerate([(14, 0, 70), (10, 26, 50), (8, 50, 35)]):
        path = []
        for x in range(0, s + 1, 8):
            y = base_y + y_off + math.sin(x / 60.0 + i) * amp
            path.append((x, y))
        # Stroke as polyline by drawing repeated lines for thickness
        for k in range(-3, 4):
            shifted = [(x, y + k) for (x, y) in path]
            od.line(shifted, fill=(255, 255, 255, alpha), width=1)
    overlay = overlay.filter(ImageFilter.GaussianBlur(1.2))
    img.alpha_composite(overlay)


def make_icon() -> Image.Image:
    bg = vertical_gradient(SIZE, TOP, BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(bg)
    draw_sail(draw, scale=1.0, cx=0.52, cy=0.50)
    draw_waves(bg)
    return bg


def make_foreground() -> Image.Image:
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(fg)
    # Adaptive icons get center-cropped by ~33%; keep sails comfortably inside safe zone.
    draw_sail(draw, scale=0.72, cx=0.52, cy=0.50)
    return fg


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    icon = make_icon()
    icon.convert("RGB").save(os.path.join(OUT_DIR, "icon.png"), "PNG")
    fg = make_foreground()
    fg.save(os.path.join(OUT_DIR, "icon_foreground.png"), "PNG")
    print("wrote", os.path.abspath(OUT_DIR))


if __name__ == "__main__":
    main()
