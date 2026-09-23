"""Draws the Index app logo and exports every icon size the app needs.

    python3 tool/logo/generate.py preview        # build/logo_options.png with all concepts
    python3 tool/logo/generate.py export <A|B|C>  # assets/logo/*.png for flutter_launcher_icons
    python3 tool/logo/generate.py web             # web maskable icons (after flutter_launcher_icons)

Drawn at 4x and downsampled for clean anti-aliasing. Only needs Pillow.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]  # mobile/
SS = 4  # supersampling factor
INDIGO = (79, 91, 213)  # theme seed 0xFF4F5BD5
VIOLET = (124, 77, 219)
WHITE = (255, 255, 255, 255)


def gradient(size, top=INDIGO, bottom=VIOLET):
    """Diagonal gradient, top-left to bottom-right."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,)
    return img


def gradient_fast(size, top=INDIGO, bottom=VIOLET):
    small = gradient(256, top, bottom)
    return small.resize((size, size), Image.BICUBIC)


def stroke(d, pts, width, fill=WHITE):
    """Polyline with round caps and joins."""
    d.line(pts, fill=fill, width=round(width), joint="curve")
    r = width / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


# Glyphs draw white shapes into a transparent square of side s, within the
# box (cx, cy, half) given in pixels. Unit coordinates run -1..1 inside it.

def glyph_check_i(d, cx, cy, half, color=WHITE):
    u = lambda x, y: (cx + x * half, cy + y * half)
    w = 0.30 * half
    stroke(d, [u(-0.62, 0.10), u(-0.18, 0.52), u(0.66, -0.40)], w, color)
    # The dot of the "i", above the short arm.
    r = 0.17 * half
    x, y = u(-0.62, -0.42)
    d.ellipse((x - r, y - r, x + r, y + r), fill=color)


def glyph_cards(d, cx, cy, half, color=WHITE):
    u = lambda x, y: (cx + x * half, cy + y * half)
    faded = color[:3] + (110,)
    mid = color[:3] + (175,)
    rad = 0.16 * half
    # Back cards peek out above the front card.
    for dy, fill, inset in ((-0.54, faded, 0.22), (-0.36, mid, 0.11)):
        x0, y0 = u(-0.78 + inset, dy)
        x1, y1 = u(0.78 - inset, dy + 0.9)
        d.rounded_rectangle((x0, y0, x1, y1), radius=rad, fill=fill)
    x0, y0 = u(-0.78, -0.16)
    x1, y1 = u(0.78, 0.78)
    d.rounded_rectangle((x0, y0, x1, y1), radius=rad, fill=color)
    # Check cut out of the front card.
    stroke(d, [u(-0.36, 0.30), u(-0.08, 0.56), u(0.40, 0.06)], 0.17 * half, (0, 0, 0, 0))


def glyph_ring(d, cx, cy, half, color=WHITE):
    w = 0.20 * half
    r = 0.80 * half
    box = (cx - r, cy - r, cx + r, cy + r)
    start, end = -90 + 28, -90 + 360 - 28  # gap at the top
    d.arc(box, start, end, fill=color, width=round(w))
    for a in (start, end):
        x = cx + (r - w / 2) * math.cos(math.radians(a))
        y = cy + (r - w / 2) * math.sin(math.radians(a))
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=color)
    u = lambda x, y: (cx + x * half, cy + y * half)
    stroke(d, [u(-0.36, 0.02), u(-0.08, 0.30), u(0.40, -0.22)], 0.19 * half, color)


GLYPHS = {"A": glyph_check_i, "B": glyph_cards, "C": glyph_ring}
NAMES = {"A": "Check-i", "B": "Index cards", "C": "Progress ring"}


def glyph_layer(key, size, scale, color=WHITE):
    """Transparent square with the glyph occupying `scale` of its width."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    GLYPHS[key](d, big / 2, big / 2, big * scale / 2, color)
    return img


def compose(key, size, rounded=True, glyph_scale=0.62):
    """Glyph on the gradient; `rounded` gives the launcher-style squircle."""
    big = size * SS
    bg = gradient_fast(big)
    # Transparent cut-outs in the glyph (the check in the cards) show the
    # gradient through.
    out = Image.alpha_composite(bg, glyph_layer(key, size, glyph_scale))
    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=big * 0.225, fill=255)
        out.putalpha(mask)
    return out.resize((size, size), Image.LANCZOS)


def transparent_glyph(key, size, scale, color=WHITE):
    return glyph_layer(key, size, scale, color).resize((size, size), Image.LANCZOS)


def preview():
    tile, pad = 360, 48
    keys = list(GLYPHS)
    sheet = Image.new("RGBA", (pad + len(keys) * (tile + pad), tile + 230), (246, 246, 250, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 30)
        small = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 20)
    except OSError:
        font = small = ImageFont.load_default()
    for i, k in enumerate(keys):
        x = pad + i * (tile + pad)
        sheet.alpha_composite(compose(k, tile), (x, pad))
        # Small sizes, as on a home screen and in a browser tab.
        sheet.alpha_composite(compose(k, 96), (x, pad + tile + 24))
        sheet.alpha_composite(compose(k, 48), (x + 112, pad + tile + 48))
        mono = Image.new("RGBA", (96, 96), (40, 40, 48, 255))
        mono.alpha_composite(transparent_glyph(k, 96, 0.55, (230, 230, 240, 255)))
        sheet.alpha_composite(mono, (x + 176, pad + tile + 24))
        d.text((x, pad + tile + 140), f"{k} · {NAMES[k]}", fill=(30, 30, 40, 255), font=font)
        d.text((x + 176, pad + tile + 124), "themed", fill=(110, 110, 120, 255), font=small)
    out = ROOT / "build" / "logo_options.png"
    out.parent.mkdir(exist_ok=True)
    sheet.convert("RGB").save(out)
    print(out)


def export(key):
    dest = ROOT / "assets" / "logo"
    dest.mkdir(parents=True, exist_ok=True)
    compose(key, 1024).save(dest / "icon.png")  # legacy launcher, web, favicon
    compose(key, 1024, rounded=False, glyph_scale=0.50).save(dest / "icon_maskable.png")  # web maskable
    gradient_fast(1024).save(dest / "adaptive_background.png")
    # Adaptive icons show the middle ~61% of the foreground; keep the glyph inside it.
    transparent_glyph(key, 1024, 0.40).save(dest / "adaptive_foreground.png")
    transparent_glyph(key, 1024, 0.40).save(dest / "adaptive_monochrome.png")
    # In-app mark (splash/auth screens): glyph on transparent, drawn by the app on its own tile.
    compose(key, 512).save(dest / "logo.png")
    (dest / "SOURCE.txt").write_text(f"Generated by tool/logo/generate.py export {key} ({NAMES[key]})\n")
    print(f"exported {NAMES[key]} to {dest}")


def web():
    """Full-bleed maskable icons (flutter_launcher_icons reuses the rounded icon)."""
    icons = ROOT / "web" / "icons"
    src = Image.open(ROOT / "assets" / "logo" / "icon_maskable.png")
    for size in (192, 512):
        src.resize((size, size), Image.LANCZOS).save(icons / f"Icon-maskable-{size}.png")
    print(f"wrote maskable icons to {icons}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "preview"
    if cmd == "preview":
        preview()
    elif cmd == "export":
        export(sys.argv[2].upper())
    elif cmd == "web":
        web()
    else:
        sys.exit(__doc__)
