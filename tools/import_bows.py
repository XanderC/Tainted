"""Makes the bow art from the archer characters' own bows (assets/skins/<skin>/Bow.png): there are
no bows in the weapon packs, but every archer skin draws one, from a plain stave to gilded.

  assets/gear/weapon/<id>/Bow.png   - in the hand: the skin's image as it is, so a Desert Scout
                                      hireling (on the archer rig) holds the bow it has equipped
  assets/gear/weapon/<id>/icon.png  - in the bag: fitted upright into its 2 x 3 cells

ART maps a bow base (LootGenerator.WEAPON_BASES) to the skin whose bow it uses, plainest first.

Usage:  python tools/import_bows.py
"""
import os

from PIL import Image

HERE = os.path.dirname(__file__)
SKINS = os.path.join(HERE, "..", "assets", "skins")
ROOT = os.path.join(HERE, "..", "assets", "gear", "weapon")
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)
CELLS = (2, 3)

ART = {
    "hunting_bow": "skeleton_archer_1",
    "short_bow": "forest_ranger_1",
    "recurve_bow": "elf_archer_2",
    "composite_bow": "forest_ranger_2",
    "long_bow": "archer_2",
    "war_bow": "skeleton_hunter_3",
    "serpent_bow": "archer_3",
    "moonlit_bow": "undead_archer_2",
    "gilded_warbow": "archer_guy",
}


def fit(im, w, h):
    """`im` cropped to its picture and centred in a w x h canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = min((w * 0.92) / im.width, (h * 0.92) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def main():
    for bid, skin in ART.items():
        im = Image.open(os.path.join(SKINS, skin, "Bow.png")).convert("RGBA")
        d = os.path.join(ROOT, bid)
        os.makedirs(d, exist_ok=True)
        im.save(os.path.join(d, "Bow.png"))
        fit(im, CELLS[0] * CELL, CELLS[1] * CELL).save(os.path.join(d, "icon.png"))
    print("wrote %d bows under %s" % (len(ART), os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
