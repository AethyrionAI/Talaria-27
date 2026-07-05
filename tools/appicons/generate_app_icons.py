#!/usr/bin/env python3
"""Generate Talaria alternate app-icon PNGs from the theme palettes.

Placeholder / example icon art for issue #25 (the data-driven app-icon picker).
Each icon is an arc-reactor glyph rendered in a theme's hero palette on that
theme's screen gradient — echoing the in-app ReactorOrb identity. These are
programmatically-generated PLACEHOLDERS that prove the picker end-to-end; swap
them for the curated art (the 19 Open Design concepts) by dropping replacement
PNGs at the same paths — no picker or catalog code changes required. See
README.md for the "add / replace an icon" checklist.

The hero-slot hex values are copied verbatim from Shared/ThemePaletteCore.swift
(the `.cyan` slot = each theme's hero accent) so the icons match the themes.

Output — loose, flat (no-alpha) bundle resources in Talaria/Resources/AppIcons/:
  Icon-<Name>@2x.png (120)   -> OS alternate-icon file (CFBundleIconFiles)
  Icon-<Name>@3x.png (180)   -> OS alternate-icon file
  IconPreview-<id>.png (240) -> in-app picker preview (loaded via UIImage(named:))

Run from the repo root:  python3 tools/appicons/generate_app_icons.py
Requires Pillow  (pip install Pillow).
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

MASTER = 1024          # master render size; downsampled per output
OUT_DIR = os.path.join("Talaria", "Resources", "AppIcons")

# id, gradient stops (hex, location), ring/arc/core hero hexes, glow, light flag.
# All hero values are the `.cyan` (hero) slot from ThemePaletteCore.swift.
THEMES = [
    dict(id="DeepField",
         grad=[(0x0C2730, 0.0), (0x070D15, 0.52), (0x04070C, 1.0)],
         ring=0x54E6F0, arc=0xCDF8FB, core=(0xE2FBFD, 0x54E6F0, 0x14636E),
         glow=0x54E6F0, light=False),
    dict(id="SolarForge",
         grad=[(0x2A1A0C, 0.0), (0x120C07, 0.52), (0x080602, 1.0)],
         ring=0xFFC14D, arc=0xFFE2A6, core=(0xFFF1D2, 0xFFC14D, 0x6E4D14),
         glow=0xFFC14D, light=False),
    dict(id="Terminal",
         grad=[(0x0A140A, 0.0), (0x040A04, 0.52), (0x000000, 1.0)],
         ring=0x33FF00, arc=0xB6FF9E, core=(0xE4FFDB, 0x33FF00, 0x0E6B00),
         glow=0x33FF00, light=False),
    dict(id="PaperTape",
         grad=[(0xF9F6F0, 0.0), (0xF2EFE9, 0.52), (0xE7E1D6, 1.0)],
         ring=0xB5382E, arc=0x7E1F17, core=(0xFAEDEA, 0xB5382E, 0xE5978F),
         glow=0xB5382E, light=True),
]


def rgb(h: int) -> tuple[int, int, int]:
    return ((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_bg(size, stops):
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    cols = [(rgb(h), loc) for h, loc in stops]
    for y in range(size):
        t = y / (size - 1)
        color = cols[-1][0]
        for i in range(len(cols) - 1):
            (c0, l0), (c1, l1) = cols[i], cols[i + 1]
            if t <= l1 or i == len(cols) - 2:
                tt = 0.0 if l1 == l0 else max(0.0, min(1.0, (t - l0) / (l1 - l0)))
                color = lerp(c0, c1, tt)
                break
        draw.line([(0, y), (size, y)], fill=color)
    return img


def add_glow(base, cx, cy, radius, color, strength):
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=(*color, 255)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.6))
    alpha = glow.split()[3].point(lambda v: int(v * strength))
    glow.putalpha(alpha)
    base.paste(glow, (0, 0), glow)


def draw_core(img, cx, cy, radius, center, mid, edge):
    draw = ImageDraw.Draw(img)
    for r in range(radius, 0, -1):
        t = 1 - r / radius                       # 0 at edge -> 1 at center
        if t < 0.6:
            color = lerp(edge, mid, t / 0.6)
        else:
            color = lerp(mid, center, (t - 0.6) / 0.4)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def ring(img, cx, cy, radius, color, width):
    ImageDraw.Draw(img).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], outline=color, width=width
    )


def corner_brackets(img, color, strength):
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    s = img.size[0]
    inset = int(s * 0.11)
    length = int(s * 0.12)
    width = max(2, int(s * 0.010))
    a = int(255 * strength)
    col = (*color, a)
    for (ox, oy, dx, dy) in [
        (inset, inset, 1, 1),
        (s - inset, inset, -1, 1),
        (inset, s - inset, 1, -1),
        (s - inset, s - inset, -1, -1),
    ]:
        draw.line([(ox, oy), (ox + dx * length, oy)], fill=col, width=width)
        draw.line([(ox, oy), (ox, oy + dy * length)], fill=col, width=width)
    img.paste(overlay, (0, 0), overlay)


def render(theme) -> Image.Image:
    s = MASTER
    img = gradient_bg(s, theme["grad"])
    cx = cy = s // 2
    ring_c = rgb(theme["ring"])
    arc_c = rgb(theme["arc"])
    center, mid, edge = (rgb(c) for c in theme["core"])
    light = theme["light"]

    add_glow(img, cx, cy, int(s * 0.24), rgb(theme["glow"]), 0.12 if light else 0.55)

    corner_brackets(img, ring_c, 0.28 if not light else 0.45)

    outer_r = int(s * 0.34)
    ring(img, cx, cy, outer_r, ring_c, max(2, int(s * 0.011)))
    # Bright HUD arc over the top-right quadrant.
    ImageDraw.Draw(img).arc(
        [cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r],
        start=-70, end=55, fill=arc_c, width=max(3, int(s * 0.022)),
    )
    ring(img, cx, cy, int(s * 0.27), lerp(ring_c, (0, 0, 0) if not light else (255, 255, 255), 0.35),
         max(2, int(s * 0.006)))

    draw_core(img, cx, cy, int(s * 0.16), center, mid, edge)
    return img


def save_variants(master: Image.Image, theme_id: str):
    os.makedirs(OUT_DIR, exist_ok=True)
    # OS alternate-icon files (60pt @2x/@3x). Flat RGB, no alpha.
    for scale, px in (("@2x", 120), ("@3x", 180)):
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(OUT_DIR, f"Icon-{theme_id}{scale}.png")
        )
    # In-app picker preview.
    master.resize((240, 240), Image.LANCZOS).save(
        os.path.join(OUT_DIR, f"IconPreview-{theme_id}.png")
    )


def make_default_preview():
    """The default icon's art lives in the asset catalog (AppIcon), which is not
    loadable as a loose image — bake a picker preview from it so the 'Default'
    card has a real thumbnail."""
    src = os.path.join("Talaria", "Resources", "Assets.xcassets",
                       "AppIcon.appiconset", "AppIcon.png")
    if not os.path.exists(src):
        print(f"! default source missing ({src}); skipping IconPreview-Default")
        return
    Image.open(src).convert("RGB").resize((240, 240), Image.LANCZOS).save(
        os.path.join(OUT_DIR, "IconPreview-Default.png")
    )
    print("  IconPreview-Default.png (from AppIcon.png)")


def main():
    if not os.path.isdir(os.path.join("Talaria", "Resources")):
        raise SystemExit("Run from the repo root (Talaria/Resources not found).")
    os.makedirs(OUT_DIR, exist_ok=True)
    make_default_preview()
    for theme in THEMES:
        master = render(theme)
        save_variants(master, theme["id"])
        print(f"  Icon-{theme['id']} @2x/@3x + IconPreview-{theme['id']}.png")
    print(f"Done -> {OUT_DIR}")


if __name__ == "__main__":
    main()
