"""Draws the CurseForge/GitHub project logo (original art, no Blizzard assets).

Holy theme: a golden sunburst behind a shield bearing a hammer.
Run: python tools/make_logo.py   ->  docs/logo.png (400x400)
Needs Pillow (pip install pillow).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 400
S = 4  # supersample for smooth edges
W = SIZE * S
CX, CY = W // 2, W // 2

GOLD = (255, 209, 64)
GOLD_DARK = (176, 122, 24)
LIGHT = (255, 244, 200)
NAVY = (16, 18, 40)
NAVY_LIGHT = (44, 40, 78)


def radial_background():
    bg = Image.new("RGB", (W, W), NAVY)
    d = ImageDraw.Draw(bg)
    steps = 60
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(W * 0.72 * t)
        col = tuple(int(NAVY[k] + (NAVY_LIGHT[k] - NAVY[k]) * (1 - t)) for k in range(3))
        d.ellipse([CX - r, CY - r, CX + r, CY + r], fill=col)
    return bg


def sunburst(img):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rays = 24
    for i in range(rays):
        a = 2 * math.pi * i / rays
        long_ray = i % 2 == 0
        length = W * (0.47 if long_ray else 0.38)
        half = math.radians(3.2 if long_ray else 2.2)
        pts = [
            (CX, CY),
            (CX + length * math.cos(a - half), CY + length * math.sin(a - half)),
            (CX + length * math.cos(a + half), CY + length * math.sin(a + half)),
        ]
        d.polygon(pts, fill=GOLD + ((150 if long_ray else 100),))
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = int(W * 0.30)
    gd.ellipse([CX - r, CY - r, CX + r, CY + r], fill=LIGHT + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.06))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(S)))
    img.alpha_composite(glow)


def shield_points(scale):
    # Heater shield, centered, pointing down.
    w, h = W * 0.42 * scale, W * 0.52 * scale
    top = CY - h * 0.48
    pts = [(CX - w / 2, top), (CX + w / 2, top)]
    steps = 24
    for i in range(steps + 1):  # right curve down to the point
        t = i / steps
        x = CX + (w / 2) * (1 - t ** 1.6)
        y = top + h * 0.45 + h * 0.55 * t
        pts.append((x, y))
    for i in range(steps, -1, -1):  # left curve back up
        t = i / steps
        x = CX - (w / 2) * (1 - t ** 1.6)
        y = top + h * 0.45 + h * 0.55 * t
        pts.append((x, y))
    return pts


def shield(img):
    d = ImageDraw.Draw(img)
    d.polygon(shield_points(1.0), fill=GOLD_DARK + (255,))
    d.polygon(shield_points(0.9), fill=GOLD + (255,))
    d.polygon(shield_points(0.78), fill=(34, 30, 64, 255))
    # Hammer: handle and head in parchment light.
    hw = W * 0.045
    d.rounded_rectangle([CX - hw / 2, CY - W * 0.08, CX + hw / 2, CY + W * 0.17], radius=hw / 2, fill=LIGHT + (255,))
    head_w, head_h = W * 0.24, W * 0.13
    d.rounded_rectangle([CX - head_w / 2, CY - W * 0.17, CX + head_w / 2, CY - W * 0.17 + head_h],
                        radius=W * 0.015, fill=LIGHT + (255,))
    d.rounded_rectangle([CX - head_w / 2 + W * 0.012, CY - W * 0.17 + W * 0.012,
                         CX + head_w / 2 - W * 0.012, CY - W * 0.17 + head_h - W * 0.012],
                        radius=W * 0.01, fill=GOLD + (255,))
    # Pommel.
    pr = W * 0.03
    d.ellipse([CX - pr, CY + W * 0.17 - pr, CX + pr, CY + W * 0.17 + pr], fill=GOLD + (255,))


def main():
    img = radial_background().convert("RGBA")
    sunburst(img)
    shield(img)
    # Soft round frame.
    ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([W * 0.02, W * 0.02, W * 0.98, W * 0.98], outline=GOLD + (200,), width=int(W * 0.012))
    img.alpha_composite(ring)
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = os.path.join(ROOT, "docs", "logo.png")
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
