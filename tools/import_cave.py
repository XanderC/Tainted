"""Imports the CraftPix "2D Top-Down Cave Tileset" as the `hollow` map theme (assets/tiles/hollow/), from the pack on the NAS
(Tainted > assets > maps), for the Weeping Hollow and, later, the Grand Ossuary's catacombs.

This pack is not laid out like the "2D RPG" ones (tools/import_tilesets.py): it is a stone-brick dungeon with a toxic
slime lake. Its walls are slabs seen from the front: a row of light cap stones over a brick face. This makes from them the
same wall pieces WallTiles draws any wall with (assets/tiles/hollow/walls/): a wall's mass is dark void, its edges are
rimmed with the cap stones, the row that faces the floor below it is the brick face, and a wall one cell thick is the
pack's own cap-and-bricks piece. Also:
  bg.png             the floor (the pack's `land`)
  river.png, river_2.png   the pack's slime lake, for MazeMap's rivers (the theme tints it dark: MapTheme `water_tint`)
  everything else    the pack's props by their own names (crystal_N, bone_N, decor_N, greenery_N, stones_N, rune_N)

Usage:  python tools/import_cave.py [--src <folder with the zip>]
"""
import argparse
import io
import os
import zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "assets", "tiles", "hollow")
SRC = "Y:/Tainted/assets/maps"
ZIP = "craftpix-net-189613-2d-top-down-cave-tileset.zip"
SIZE = 256
CAP = 64  # the cap stones' depth (the pack's wall_4 is 256 x 64)


def load(z, name):
    return Image.open(io.BytesIO(z.read("PNG/%s.png" % name))).convert("RGBA")


def over(base, piece, x, y):
    """`piece` composited onto `base` (both PIL RGBA) at (x, y)."""
    out = base.copy()
    out.alpha_composite(piece, (x, y))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    args = ap.parse_args()
    os.makedirs(os.path.join(OUT, "walls"), exist_ok=True)
    with zipfile.ZipFile(os.path.join(args.src, ZIP)) as z:
        for n in z.namelist():
            base = os.path.basename(n)
            if n.startswith("PNG/") and base.endswith(".png") and not base.startswith("2D_Top_Down"):
                with open(os.path.join(OUT, base.lower()), "wb") as f:
                    f.write(z.read(n))
            elif n.upper().startswith("TXT/") and base.lower() in ("license.txt", "readme.txt"):
                with open(os.path.join(OUT, "LICENSE_craftpix.txt" if "license" in base.lower() else "README_craftpix.txt"), "wb") as f:
                    f.write(z.read(n))
        land, lake = load(z, "land"), load(z, "lake")
        cap_h, cap_v, cap_corner = load(z, "wall_4"), load(z, "wall_3"), load(z, "wall_10")
        bricks, slab = load(z, "wall_8"), load(z, "wall_1")
    land.save(os.path.join(OUT, "bg.png"))
    lake.save(os.path.join(OUT, "river.png"))
    lake.save(os.path.join(OUT, "river_2.png"))

    # The wall mass: dark void, with the floor's stones faintly in it
    texture = np.asarray(land.convert("RGB")).astype(np.float32)
    void = Image.fromarray((texture * 0.16 + np.array([6, 9, 8], np.float32)).clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")
    cap_h = cap_h.crop((0, 0, SIZE, CAP))
    cap_v = cap_v.crop((0, 0, CAP, SIZE))
    flip_v = cap_v.transpose(Image.FLIP_LEFT_RIGHT)

    def piece(top=False, bottom=False, left=False, right=False, notch=""):
        p = void.copy()
        if top:
            p = over(p, cap_h, 0, 0)
        if bottom:
            p = over(p, cap_h, 0, SIZE - CAP)
        if left:
            p = over(p, cap_v, 0, 0)
        if right:
            p = over(p, flip_v, SIZE - CAP, 0)
        for corner in notch:
            p = over(p, cap_corner, 0 if corner in "tl bl".split() or corner.endswith("l") else SIZE - CAP, 0 if corner.startswith("t") else SIZE - CAP)
        return p

    walls = os.path.join(OUT, "walls")
    pieces = {
        "middle": piece(),
        "top": piece(top=True), "lip": piece(bottom=True), "left": piece(left=True), "right": piece(right=True),
        "top_left": piece(top=True, left=True), "top_right": piece(top=True, right=True),
        "lip_left": piece(bottom=True, left=True), "lip_right": piece(bottom=True, right=True),
        "inner_tl": piece(notch=["tl"]), "inner_tr": piece(notch=["tr"]), "inner_bl": piece(notch=["bl"]), "inner_br": piece(notch=["br"]),
        "cliff": bricks, "cliff_left": bricks, "cliff_right": bricks,
        "ledge": slab, "ledge_left": slab, "ledge_right": slab,
    }
    for name, img in pieces.items():
        img.save(os.path.join(walls, name + ".png"))
    print("hollow: %d props, %d wall pieces" % (len([f for f in os.listdir(OUT) if f.endswith(".png")]), len(pieces)))


if __name__ == "__main__":
    main()
