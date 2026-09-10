#!/usr/bin/env python3
"""Draws the TetherCam .dmg background (640x400, the Finder window size the
release script sets) into the path given as argv[1].

Generated at build time with Pillow so no binary asset lives in the repo. Exits
non-zero when Pillow is missing — the release script then ships a plain volume
instead of failing.
"""
import sys

WIDTH, HEIGHT = 640, 400
BG = (24, 26, 32)
TEXT = (232, 234, 240)
ARROW = (94, 160, 255)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make-dmg-background.py <out.png>", file=sys.stderr)
        return 2
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow is not installed (pip3 install pillow)", file=sys.stderr)
        return 1

    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(img)

    # Arrow from the app icon (x ~160) to the Applications alias (x ~480); the
    # icons sit at y ~190 measured from the TOP in Finder coordinates.
    y = 205
    x0, x1 = 250, 390
    draw.line([(x0, y), (x1, y)], fill=ARROW, width=6)
    draw.polygon([(x1 + 22, y), (x1 - 4, y - 16), (x1 - 4, y + 16)], fill=ARROW)

    caption = "Drag TetherCam to Applications"
    font = None
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            font = ImageFont.truetype(path, 22)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()
    box = draw.textbbox((0, 0), caption, font=font)
    draw.text(((WIDTH - (box[2] - box[0])) / 2, 320), caption, fill=TEXT, font=font)

    img.save(sys.argv[1], "PNG")
    print("wrote %s (%dx%d)" % (sys.argv[1], WIDTH, HEIGHT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
