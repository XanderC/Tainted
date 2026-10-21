"""Makes the flask icons from the CraftPix RPG potion icons pack (craftpix-net-789213-rpg-potion-icons):

  assets/gear/flask/<id>/icon.png  - 160 x 160, the potion cropped to its picture and centred,
                                     used in the bag, the merchant's wares and the HUD flask bar

ART maps a flask base (LootGenerator._build_bases) to a potion in the pack's PNG/without background
folder: life flasks are the red ones, power flasks orange, small to large as the bottles get grander;
the utility flasks take the potion that matches their colour.

Usage:  python tools/import_potions.py <craftpix-net-789213-rpg-potion-icons.zip>
"""
import io
import os
import sys
import zipfile

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "gear", "flask")
SIZE = 160

ART = {
    "small_life_flask": 34, "medium_life_flask": 22, "large_life_flask": 41,
    "small_power_flask": 36, "medium_power_flask": 24, "large_power_flask": 40,
    "granite_flask": 33, "quicksilver_flask": 37, "silver_flask": 30, "sulphur_flask": 38,
}


def fit(im, size):
    """`im` cropped to its picture and centred in a size x size canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = (size * 0.94) / max(im.width, im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size))
    out.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    z = zipfile.ZipFile(sys.argv[1])
    for fid, n in ART.items():
        im = Image.open(io.BytesIO(z.read("PNG/without background/%d.png" % n))).convert("RGBA")
        d = os.path.join(ROOT, fid)
        os.makedirs(d, exist_ok=True)
        fit(im, SIZE).save(os.path.join(d, "icon.png"))
    print("wrote %d flask icons under %s" % (len(ART), os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
