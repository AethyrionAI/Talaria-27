#!/usr/bin/env python3
"""Render alternate app-icon PNGs from the theme-gallery SVGs (Lane K).

Rasterizes curated icon art out of design/themes/app-icons.html (the `icons[]`
array — each entry's `svg` field is a complete full-bleed 1024x1024 icon) into
the loose bundle resources the app-icon picker consumes. Complements
generate_app_icons.py, which draws the four flagship PLACEHOLDER icons
programmatically; gallery icons are rendered from their SVG source instead.

Output per icon — the same flat (no-alpha) files the flagship set uses, in
Talaria/Resources/AppIcons/ (see README.md):
  Icon-<Name>@2x.png (120)   -> OS alternate-icon file (CFBundleIconFiles)
  Icon-<Name>@3x.png (180)   -> OS alternate-icon file
  IconPreview-<Name>.png (240) -> in-app picker preview (UIImage(named:))

<Name> is the gallery id PascalCased ("glitch-garden" -> "GlitchGarden") — the
string wired as the CFBundleAlternateIcons key / setAlternateIconName(_:) value.

Run from the repo root:  python3 tools/appicons/render_gallery_icons.py
Requires cairosvg + Pillow  (pip install cairosvg Pillow).
"""
from __future__ import annotations

import io
import os
import re

import cairosvg
from PIL import Image

GALLERY = os.path.join("design", "themes", "app-icons.html")
OUT_DIR = os.path.join("Talaria", "Resources", "AppIcons")
MASTER = 1024  # native SVG canvas; downsampled per output

# The Lane K batch (dispatch/FABLE-LANE-K-app-icons.md) + the Lane L batch
# (Special Edition five + Midnight Marquee eight —
# dispatch/FABLE-LANE-L-midnight-marquee.md). Deliberately absent:
#   deep-field / solar-forge / terminal / paper-tape — flagship set, keeps its
#     generate_app_icons.py placeholder art until the curated swap;
#   deep-sea-diner — theme cut, icon cut with it (icon<->theme parity).
ICON_IDS = [
    "neon-arcade",
    "glitch-garden",
    "witchs-brew",
    "holo-sushi",
    "lunar-diner",
    "cyber-cactus",
    "disco-inferno",
    "cereal-box",
    "bubblegum-mecha",
    "retro-sci-fi",
    "autumn-harvest",
    "spring-sprout",
    "summer-solar",
    "winter-frost",
    # Special Edition (Lane L).
    "event-horizon",
    "graffiti-galaxy",
    "karaoke-supernova",
    "midnight-aquarium",
    "molten-forge",
    # Midnight Marquee (Lane L) — Comic Book ships BOTH variants as
    # separately selectable icons (icons stay independent of theme
    # selection, the Lane K coupling rule).
    "lucha-libre",
    "kaiju-attack",
    "pulp-noir",
    "casino-lucky-7s",
    "cosmic-bowling",
    "sticker-bomb-toybox",
    "comic-villain",
    "comic-funnies",
]


def pascal_case(gallery_id: str) -> str:
    return "".join(part.capitalize() for part in gallery_id.split("-"))


def load_gallery_svgs(path: str) -> dict[str, str]:
    """id -> svg for every `icons[]` entry. Each entry carries exactly one
    `id: '...'` and one backtick-quoted `svg` template (no nested backticks),
    in source order, so pairing the two scans is lossless."""
    with open(path, encoding="utf-8") as f:
        html = f.read()
    ids = re.findall(r"id:\s*'([^']+)'", html)
    svgs = re.findall(r"svg:\s*`([^`]+)`", html)
    if len(ids) != len(svgs):
        raise SystemExit(f"gallery parse mismatch: {len(ids)} ids vs {len(svgs)} svgs")
    return dict(zip(ids, svgs))


def render_master(svg: str) -> Image.Image:
    """SVG -> flat RGB 1024 master. The gallery SVGs open with a full-canvas
    background <rect>, so the render is already opaque edge to edge; the RGB
    convert just strips the (fully opaque) alpha channel iOS would reject."""
    png = cairosvg.svg2png(bytestring=svg.encode("utf-8"),
                           output_width=MASTER, output_height=MASTER)
    return Image.open(io.BytesIO(png)).convert("RGB")


def save_variants(master: Image.Image, name: str):
    for suffix, px in (("@2x", 120), ("@3x", 180)):
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(OUT_DIR, f"Icon-{name}{suffix}.png")
        )
    master.resize((240, 240), Image.LANCZOS).save(
        os.path.join(OUT_DIR, f"IconPreview-{name}.png")
    )


def main():
    if not os.path.isdir(os.path.join("Talaria", "Resources")):
        raise SystemExit("Run from the repo root (Talaria/Resources not found).")
    gallery = load_gallery_svgs(GALLERY)
    missing = [i for i in ICON_IDS if i not in gallery]
    if missing:
        raise SystemExit(f"gallery is missing icon ids: {missing}")
    os.makedirs(OUT_DIR, exist_ok=True)
    for icon_id in ICON_IDS:
        name = pascal_case(icon_id)
        save_variants(render_master(gallery[icon_id]), name)
        print(f"  Icon-{name} @2x/@3x + IconPreview-{name}.png")
    print(f"Done ({len(ICON_IDS)} icons) -> {OUT_DIR}")


if __name__ == "__main__":
    main()
