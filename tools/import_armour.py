"""Makes body armour, gloves and boots from the character packs' own clothes (assets/skins/<skin>):
a skin's body and arms are a suit of armour, its hands a pair of gloves, its legs a pair of boots.

  assets/gear/chest/<id>/Body.png, Left Arm.png, Right Arm.png  - worn: the skin's parts as they are
  assets/gear/gloves/<id>/Left Hand.png, Right Hand.png           (same canvases as the rig's parts,
  assets/gear/boots/<id>/Left Leg.png, Right Leg.png               so they sit exactly on a character)
  assets/gear/<slot>/<id>/icon.png  - in the bag: the parts as they sit in the idle pose (tools/rig_pose.py),
                                      fitted into the item's cells (armour 2 x 3, gloves and boots 2 x 2)

The tables map a base (LootGenerator CHEST_BASES, GLOVE_BASES, BOOT_BASES) to the skin it comes from,
plainest first. Only the zombie rig's skins (480 px heads) are used; the archers are another rig.

Usage:  python tools/import_armour.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from rig_pose import compose  # noqa: E402

HERE = os.path.dirname(__file__)
SKINS = os.path.join(HERE, "..", "assets", "skins")
ROOT = os.path.join(HERE, "..", "assets", "gear")
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)

CHEST = {
    "linen_robe": "sage",
    "padded_vest": "merchant",
    "leather_jerkin": "forest_ranger_3",
    "chain_mail": "skeleton_crusader_2",
    "studded_leather": "stash_keeper",
    "brigandine": "caravan_guard",
    "crusader_hauberk": "skeleton_crusader_1",
    "scale_mail": "skeleton_warrior_2",
    "battle_plate": "battlemaster",
    "shadow_mail": "dark_elf_1",
    "frost_plate": "ghost_knight",
    "demon_plate": "blood_demon",
    "death_plate": "death_knight",
}
GLOVES = {
    "linen_wraps": "mummy",
    "leather_gloves": "forest_ranger_3",
    "heavy_gloves": "battlemaster",
    "iron_gauntlets": "caravan_guard",
    "frost_gauntlets": "ghost_knight",
    "death_gauntlets": "blood_demon",
}
BOOTS = {
    "worn_boots": "zombie_villager_1",
    "leather_boots": "forest_ranger_3",
    "riding_boots": "stash_keeper",
    "chain_boots": "skeleton_crusader_2",
    "plated_boots": "caravan_guard",
    "frost_greaves": "ghost_knight",
    "death_greaves": "death_knight",
}
KINDS = [
    ("chest", CHEST, ["Body", "Left Arm", "Right Arm"], (2, 3)),
    ("gloves", GLOVES, ["Left Hand", "Right Hand"], (2, 2)),
    ("boots", BOOTS, ["Left Leg", "Right Leg"], (2, 2)),
]


def fit(im, w, h):
    """`im` cropped to its picture and centred in a w x h canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = min((w * 0.9) / im.width, (h * 0.9) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def pair(left, right, gap=6):
    """A pair side by side (gloves, boots): the near one a little in front, as you'd lay them out."""
    l, r = left.crop(left.getbbox()), right.crop(right.getbbox())
    out = Image.new("RGBA", (l.width + r.width + gap, max(l.height, r.height)))
    out.alpha_composite(r, (0, out.height - r.height))
    out.alpha_composite(l, (r.width + gap, out.height - l.height))
    return out


def main():
    n = 0
    for slot, table, parts, cells in KINDS:
        for gid, skin in table.items():
            imgs = {p: Image.open(os.path.join(SKINS, skin, p + ".png")).convert("RGBA") for p in parts}
            d = os.path.join(ROOT, slot, gid)
            os.makedirs(d, exist_ok=True)
            for p, im in imgs.items():
                im.save(os.path.join(d, p + ".png"))
            icon = compose(imgs) if slot == "chest" else pair(imgs[parts[0]], imgs[parts[1]])
            fit(icon, cells[0] * CELL, cells[1] * CELL).save(os.path.join(d, "icon.png"))
            n += 1
    print("wrote %d pieces of armour under %s" % (n, os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
