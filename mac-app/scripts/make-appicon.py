#!/usr/bin/env python3
"""Regenerates mac-app/App/Assets.xcassets/AppIcon.appiconset from the 1024 px
master in docs/images/tethercam-icon-1024.png with `sips`.

Run from the repo root: python3 mac-app/scripts/make-appicon.py
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "docs/images/tethercam-icon-1024.png")
OUT = os.path.join(ROOT, "mac-app/App/Assets.xcassets/AppIcon.appiconset")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    images = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size * scale
            name = "icon_%dx%d%s.png" % (size, size, "@2x" if scale == 2 else "")
            subprocess.run(["sips", "-z", str(px), str(px), SRC, "--out", os.path.join(OUT, name)],
                           check=True, capture_output=True)
            images.append({"idiom": "mac", "size": "%dx%d" % (size, size),
                           "scale": "%dx" % scale, "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as fh:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, fh, indent=2)
    catalog = os.path.join(ROOT, "mac-app/App/Assets.xcassets/Contents.json")
    with open(catalog, "w") as fh:
        json.dump({"info": {"version": 1, "author": "xcode"}}, fh, indent=2)
    print("wrote %d icons to %s" % (len(images), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
