"""Imports the props of the CraftPix "2D Top-Down Dungeon Tileset" into assets/tiles/crypt/ (decor_1 ... decor_42: a
gravestone slab, dead branches, ruined walls, a stone archway, traps, a key...), from the pack on the NAS (Tainted >
assets > maps). Maps borrow them by "crypt/<name>" (MapTheme): the Ashen Verge's headstones and branches now, and the
Grand Ossuary's own theme (walls, floors) is built on this folder later.

Usage:  python tools/import_crypt.py [--src <folder with the zip>]
"""
import argparse
import os
import zipfile

from PIL import Image

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "assets", "tiles", "crypt")
SRC = "Y:/Tainted/assets/maps"
ZIP = "craftpix-891134-2d-top-down-dungeon-tileset.zip"


def red(im, shift=-88):
    """`im` with its hues turned from green to blood red (shift in 0..255 hue units, wrapping)."""
    rgba = im.convert("RGBA")
    hsv = rgba.convert("RGB").convert("HSV")
    h, s_, v = hsv.split()
    h = h.point(lambda x: (x + shift) % 256)
    out = Image.merge("HSV", (h, s_, v)).convert("RGB").convert("RGBA")
    out.putalpha(rgba.getchannel("A"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    count = 0
    with zipfile.ZipFile(os.path.join(args.src, ZIP)) as z:
        for n in z.namelist():
            base = os.path.basename(n).lower()
            if n.startswith("PNG/") and base.endswith(".png") and (base.startswith("decor_") or base.startswith("stones_")):
                with open(os.path.join(OUT, base), "wb") as f:
                    f.write(z.read(n))
                count += 1
            elif base in ("license.txt", "readme.txt") and n.upper().startswith("TXT/"):
                with open(os.path.join(OUT, "LICENSE_craftpix.txt" if "license" in base else "README_craftpix.txt"), "wb") as f:
                    f.write(z.read(n))
    print("imported", count, "pictures into", OUT)
    # Bleed Rift dressing: the cave pack's green crystals and the dungeon's green slime puddles turned red
    hollow = os.path.join(HERE, "..", "assets", "tiles", "hollow")
    made = 0
    for out_name, src in [("rift_1", os.path.join(hollow, "crystal_1.png")), ("rift_2", os.path.join(hollow, "crystal_5.png")),
                          ("rift_3", os.path.join(hollow, "crystal_9.png")), ("blood_1", os.path.join(OUT, "decor_26.png")),
                          ("blood_2", os.path.join(OUT, "decor_27.png")), ("blood_3", os.path.join(OUT, "decor_28.png"))]:
        if os.path.exists(src):
            red(Image.open(src), -72 if out_name.startswith("blood") else -88).save(os.path.join(OUT, out_name + ".png"))
            made += 1
    print("recoloured", made, "pictures red")


if __name__ == "__main__":
    main()
