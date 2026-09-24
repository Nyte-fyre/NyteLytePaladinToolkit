"""Draws the project logo (original art, no Blizzard assets).

Theme: "Nyte Lyte", a paladin's light in the night. A starry night sky and
a crescent moon, with a paladin's shield blazing with holy light at the
center, bearing a hammer beneath a four-point "night light" star.
Run: python tools/make_logo.py   ->  docs/logo.png (400x400)
Needs Pillow (pip install pillow).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 400
S = 4  # supersample for smooth edges
W = SIZE * S
CX, CY = W // 2, int(W * 0.53)

GOLD = (255, 209, 64)
GOLD_DARK = (168, 112, 20)
LIGHT = (255, 246, 214)
MOON = (236, 232, 214)
NIGHT_TOP = (8, 10, 32)
NIGHT_BOTTOM = (38, 30, 82)
FIELD = (22, 26, 70)


def night_sky():
    sky = Image.new("RGBA", (W, W))
    d = ImageDraw.Draw(sky)
    for y in range(W):
        t = y / W
        col = tuple(int(NIGHT_TOP[k] + (NIGHT_BOTTOM[k] - NIGHT_TOP[k]) * t) for k in range(3))
        d.line([(0, y), (W, y)], fill=col + (255,))
    rng = random.Random(7)
    for _ in range(90):
        x, y = rng.uniform(0, W), rng.uniform(0, W)
        if math.hypot(x - CX, y - CY) < W * 0.27:
            continue  # keep the glow around the shield clean
        r = rng.choice([1.5, 2, 2.5, 3.5]) * S
        a = rng.randint(120, 255)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 230, a))
    return sky


def sparkle(d, x, y, size, color):
    """A four-point star."""
    t = size * 0.18
    d.polygon([(x, y - size), (x + t, y - t), (x + size, y), (x + t, y + t),
               (x, y + size), (x - t, y + t), (x - size, y), (x - t, y - t)], fill=color)


def moon(img):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    mx, my, r = W * 0.26, W * 0.27, W * 0.115
    d.ellipse([mx - r, my - r, mx + r, my + r], fill=MOON + (255,))
    # Bite out the crescent with the sky color gradient's top tone.
    ox, oy = mx + r * 0.42, my - r * 0.22
    d.ellipse([ox - r, oy - r, ox + r, oy + r], fill=(0, 0, 0, 0))
    glow = layer.filter(ImageFilter.GaussianBlur(W * 0.02))
    img.alpha_composite(glow)
    img.alpha_composite(layer)


def holy_light(img):
    rays = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(rays)
    n = 20
    for i in range(n):
        a = 2 * math.pi * i / n - math.pi / 2
        long_ray = i % 2 == 0
        length = W * (0.44 if long_ray else 0.33)
        half = math.radians(3.4 if long_ray else 2.2)
        d.polygon([(CX, CY), (CX + length * math.cos(a - half), CY + length * math.sin(a - half)),
                   (CX + length * math.cos(a + half), CY + length * math.sin(a + half))],
                  fill=GOLD + ((135 if long_ray else 85),))
    img.alpha_composite(rays.filter(ImageFilter.GaussianBlur(S * 1.5)))
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    r = W * 0.29
    ImageDraw.Draw(glow).ellipse([CX - r, CY - r, CX + r, CY + r], fill=LIGHT + (150,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(W * 0.07)))


def shield_points(scale):
    w, h = W * 0.40 * scale, W * 0.50 * scale
    top = CY - h * 0.50
    pts = [(CX - w / 2, top + h * 0.04), (CX, top - h * 0.02), (CX + w / 2, top + h * 0.04)]
    steps = 28
    for i in range(steps + 1):
        t = i / steps
        pts.append((CX + (w / 2) * (1 - t ** 1.7), top + h * 0.42 + h * 0.58 * t))
    for i in range(steps, -1, -1):
        t = i / steps
        pts.append((CX - (w / 2) * (1 - t ** 1.7), top + h * 0.42 + h * 0.58 * t))
    return pts


def shield(img):
    d = ImageDraw.Draw(img)
    d.polygon(shield_points(1.0), fill=GOLD_DARK + (255,))
    d.polygon(shield_points(0.92), fill=GOLD + (255,))
    d.polygon(shield_points(0.82), fill=FIELD + (255,))
    # Inner light wash at the top of the field.
    wash = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(wash).polygon(shield_points(0.82), fill=(90, 110, 200, 70))
    mask = Image.new("L", (W, W), 0)
    md = ImageDraw.Draw(mask)
    for y in range(W):
        md.line([(0, y), (W, y)], fill=max(0, int(255 - (y - (CY - W * 0.22)) * 0.6)))
    wash.putalpha(Image.composite(wash.getchannel("A"), Image.new("L", (W, W), 0), mask))
    img.alpha_composite(wash)

    d = ImageDraw.Draw(img)
    # Hammer (upright), in holy light.
    hw = W * 0.042
    d.rounded_rectangle([CX - hw / 2, CY - W * 0.03, CX + hw / 2, CY + W * 0.18], radius=hw / 2, fill=LIGHT + (255,))
    head_w, head_h = W * 0.21, W * 0.10
    top = CY - W * 0.10
    d.rounded_rectangle([CX - head_w / 2, top, CX + head_w / 2, top + head_h], radius=W * 0.014, fill=LIGHT + (255,))
    d.rounded_rectangle([CX - head_w / 2 + W * 0.012, top + W * 0.012, CX + head_w / 2 - W * 0.012,
                         top + head_h - W * 0.012], radius=W * 0.01, fill=GOLD + (255,))
    pr = W * 0.026
    d.ellipse([CX - pr, CY + W * 0.18 - pr, CX + pr, CY + W * 0.18 + pr], fill=GOLD + (255,))

    # The "night light": a glowing four-point star above the hammer.
    star = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sx, sy = CX, CY - W * 0.165
    sparkle(ImageDraw.Draw(star), sx, sy, W * 0.055, LIGHT + (255,))
    img.alpha_composite(star.filter(ImageFilter.GaussianBlur(W * 0.012)))
    sparkle(ImageDraw.Draw(img), sx, sy, W * 0.05, (255, 255, 250, 255))


def frame(img):
    ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(ring)
    d.ellipse([W * 0.02, W * 0.02, W * 0.98, W * 0.98], outline=GOLD + (230,), width=int(W * 0.014))
    d.ellipse([W * 0.045, W * 0.045, W * 0.955, W * 0.955], outline=GOLD_DARK + (180,), width=int(W * 0.005))
    img.alpha_composite(ring)
    # Circular crop so corners are transparent.
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse([W * 0.015, W * 0.015, W * 0.985, W * 0.985], fill=255)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (W, W), 0), mask))


def main():
    img = night_sky()
    # A few brighter sparkles in the sky.
    d = ImageDraw.Draw(img)
    for x, y, s in [(0.78, 0.18, 0.030), (0.86, 0.36, 0.018), (0.16, 0.62, 0.020), (0.70, 0.84, 0.016)]:
        sparkle(d, W * x, W * y, W * s, (255, 244, 210, 235))
    moon(img)
    holy_light(img)
    shield(img)
    frame(img)
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = os.path.join(ROOT, "docs", "logo.png")
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
