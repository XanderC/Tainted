"""Imports the props of the CraftPix "2D Top-Down Dungeon Tileset" into assets/tiles/crypt/ (decor_1 ... decor_42: a
gravestone slab, dead branches, ruined walls, a stone archway, traps, a key...), from the pack on the NAS (Tainted >
assets > maps). Maps borrow them by "crypt/<name>" (MapTheme): the Ashen Verge's headstones and branches now, and the
Grand Ossuary's own theme (walls, floors) is built on this folder later.

The same folder is the `crypt` map theme (the Grand Ossuary's catacombs): the pack's own floor (bg.png) and the wall pieces
WallTiles draws any wall with (walls/), made the way tools/import_cave.py makes the cave's (the two packs share their wall art:
a row of light cap stones over a cobble face, dark void behind), plus torch_1 and lantern_1 (the pack's torch holders, lit).

Usage:  python tools/import_crypt.py [--src <folder with the zip>]
"""
import argparse
import math
import os
import random
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

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


SIZE = 256
CAP = 64  # the cap stones' depth (the pack's wall_4 is 256 x 64)


def over(base, piece, x, y):
    out = base.copy()
    out.alpha_composite(piece, (x, y))
    return out


def flame(holder, core, rim, glow):
    """A torch holder (PIL RGBA, standing on its foot) with a flame over its cup, and a soft glow round it."""
    w, h = holder.size
    pad = 70
    canvas = Image.new("RGBA", (w + 2 * pad, h + pad + 20), (0, 0, 0, 0))
    cx, cy = canvas.width // 2, pad - 6
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(halo)
    d.ellipse((cx - 58, cy - 62, cx + 58, cy + 54), fill=glow + (70,))
    halo = halo.filter(ImageFilter.GaussianBlur(16))
    canvas.alpha_composite(halo)
    canvas.alpha_composite(holder, (pad, pad - 4))
    f = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(f)
    d.polygon([(cx - 15, cy + 6), (cx - 9, cy - 22), (cx - 2, cy - 12), (cx + 2, cy - 44), (cx + 10, cy - 18), (cx + 17, cy - 8), (cx + 14, cy + 8)], fill=rim + (255,))
    d.polygon([(cx - 9, cy + 6), (cx - 3, cy - 14), (cx + 1, cy - 26), (cx + 5, cy - 10), (cx + 10, cy + 6)], fill=core + (255,))
    canvas.alpha_composite(f.filter(ImageFilter.GaussianBlur(0.8)))
    return canvas


def walls(z, out):
    """The wall pieces and the floor of the crypt theme (as tools/import_cave.py makes the cave's)."""
    def load(name):
        return Image.open(__import__("io").BytesIO(z.read("PNG/%s.png" % name))).convert("RGBA")
    land, cap_h, cap_v, cap_corner, bricks, slab = load("land"), load("wall_4"), load("wall_3"), load("wall_9"), load("wall_8"), load("wall_1")
    land.save(os.path.join(out, "bg.png"))
    os.makedirs(os.path.join(out, "walls"), exist_ok=True)
    texture = np.asarray(land.convert("RGB")).astype(np.float32)
    void = Image.fromarray((texture * 0.14 + np.array([7, 7, 10], np.float32)).clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")
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
            p = over(p, cap_corner, 0 if corner.endswith("l") else SIZE - CAP, 0 if corner.startswith("t") else SIZE - CAP)
        return p

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
        img.save(os.path.join(out, "walls", name + ".png"))
    print("crypt: floor and %d wall pieces" % len(pieces))


def make_veil_rift(out):
    """veil_rift.png: the great torn rift in the Sepulcher's altar wall: a jagged slit of black-violet with a blood-red edge and a glow."""
    rng = random.Random(77)
    w, h = 420, 640
    cx = w // 2
    left, right = [], []
    for i in range(0, 33):
        y = 30 + i * (h - 60) / 32.0
        t = i / 32.0
        width = 30 + 78 * math.sin(math.pi * t) ** 0.8
        jag = rng.uniform(-14, 14)
        left.append((cx - width / 2 + jag, y))
        right.append((cx + width / 2 + rng.uniform(-14, 14), y))
    poly = left + right[::-1]
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(poly, fill=(255, 40, 70, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(26))
    glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.8)))
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    d.polygon(poly, fill=(14, 0, 24, 255))
    inner = [(cx + (x - cx) * 0.62, y) for x, y in poly]
    d.polygon(inner, fill=(40, 4, 60, 255))
    d.polygon([(cx + (x - cx) * 0.3, y) for x, y in poly], fill=(110, 12, 70, 255))
    d.line(poly + [poly[0]], fill=(255, 90, 110, 255), width=5)
    d.line(poly + [poly[0]], fill=(255, 220, 220, 255), width=1)
    for _ in range(14):  # cracks running out of it
        side = rng.choice([-1, 1])
        y = rng.uniform(60, h - 60)
        x = cx + side * rng.uniform(50, 70)
        pts = [(x, y)]
        for _ in range(4):
            x += side * rng.uniform(12, 30)
            y += rng.uniform(-22, 22)
            pts.append((x, y))
        d.line(pts, fill=(255, 70, 90, 220), width=2)
    img.save(os.path.join(out, "veil_rift.png"))


def make_glass(out):
    """glass_1..3.png: tall stained-glass windows with panes missing, and glass_shard_1..3.png for the floor beneath them."""
    palettes = [[(40, 80, 170), (150, 30, 40), (200, 150, 40)], [(150, 30, 40), (90, 40, 140), (40, 120, 110)],
                [(200, 150, 40), (40, 80, 170), (150, 30, 40)]]
    for n, pal in enumerate(palettes, 1):
        rng = random.Random(n * 13)
        w, h = 200, 330
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        arch = [(x, h - 4) for x in (14, w - 14)]
        d.rounded_rectangle((8, 8, w - 8, h - 2), radius=92, fill=(92, 92, 100, 255))
        d.rounded_rectangle((22, 22, w - 22, h - 14), radius=78, fill=(22, 18, 26, 255))
        cols, rows = 4, 7
        cw, ch = (w - 48) / cols, (h - 52) / rows
        for r in range(rows):
            for c in range(cols):
                x0, y0 = 24 + c * cw, 26 + r * ch
                if rng.random() < 0.3:  # a pane gone: the dark shows through
                    continue
                col = rng.choice(pal)
                shade = rng.uniform(0.6, 1.0)
                col = tuple(int(v * shade) for v in col) + (255,)
                if (x0 - w / 2 + cw / 2) ** 2 / (w / 2 - 26) ** 2 + (y0 - 100 + ch) ** 2 / 90 ** 2 > 1.0 and y0 < 100:
                    continue  # out of the arch's curve
                d.rectangle((x0 + 2, y0 + 2, x0 + cw - 2, y0 + ch - 2), fill=col)
        for c in range(cols + 1):
            d.line((24 + c * cw, 22, 24 + c * cw, h - 14), fill=(50, 50, 56, 255), width=3)
        for r in range(rows + 1):
            d.line((24, 26 + r * ch, w - 24, 26 + r * ch), fill=(50, 50, 56, 255), width=3)
        d.rounded_rectangle((8, 8, w - 8, h - 2), radius=92, outline=(150, 150, 160, 255), width=4)
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle((8, 8, w - 8, h - 2), radius=92, fill=255)
        img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (w, h), 0), mask))
        img.save(os.path.join(out, "glass_%d.png" % n))
        shard = Image.new("RGBA", (40, 34), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shard)
        for _ in range(5):
            x, y = rng.randint(4, 30), rng.randint(4, 24)
            col = rng.choice(pal) + (230,)
            sd.polygon([(x, y), (x + rng.randint(5, 10), y + rng.randint(-3, 3)), (x + rng.randint(1, 6), y + rng.randint(5, 9))], fill=col)
        shard.save(os.path.join(out, "glass_shard_%d.png" % n))


def make_river(out):
    """river.png and river_2.png: the cave pack's lake (assets/tiles/hollow) as coagulated blood, for the Sepulcher's flooded floor."""
    hollow = os.path.join(HERE, "..", "assets", "tiles", "hollow")
    for name in ("river", "river_2"):
        src = os.path.join(hollow, name + ".png")
        if os.path.exists(src):
            im = red(Image.open(src), -72)
            r, g, b, a = im.split()
            r, g, b = (ch.point(lambda v: int(v * 0.62)) for ch in (r, g, b))
            Image.merge("RGBA", (r, g, b, a)).save(os.path.join(out, name + ".png"))


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
    with zipfile.ZipFile(os.path.join(args.src, ZIP)) as z:
        walls(z, OUT)
    make_veil_rift(OUT)
    make_glass(OUT)
    make_river(OUT)
    # Torches (orange) and soul lanterns (cold blue-white): the pack's holders, lit
    flame(Image.open(os.path.join(OUT, "decor_29.png")), (255, 236, 150), (255, 140, 40), (255, 150, 60)).save(os.path.join(OUT, "torch_1.png"))
    lantern = flame(red(Image.open(os.path.join(OUT, "decor_30.png")), 100), (230, 255, 255), (90, 200, 255), (80, 190, 255))
    lantern.save(os.path.join(OUT, "lantern_1.png"))
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
