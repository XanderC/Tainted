"""Makes the `ashen` map theme's own pictures (assets/tiles/ashen/) from the woodland's: the Ashen Verge is the autumn woods
burnt out, so its ground, paths, walls and terraces are the woodland's with the colour drained to ash and the light dimmed.
Every other picture a map of this theme asks for (dead trees, stumps, stones, signposts) falls back on the woodland folder
(MapTheme "art").

Usage:  python tools/import_ashen.py        (needs assets/tiles/woodland; run tools/import_tilesets.py first if it is missing)
"""
import os

from PIL import Image, ImageEnhance

HERE = os.path.dirname(__file__)
TILES = os.path.join(HERE, "..", "assets", "tiles")
SRC = os.path.join(TILES, "woodland")
OUT = os.path.join(TILES, "ashen")
COLOR = 0.18       # 0 = grey, 1 = as it was
LIGHT = 0.80
WARM = (1.04, 1.0, 0.95)  # a touch of soot-brown over the grey


def ash(im):
    rgba = im.convert("RGBA")
    r, g, b, a = rgba.split()
    rgb = Image.merge("RGB", (r, g, b))
    rgb = ImageEnhance.Color(rgb).enhance(COLOR)
    rgb = ImageEnhance.Brightness(rgb).enhance(LIGHT)
    r, g, b = rgb.split()
    r = r.point(lambda v: min(255, int(v * WARM[0])))
    g = g.point(lambda v: min(255, int(v * WARM[1])))
    b = b.point(lambda v: min(255, int(v * WARM[2])))
    return Image.merge("RGBA", (r, g, b, a))


def main():
    count = 0
    for sub in ("", "walls", "terrace"):
        src_dir = os.path.join(SRC, sub)
        out_dir = os.path.join(OUT, sub)
        os.makedirs(out_dir, exist_ok=True)
        for name in sorted(os.listdir(src_dir)):
            if not name.endswith(".png"):
                continue
            if sub == "" and not (name == "bg.png" or name.startswith("road_") or name.startswith("land_")):
                continue
            ash(Image.open(os.path.join(src_dir, name))).save(os.path.join(out_dir, name))
            count += 1
    print("made", count, "pictures in", OUT)


if __name__ == "__main__":
    main()
