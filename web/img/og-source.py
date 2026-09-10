#!/usr/bin/env python3
"""Generate the TetherCam social card and the Mac-app visual.

    python3 web/img/og-source.py

Writes, relative to the repository root:
    web/img/og.png            1200x630 Open Graph / Twitter card
    web/img/mac-app-zoom.png  1600x1000 illustration of the camera picker

Only Pillow is required. Fonts come from the system. No faces and no private
rooms appear in either image: the only photographic element is the generated
studio-desk scene in images/generated-1788629447997.png.
"""

import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "web", "img")
SCENE = os.path.join(ROOT, "images", "generated-1788629447997.png")

# Site tokens, from web/style.css :root
BG = (11, 12, 16)          # --bg      #0B0C10
CARD = (22, 24, 31)        # --card    #16181F
ELEV = (18, 19, 25)        # --bg-elevated #121319
BORDER = (36, 39, 49)      # --border  #242731
BORDER_STRONG = (51, 56, 70)
FG = (242, 243, 245)       # --fg      #F2F3F5
MUTED = (154, 160, 173)    # --fg-muted #9AA0AD
ACCENT = (139, 124, 246)   # --accent  #8B7CF6
SIGNAL = (74, 222, 128)    # --signal  #4ADE80

SF = "/System/Library/Fonts/SFNS.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"
ARIAL_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
ARIAL = "/System/Library/Fonts/Supplemental/Arial.ttf"
MENLO = "/System/Library/Fonts/Menlo.ttc"


def font(size, weight="Regular", mono=False):
    path = SF_MONO if mono else SF
    try:
        f = ImageFont.truetype(path, size)
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
        return f
    except Exception:
        if mono:
            return ImageFont.truetype(MENLO, size)
        return ImageFont.truetype(ARIAL_BOLD if weight != "Regular" else ARIAL, size)


def tracked(draw, xy, text, fnt, fill, tracking=0):
    """Draw text with extra letter spacing, returns the end x."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking
    return x


# --------------------------------------------------------------------------- og

def build_og():
    W, H = 1200, 630
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)

    f_eyebrow = font(17, "Bold", mono=True)
    f_h1 = font(47, "Bold")
    f_sub = font(25, "Regular")
    f_foot = font(17, "Bold", mono=True)
    f_small = font(15, "Regular", mono=True)
    f_status = font(17, "Regular", mono=True)

    # eyebrow
    d.line([(72, 322 - 148), (104, 322 - 148)], fill=MUTED, width=2)
    tracked(d, (120, 165), "OPEN SOURCE  ·  MACOS  ·  NO WI-FI", f_eyebrow, MUTED, 1.6)

    # headline
    d.text((72, 214), "Your iPhone as a wired", font=f_h1, fill=FG)
    d.text((72, 272), "webcam for your Mac", font=f_h1, fill=ACCENT)

    # sub
    d.text((72, 366), "Zoom · Teams · Meet · FaceTime · OBS", font=f_sub, fill=FG)
    d.text((72, 404), "USB only, no cloud", font=f_sub, fill=MUTED)

    # footer wordmark
    tracked(d, (72, 552), "TETHERCAM.APP", f_foot, MUTED, 2.4)

    # ---- right panel: phone, cable, Mac
    px, py, pw, ph = 645, 148, 482, 334
    d.rounded_rectangle([px, py, px + pw, py + ph], radius=12, fill=ELEV, outline=BORDER)

    # phone
    fx, fy, fw, fh = px + 45, py + 48, 108, 200
    d.rounded_rectangle([fx, fy, fx + fw, fy + fh], radius=17, fill=(24, 26, 34), outline=BORDER_STRONG)
    d.rounded_rectangle([fx + 7, fy + 7, fx + fw - 7, fy + fh - 7], radius=12, fill=(16, 17, 23))
    d.rounded_rectangle([fx + 37, fy + 13, fx + fw - 37, fy + 18], radius=3, fill=BORDER_STRONG)
    d.rounded_rectangle([fx + 15, fy + 32, fx + fw - 15, fy + 140], radius=6,
                        fill=(38, 34, 68), outline=BORDER_STRONG)
    d.ellipse([fx + 41, fy + 74, fx + 67, fy + 100], fill=(96, 86, 190))
    d.rounded_rectangle([fx + 15, fy + 156, fx + 67, fy + 160], radius=2, fill=(58, 62, 76))
    d.rounded_rectangle([fx + 15, fy + 170, fx + 49, fy + 174], radius=2, fill=(45, 48, 60))

    # mac
    mx, my, mw, mh = px + 268, py + 30, 178, 128
    d.rounded_rectangle([mx, my, mx + mw, my + mh], radius=8, fill=(24, 26, 34), outline=BORDER_STRONG)
    d.line([(mx, my + 26), (mx + mw, my + 26)], fill=BORDER_STRONG, width=1)
    for i, alpha in enumerate((150, 110, 80)):
        d.ellipse([mx + 12 + i * 13, my + 9, mx + 20 + i * 13, my + 17], fill=(alpha, alpha + 6, alpha + 16))
    d.rounded_rectangle([mx + 12, my + 38, mx + mw - 12, my + mh - 12], radius=4, fill=(16, 17, 23))
    d.rounded_rectangle([mx + 20, my + 46, mx + mw - 20, my + mh - 20], radius=3,
                        fill=(38, 34, 68), outline=BORDER_STRONG)
    d.ellipse([mx + mw // 2 - 12, my + 74, mx + mw // 2 + 12, my + 98], fill=(96, 86, 190))

    # cable
    d.line([(fx + fw // 2, fy + fh + 4), (fx + fw // 2, fy + fh + 34),
            (mx - 26, fy + fh + 34), (mx - 26, my + mh // 2 + 6), (mx - 6, my + mh // 2 + 6)],
           fill=ACCENT, width=4, joint="curve")
    d.ellipse([fx + fw // 2 + 44, fy + fh + 28, fx + fw // 2 + 56, fy + fh + 40], fill=SIGNAL)
    d.rounded_rectangle([fx + fw // 2 - 7, fy + fh - 2, fx + fw // 2 + 7, fy + fh + 8], radius=3, fill=ACCENT)
    d.rounded_rectangle([mx - 10, my + mh // 2, mx + 4, my + mh // 2 + 12], radius=3, fill=ACCENT)

    d.text((mx + 4, py + 218), "USB-C · TCP 7878", font=f_small, fill=MUTED)
    d.text((mx + 4, py + 240), "HEVC, HARDWARE", font=f_small, fill=MUTED)

    d.line([(px + 22, py + ph - 48), (px + pw - 22, py + ph - 48)], fill=BORDER, width=1)
    d.ellipse([px + 22, py + ph - 33, px + 32, py + ph - 23], fill=SIGNAL)
    d.text((px + 42, py + ph - 36), "Camera \"TetherCam\" · 1080p30", font=f_status, fill=MUTED)

    im.save(os.path.join(OUT, "og.png"), optimize=True)
    return im.size


# ------------------------------------------------------------------- mac-app

def build_mac_app():
    W, H = 1600, 840
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)

    f_title = font(24, "Semibold")
    f_lbl = font(24, "Regular")
    f_item = font(28, "Regular")
    f_item_b = font(28, "Semibold")
    f_meta = font(21, "Regular")
    f_mono = font(20, "Regular", mono=True)
    f_foot = font(20, "Bold", mono=True)

    # window
    wx, wy, ww, wh = 70, 60, W - 140, 660
    d.rounded_rectangle([wx, wy, wx + ww, wy + wh], radius=16, fill=CARD, outline=BORDER_STRONG)
    d.rounded_rectangle([wx, wy, wx + ww, wy + 62], radius=16, fill=ELEV)
    d.rectangle([wx, wy + 46, wx + ww, wy + 62], fill=ELEV)
    d.line([(wx, wy + 62), (wx + ww, wy + 62)], fill=BORDER_STRONG, width=1)
    for i, c in enumerate(((255, 95, 87), (254, 188, 46), (40, 200, 64))):
        d.ellipse([wx + 22 + i * 26, wy + 22, wx + 40 + i * 26, wy + 40], fill=c)
    d.text((wx + 130, wy + 19), "Video settings  ·  Camera", font=f_title, fill=MUTED)

    # left: camera picker
    lx, ly = wx + 46, wy + 110
    d.text((lx, ly), "Camera", font=f_lbl, fill=MUTED)

    items = [
        ("FaceTime HD Camera", False),
        ("TetherCam", True),
        ("OBS Virtual Camera", False),
    ]
    iy = ly + 48
    box_w = 560
    d.rounded_rectangle([lx, iy, lx + box_w, iy + 46 + len(items) * 68], radius=10,
                        fill=ELEV, outline=BORDER_STRONG)
    row = iy + 22
    for name, selected in items:
        if selected:
            d.rounded_rectangle([lx + 10, row - 8, lx + box_w - 10, row + 52], radius=8,
                                fill=(31, 28, 56), outline=ACCENT)
            # check mark
            d.line([(lx + 28, row + 22), (lx + 40, row + 34), (lx + 62, row + 8)],
                   fill=ACCENT, width=5, joint="curve")
            d.text((lx + 82, row + 6), name, font=f_item_b, fill=FG)
            d.text((lx + 82 + d.textlength(name, font=f_item_b) + 18, row + 12),
                   "iPhone over USB", font=f_meta, fill=ACCENT)
        else:
            d.text((lx + 82, row + 6), name, font=f_item, fill=MUTED)
        row += 68

    d.text((lx, iy + 46 + len(items) * 68 + 34),
           "Pick \"TetherCam\" in Zoom, Microsoft Teams, Google Meet,", font=f_meta, fill=MUTED)
    d.text((lx, iy + 46 + len(items) * 68 + 66),
           "FaceTime, QuickTime Player, Safari or Chrome.", font=f_meta, fill=MUTED)

    # right: preview
    px, py, pw = wx + 660, wy + 110, ww - 706
    ph = int(pw * 9 / 16)
    d.rounded_rectangle([px - 2, py - 2, px + pw + 2, py + ph + 2], radius=10, outline=BORDER_STRONG)
    scene = Image.open(SCENE).convert("RGB")
    sw, sh = scene.size
    scale = max(pw / sw, ph / sh)
    scene = scene.resize((int(sw * scale) + 1, int(sh * scale) + 1), Image.LANCZOS)
    left = (scene.width - pw) // 2
    top = (scene.height - ph) // 2
    scene = scene.crop((left, top, left + pw, top + ph))
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=8, fill=255)
    im.paste(scene, (px, py), mask)

    # status capsule on the preview
    d.rounded_rectangle([px + 20, py + 20, px + 300, py + 62], radius=21, fill=(11, 12, 16))
    d.ellipse([px + 36, py + 34, px + 50, py + 48], fill=SIGNAL)
    d.text((px + 62, py + 30), "Streaming 1080p30", font=f_meta, fill=FG)

    d.text((px, py + ph + 26), "Live preview from the iPhone, 1920x1080 at 30 fps",
           font=f_meta, fill=MUTED)
    d.text((px, py + ph + 58), "usb-c · tcp 7878 · hevc, hardware", font=f_mono, fill=MUTED)

    # footer
    tracked(d, (70, wy + wh + 52), "TETHERCAM.APP  ·  THE MAC APP", f_foot, MUTED, 2.4)

    im.save(os.path.join(OUT, "mac-app-zoom.png"), optimize=True)
    return im.size


if __name__ == "__main__":
    print("og.png", build_og())
    print("mac-app-zoom.png", build_mac_app())
