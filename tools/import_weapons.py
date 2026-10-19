"""Makes the weapon and shield art from the CraftPix weapon packs (axes, swords, sabres, cudgels,
daggers, spears, staves, shields: 8 designs each in 5 grades, crude to ornate):

  assets/gear/weapon/<id>/Sword.png    - in the hand: the pack image as it is (400 x 128, the size
                                         and grip of the rig's own sword)
  assets/gear/weapon/<id>/icon.png     - in the bag: the same image turned to fit the item's cells
                                         (upright in a one-cell-wide space, diagonal in a wider one)
  assets/gear/offhand/<id>/Shield.png and icon.png for shields

ART maps a base id (LootGenerator.WEAPON_BASES) to (pack folder, grade) and its bag size.

Usage:  python tools/import_weapons.py <folder with the weapon pack zips>
"""
import io
import os
import sys
import zipfile

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "gear")
CELL = 96  # icon pixels per bag cell

# id: (folder in the pack, grade 1-5, bag cells (w, h))
ART = {
    "rusty_sword": ("Sword_1", 1, (1, 3)), "copper_sword": ("Sword_8", 2, (1, 3)),
    "sabre": ("Saber_1", 2, (1, 3)), "broad_sword": ("Sword_4", 3, (1, 3)),
    "cutlass": ("Saber_4", 3, (1, 3)), "war_sword": ("Sword_2", 4, (1, 3)),
    "corsair_sabre": ("Saber_7", 4, (1, 3)), "eternal_sword": ("Sword_1", 5, (1, 3)),
    "greatsword": ("Sword_3", 1, (2, 4)), "bastard_sword": ("Sword_6", 2, (2, 4)),
    "executioner_blade": ("Sword_5", 3, (2, 4)), "reaver_blade": ("Sword_6", 5, (2, 4)),
    "hand_axe": ("Axe_3", 1, (1, 3)), "tomahawk": ("Axe_4", 2, (1, 3)),
    "boarding_axe": ("Axe_7", 3, (1, 3)), "jade_hatchet": ("Axe_2", 4, (1, 3)),
    "runic_hatchet": ("Axe_8", 5, (1, 3)),
    "battle_axe": ("Axe_8", 1, (2, 3)), "double_axe": ("Axe_1", 2, (2, 3)),
    "poleaxe": ("Axe_5", 3, (2, 3)), "labrys": ("Axe_1", 5, (2, 3)), "despot_axe": ("Axe_6", 5, (2, 3)),
    "iron_mace": ("Cudgels_1", 1, (1, 3)), "spiked_club": ("Cudgels_3", 3, (1, 3)),
    "flanged_mace": ("Cudgels_6", 2, (1, 3)), "morning_star": ("Cudgels_5", 4, (1, 3)),
    "dragon_mace": ("Cudgels_4", 5, (1, 3)),
    "war_maul": ("Cudgels_8", 1, (2, 4)), "great_club": ("Cudgels_2", 2, (2, 4)),
    "spiked_maul": ("Cudgels_7", 3, (2, 4)), "colossus_mallet": ("Cudgels_7", 5, (2, 4)),
    "wooden_spear": ("Spear_1", 1, (1, 4)), "hunting_spear": ("Spear_6", 2, (1, 4)),
    "harpoon": ("Spear_5", 3, (1, 4)), "war_spear": ("Spear_7", 4, (1, 4)), "dragon_spear": ("Spear_8", 5, (1, 4)),
    "dagger": ("Dagger_1", 1, (1, 2)), "kris": ("Dagger_5", 2, (1, 2)),
    "stiletto": ("Dagger_6", 3, (1, 2)), "skean": ("Dagger_8", 5, (1, 2)),
    "oak_staff": ("Staves_1", 1, (1, 4)), "quarterstaff": ("Staves_6", 2, (1, 4)),
    "serpent_staff": ("Staves_4", 3, (1, 4)), "crystal_staff": ("Staves_8", 4, (1, 4)), "void_staff": ("Staves_5", 5, (1, 4)),
    "wooden_shield": ("Shield_1", 1, (2, 2)), "buckler": ("Shield_3", 2, (2, 2)),
    "kite_shield": ("Shield_8", 3, (2, 2)), "tower_shield": ("Shield_6", 3, (2, 3)),
    "heater_shield": ("Shield_2", 4, (2, 2)), "spiked_shield": ("Shield_5", 4, (2, 2)),
    "gilded_aegis": ("Shield_7", 5, (2, 2)),
}
PACK_OF = {"Sword": "swords", "Saber": "saber", "Axe": "axes", "Cudgels": "cudgels",
           "Dagger": "dagger", "Spear": "spear", "Staves": "staves", "Shield": "shield"}


def fit(im, w, h):
    """`im` cropped to its picture and centred in a w x h canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = min((w * 0.92) / im.width, (h * 0.92) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def bag_icon(weapon, cells):
    w, h = cells[0] * CELL, cells[1] * CELL
    if cells[0] == 1:
        turned = weapon.rotate(90, expand=True, resample=Image.BICUBIC)  # handle down, blade up
    else:
        turned = weapon.rotate(55, expand=True, resample=Image.BICUBIC)  # handle low left, blade high right
    return fit(turned, w, h)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    zips = [z for z in os.listdir(src) if z.endswith(".zip")]
    opened = {}
    for bid, (folder, grade, cells) in ART.items():
        kind = folder.split("_")[0]
        key = PACK_OF[kind]
        if key not in opened:
            found = [z for z in zips if key in z]
            if len(found) != 1:
                sys.exit("%d zips match %r" % (len(found), key))
            opened[key] = zipfile.ZipFile(os.path.join(src, found[0]))
        im = Image.open(io.BytesIO(opened[key].read("PNG/%s/%d.png" % (folder, grade)))).convert("RGBA")
        shield = kind == "Shield"
        d = os.path.join(ROOT, "offhand" if shield else "weapon", bid)
        os.makedirs(d, exist_ok=True)
        if shield:
            im.save(os.path.join(d, "Shield.png"))
            fit(im, cells[0] * CELL, cells[1] * CELL).save(os.path.join(d, "icon.png"))
        else:
            im.save(os.path.join(d, "Sword.png"))
            bag_icon(im, cells).save(os.path.join(d, "icon.png"))
    print("wrote %d weapons and shields under %s" % (len(ART), os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
