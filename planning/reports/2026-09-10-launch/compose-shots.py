#!/usr/bin/env python3
"""compose-shots.py — place phone/sim screenshots on 6.9-inch App Store canvases.

#443 bar 443-E. Apple's 6.9-inch slot wants 1320 × 2868 (portrait). A capture from a
6.9-inch simulator is already that size and passes through untouched; a capture from a
smaller phone is centred at native scale on a canvas filled with the app's Deep Field
background so the margin reads as the app, not as a frame. No upscaling, no mock-ups —
the image must show the app as it runs.

Usage:
    compose-shots.py <out_dir> <in.png> [<in.png> ...]
Outputs <out_dir>/<NN>-<stem>.png in argument order, numbered from 01.
"""
import sys
from pathlib import Path

from PIL import Image

CANVAS = (1320, 2868)
DEEP_FIELD = (6, 11, 18)  # Deep Field screen background, sampled from the app


def compose(src: Path, dst: Path) -> str:
    img = Image.open(src).convert("RGB")
    if img.size == CANVAS:
        img.save(dst, optimize=True)
        return f"{src.name}: native 6.9-inch, copied"
    if img.width > CANVAS[0] or img.height > CANVAS[1]:
        raise SystemExit(f"{src.name}: {img.size} exceeds the canvas — do not downscale store shots")
    canvas = Image.new("RGB", CANVAS, DEEP_FIELD)
    x = (CANVAS[0] - img.width) // 2
    y = (CANVAS[1] - img.height) // 2
    canvas.paste(img, (x, y))
    canvas.save(dst, optimize=True)
    return f"{src.name}: {img.size} centred on {CANVAS} at native scale"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    out = Path(argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for n, arg in enumerate(argv[2:], start=1):
        src = Path(arg)
        dst = out / f"{n:02d}-{src.stem}.png"
        print(compose(src, dst), "->", dst)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
