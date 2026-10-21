"""Makes the dye icons from the CraftPix 50 free RPG paint icons pack (craftpix-net-500794):

  assets/icons/paints/<dye id>.png  - 128 x 128, the paint bottle cropped to its picture and centred

DYES maps a dye id (scripts/dye_db.gd) to a bottle in the pack's PNG/without background folder. The
pack lays its bottles out ten colours across (red, green, blue, black, white, yellow, pink, purple,
orange, cyan) in rows of three shades: bright (1-10), deep (11-20) and muted (21-30); the rest are
the same paints in crates and barrels, not used.

Usage:  python tools/import_paints.py <craftpix-net-500794-50-free-rpg-paint-icons.zip>
"""
import io
import os
import sys
import zipfile

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons", "paints")
SIZE = 128

DYES = {
    "crimson": 1, "emerald": 2, "sapphire": 3, "jet": 4, "ivory": 5,
    "sunflower": 6, "rose": 7, "amethyst": 8, "tangerine": 9, "cyan": 10,
    "blood": 11, "forest": 12, "navy": 13, "onyx": 14, "silver": 15,
    "amber": 16, "ruby": 17, "violet": 18, "ember": 19, "teal": 20,
    "brick": 21, "moss": 22, "steel": 23, "charcoal": 24, "ash": 25,
    "olive": 26, "dusty_rose": 27, "indigo": 28, "copper": 29, "sea": 30,
}


def fit(im, size):
    """`im` cropped to its picture and centred in a size x size canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = (size * 0.96) / max(im.width, im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size))
    out.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    z = zipfile.ZipFile(sys.argv[1])
    os.makedirs(ROOT, exist_ok=True)
    for did, n in DYES.items():
        im = Image.open(io.BytesIO(z.read("PNG/without background/%d.png" % n))).convert("RGBA")
        fit(im, SIZE).save(os.path.join(ROOT, did + ".png"))
    print("wrote %d paint icons under %s" % (len(DYES), os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
