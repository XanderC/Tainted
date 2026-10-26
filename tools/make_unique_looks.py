"""Makes the Legendary and Set items' own looks (UniqueItems.look_of): a piece of the gear library
(tools/import_armour.py, import_headgear.py, import_weapon_library.py) recoloured, so no other item,
monster or townsperson looks like it. A weapon's is a design of its own kind it doesn't otherwise
have (a crossbow, with no other designs, its own). A set's pieces share a colour.

  assets/gear/<slot>/u_<unique id>/  - the piece's parts and bag icon, recoloured
  assets/gear/<slot>/catalog.json    - an entry for it ({name, source, unique}; helmets keep the
                                       source's kind and whether it hides the hair, weapons its group)
  (<slot> is the gear folder: weapon, offhand for shields)

Recolouring keeps each pixel's brightness and moves its colour: coloured pixels (cloth, leather,
paint, gems) to the piece's hue, and greys (steel, the outline's highlights) towards it by `grey`.
The dark outline stays.

Usage:  python tools/make_unique_looks.py   (run it after the library importers, which rewrite the
                                             catalogs but keep these entries)
"""
import colorsys
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
GEAR = os.path.join(HERE, "..", "assets", "gear")

# unique id: slot, library piece, hue (degrees), saturation multiplier, grey tint 0..1
ASHEN = (18, 1.15, 0.12)       # Ashen Warlord: embers
BLOODSWORN = (318, 1.3, 0.12)  # wine
WINDRUNNER = (165, 1.1, 0.15)   # teal
ARCHMAGE = (272, 1.2, 0.25)     # violet
TEMPLAR = (46, 1.2, 0.12)       # gold
LOOKS = {
    # Sets
    "warlord_visage": ("helmet", "demon_helm", ASHEN),
    "warlord_hauberk": ("chest", "skeleton_death_knight_2_armour", ASHEN),
    "warlord_grips": ("gloves", "skeleton_death_knight_2_gloves", ASHEN),
    "warlord_treads": ("boots", "skeleton_death_knight_2_boots", ASHEN),
    "bloodsworn_mask": ("helmet", "oni_mask", BLOODSWORN),
    "bloodsworn_vest": ("chest", "demons_of_darkness_1_armour", BLOODSWORN),
    "ancestral_boots": ("boots", "old_hero_1_boots", (55, 1.3, 0.20)),
    "windrunner_hood": ("helmet", "forest_hood", WINDRUNNER),
    "windrunner_vest": ("chest", "forest_ranger_1_armour", WINDRUNNER),
    "windrunner_boots": ("boots", "forest_ranger_1_boots", WINDRUNNER),
    "archmage_circlet": ("helmet", "silver_circlet", ARCHMAGE),
    "archmage_robe": ("chest", "human_magician_3_armour", ARCHMAGE),
    "templar_helm": ("helmet", "holy_greathelm", TEMPLAR),
    "templar_plate": ("chest", "templar_knight_armour", TEMPLAR),
    # Legendaries
    "crown_of_wrath": ("helmet", "bone_diadem", (24, 1.4, 0.20)),
    "martyrs_thornmail": ("chest", "skull_knight_armour", (95, 1.1, 0.15)),
    "hasteful_grips": ("gloves", "assassin_guy_gloves", (200, 1.3, 0.35)),
    "windstriders": ("boots", "white_ninja_boots", (190, 1.2, 0.30)),
    "hunters_cowl": ("helmet", "ranger_hood", (28, 1.2, 0.10)),
    "sages_circlet": ("helmet", "amethyst_circlet", (212, 1.25, 0.15)),
    "heart_of_the_mountain": ("chest", "very_heavy_armored_frontier_defender_armour", (28, 1.2, 0.50)),
    "wardens_grips": ("gloves", "knight_2_gloves", (135, 1.2, 0.30)),
    # Weapons and shields: sets
    "warlord_maul": ("weapon", "mace_2_5", ASHEN),
    "bloodsworn_hatchet": ("weapon", "axe_4_5", BLOODSWORN),
    "ancestral_shield": ("offhand", "shield_1_5", (55, 1.3, 0.20)),
    "windrunner_bow": ("weapon", "skeleton_hunter_2_bow", (165, 1.3, 0.60)),  # (little colour of its own)
    "archmage_staff": ("weapon", "staff_7_5", ARCHMAGE),
    "templar_mace": ("weapon", "mace_1_5", (46, 1.3, 0.45)),
    # Weapons and shields: Legendaries
    "maelstrom_edge": ("weapon", "sword_7_5", (200, 1.3, 0.35)),
    "skybreaker": ("weapon", "mace_8_5", (210, 1.2, 0.35)),
    "bloodthirst_cleaver": ("weapon", "axe_3_4", (356, 1.4, 0.25)),
    "executioners_due": ("weapon", "axe_6_4", (300, 1.2, 0.30)),
    "fury_of_the_ancients": ("weapon", "sword_5_4", (30, 1.2, 0.35)),
    "earthshaker": ("weapon", "mace_5_5", (35, 1.1, 0.30)),
    "lightbringer": ("weapon", "mace_6_5", (50, 1.3, 0.35)),
    "shadowfang": ("weapon", "dagger_6_5", (270, 1.2, 0.35)),
    "vipers_kiss": ("weapon", "dagger_5_5", (110, 1.3, 0.30)),
    "emberheart": ("weapon", "staff_3_5", (15, 1.4, 0.25)),
    "frostbinder": ("weapon", "staff_8_5", (195, 1.2, 0.35)),
    "stormcallers_crook": ("weapon", "staff_2_5", (232, 1.3, 0.30)),
    "windpiercer": ("weapon", "elf_archer_1_bow", (150, 1.2, 0.30)),
    "hail_of_thorns": ("weapon", "archer_1_bow", (95, 1.3, 0.25)),
    "buriza": ("weapon", "arbalest", (195, 1.2, 0.40)),
    "hellrack": ("weapon", "siege_crossbow", (8, 1.5, 0.65)),
    "bulwark_of_the_unbroken": ("offhand", "shield_6_5", (215, 1.1, 0.30)),
    "aegis_of_the_elements": ("offhand", "shield_7_4", (280, 1.2, 0.30)),
}
NAMES = {  # as UniqueItems has them, for the catalog
    "warlord_visage": "Warlord's Visage", "warlord_hauberk": "Warlord's Hauberk", "warlord_grips": "Warlord's Grips",
    "warlord_treads": "Warlord's Treads", "bloodsworn_mask": "Bloodsworn Mask", "bloodsworn_vest": "Bloodsworn Vest",
    "ancestral_boots": "Treads of the Forefathers", "windrunner_hood": "Windrunner's Hood",
    "windrunner_vest": "Windrunner's Vest", "windrunner_boots": "Windrunner's Boots",
    "archmage_circlet": "Archmage's Circlet", "archmage_robe": "Archmage's Robe", "templar_helm": "Templar's Helm",
    "templar_plate": "Templar's Plate", "crown_of_wrath": "Crown of Wrath", "martyrs_thornmail": "Martyr's Thornmail",
    "hasteful_grips": "Hasteful Grips", "windstriders": "Windstriders", "hunters_cowl": "Hunter's Cowl",
    "sages_circlet": "Sage's Circlet", "heart_of_the_mountain": "Heart of the Mountain",
    "wardens_grips": "Warden's Grips",
    "warlord_maul": "Warlord's Maul", "bloodsworn_hatchet": "Bloodsworn Hatchet",
    "ancestral_shield": "Shield of the Forefathers", "windrunner_bow": "Windrunner's Bow",
    "archmage_staff": "Archmage's Staff", "templar_mace": "Templar's Mace", "maelstrom_edge": "Maelstrom Edge",
    "skybreaker": "Skybreaker", "bloodthirst_cleaver": "Bloodthirst Cleaver", "executioners_due": "Executioner's Due",
    "fury_of_the_ancients": "Fury of the Ancients", "earthshaker": "Earthshaker", "lightbringer": "Lightbringer",
    "shadowfang": "Shadowfang", "vipers_kiss": "Viper's Kiss", "emberheart": "Emberheart", "frostbinder": "Frostbinder",
    "stormcallers_crook": "Stormcaller's Crook", "windpiercer": "Windpiercer", "hail_of_thorns": "Hail of Thorns",
    "buriza": "Buriza-Do Kyanon", "hellrack": "Hellrack", "bulwark_of_the_unbroken": "Bulwark of the Unbroken",
    "aegis_of_the_elements": "Aegis of the Elements",
}


def recolour(im, hue, sat, grey):
    """`im` with its colours moved to `hue`, saturation times `sat`, greys tinted by `grey`."""
    a = np.asarray(im.convert("RGBA")).astype(np.float32) / 255.0
    rgb = a[..., :3]
    mx, mn = rgb.max(2), rgb.min(2)
    v = mx
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    h = np.array(colorsys.hsv_to_rgb(hue / 360.0, 1.0, 1.0), np.float32)
    # Coloured pixels: the new hue at their own saturation (times sat) and brightness
    coloured = np.clip(s * sat, 0, 1)[..., None]
    new = v[..., None] * (1 - coloured + coloured * h)
    # Greys: towards the hue a little, more where they're bright (dark outlines stay dark)
    g = np.clip((0.18 - s) / 0.18, 0, 1)[..., None] * grey * np.clip((v[..., None] - 0.15) / 0.5, 0, 1)
    tint = v[..., None] * (1 - 0.6 + 0.6 * h)
    out = new * (1 - g) + tint * g
    out = np.where((s > 0.0)[..., None] | (g > 0), out, rgb)
    return Image.fromarray((np.dstack([out, a[..., 3:]]) * 255).clip(0, 255).astype(np.uint8), "RGBA")


def main():
    catalogs = {}
    for uid, (slot, src, (hue, sat, grey)) in LOOKS.items():
        cat = catalogs.setdefault(slot, json.load(open(os.path.join(GEAR, slot, "catalog.json"))))
        if src not in cat:
            raise SystemExit("%s: no %s/%s in the library" % (uid, slot, src))
        sd, dd = os.path.join(GEAR, slot, src), os.path.join(GEAR, slot, "u_" + uid)
        os.makedirs(dd, exist_ok=True)
        for f in os.listdir(sd):
            if f.endswith(".png"):
                recolour(Image.open(os.path.join(sd, f)), hue, sat, grey).save(os.path.join(dd, f))
        entry = {k: v for k, v in cat[src].items() if k in ("kind", "hides_hair", "group")}
        entry.update({"name": NAMES[uid], "source": "%s/%s" % (slot, src), "unique": uid, "item": False})
        cat["u_" + uid] = entry
    for slot, cat in catalogs.items():
        with open(os.path.join(GEAR, slot, "catalog.json"), "w") as f:
            json.dump(dict(sorted(cat.items())), f, indent="\t")
    print("wrote %d unique looks" % len(LOOKS))


if __name__ == "__main__":
    main()
