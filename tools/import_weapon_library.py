"""Makes the weapon and shield looks (Wardrobe) besides the items' own: every design in the CraftPix
weapon packs (on the NAS, Tainted > assets > weapons: 8 designs in 5 grades of each kind), and every
weapon the characters in the character packs (Tainted > assets > sprites) hold: their swords, axes,
staves, scythes and the rest (drawn for the same hand as the rig's sword), and the archers' bows.

  assets/gear/weapon/<id>/Sword.png or Bow.png, icon.png   - melee weapons and bows
  assets/gear/offhand/<id>/Shield.png, icon.png            - shields
  assets/gear/weapon/catalog.json, offhand/catalog.json    - every look there, the items' own too:
      {name, group: "melee" | "bow" | "shield", item: is an item's own art}

A weapon can look like any other of its group (a bow or crossbow like a bow, a melee weapon like any
melee weapon, a shield like a shield): the rig draws a group's art the same way. Designs an item
already uses (tools/import_weapons.py, import_bows.py) aren't made again. The uniques' own looks
(u_<id>, tools/make_unique_looks.py) are kept in the catalogs.

Usage:  python tools/import_weapon_library.py [--weapons <folder>] [--sprites <folder>]
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys
import zipfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from import_weapons import ART, PACK_OF, bag_icon, fit  # noqa: E402

HERE = os.path.dirname(__file__)
GEAR = os.path.join(HERE, "..", "assets", "gear")
LOOT = os.path.join(HERE, "..", "scripts", "loot_generator.gd")
WEAPONS = "Y:/Tainted/assets/weapons"
SPRITES = "Y:/Tainted/assets/sprites"
CELL = 96
GRADES = ["Crude", "Plain", "Fine", "Ornate", "Masterwork"]
# pack folder kind: (id word, name, bag cells for the icon)
KINDS = {"Sword": ("sword", "Sword", (1, 3)), "Saber": ("sabre", "Sabre", (1, 3)), "Axe": ("axe", "Axe", (1, 3)),
         "Cudgels": ("mace", "Mace", (1, 3)), "Dagger": ("dagger", "Dagger", (1, 2)),
         "Spear": ("spear", "Spear", (1, 4)), "Staves": ("staff", "Staff", (1, 4)),
         "Shield": ("shield", "Shield", (2, 2))}
ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]


def bases():
    """The items' weapons and shields from LootGenerator.WEAPON_BASES: id -> (name, look group)."""
    src = open(LOOT, encoding="utf-8").read()
    table = src[src.index("const WEAPON_BASES"):]
    table = table[:table.index("\n]\n")]
    out = {}
    for m in re.finditer(r'\["(\w+)", "([^"]+)", "(\w+)", (true|false),', table):
        wtype, two = m.group(3), m.group(4) == "true"
        group = "shield" if wtype == "shield" else ("handxbow" if wtype == "crossbow" and not two else
                                                    ("bow" if wtype in ("bow", "crossbow") else "melee"))
        out[m.group(1)] = (m.group(2), group)
    return out


def pixels(png):
    return hashlib.md5(np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).tobytes()).hexdigest()


def pack_designs(folder):
    """Every design of the weapon packs not an item's: (id, name, kind, png bytes)."""
    used = {(f, g) for f, g, _ in ART.values()}
    zips = [z for z in os.listdir(folder) if z.endswith(".zip")]
    out = []
    for kind, (word, name, _) in KINDS.items():
        found = [z for z in zips if PACK_OF[kind] in z]
        with zipfile.ZipFile(os.path.join(folder, found[0])) as z:
            for n in sorted(z.namelist()):
                m = re.match(r"PNG/%s_(\d+)/(\d)\.png$" % kind, n)
                if not m or (("%s_%s" % (kind, m.group(1))), int(m.group(2))) in used:
                    continue
                design, grade = int(m.group(1)), int(m.group(2))
                out.append(("%s_%d_%d" % (word, design, grade), "%s %s %s" % (GRADES[grade - 1], name, ROMAN[design - 1]),
                            kind, z.read(n)))
    return out


def pack_held(folder, have, part, suffix, noun):
    """Every character's `part` ("Bow", "Sword") in the character packs, once each and not already an
    item's: (id, name, png)."""
    out, seen = [], set(have)
    for zn in sorted(z for z in os.listdir(folder) if z.endswith(".zip") and "(1)" not in z):
        with zipfile.ZipFile(os.path.join(folder, zn)) as z:
            for n in sorted(z.namelist()):
                m = re.match(r"(.+?)/PNG/Vector Parts/%s\.png$" % part, n)
                if not m:
                    continue
                png = z.read(n)
                h = pixels(png)
                if h in seen:
                    continue
                seen.add(h)
                char = re.sub(r"[^a-z0-9]+", "_", m.group(1).lower()).strip("_")
                words = [w for w in re.sub(r"^craftpix-(net-)?\d+-", "", zn[:-4]).split("-")
                         if w not in ("chibi", "free", "2d", "game", "sprites", "character")]
                pid = "%s_%s" % (char, suffix)
                if any(o[0] == pid for o in out):
                    pid = "%s_%s_%s" % (words[0], char, suffix)
                out.append((pid, "%s's %s" % (" ".join(w.capitalize() for w in char.split("_")), noun), png))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weapons", default=WEAPONS)
    ap.add_argument("--sprites", default=SPRITES)
    args = ap.parse_args()
    catalogs = {}
    for folder in ("weapon", "offhand"):
        path = os.path.join(GEAR, folder, "catalog.json")
        old = json.load(open(path)) if os.path.exists(path) else {}
        catalogs[folder] = {k: v for k, v in old.items() if k.startswith("u_")}
    have_bows, have_melee = [], []
    for bid, (name, group) in bases().items():
        folder = "offhand" if group == "shield" else "weapon"
        catalogs[folder][bid] = {"name": name, "group": group, "item": True}
        bow = os.path.join(GEAR, folder, bid, "Bow.png")
        if group == "bow" and os.path.exists(bow):
            have_bows.append(pixels(open(bow, "rb").read()))
        sword = os.path.join(GEAR, folder, bid, "Sword.png")
        if group == "melee" and os.path.exists(sword):
            have_melee.append(pixels(open(sword, "rb").read()))
    n = 0
    designs = pack_designs(args.weapons)
    have_melee += [pixels(png) for _, _, kind, png in designs if kind != "Shield"]
    for pid, name, kind, png in designs:
        im = Image.open(io.BytesIO(png)).convert("RGBA")
        shield = kind == "Shield"
        d = os.path.join(GEAR, "offhand" if shield else "weapon", pid)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "Shield.png" if shield else "Sword.png"), "wb") as f:
            f.write(png)
        cells = KINDS[kind][2]
        (fit(im, cells[0] * CELL, cells[1] * CELL) if shield else bag_icon(im, cells)).save(os.path.join(d, "icon.png"))
        catalogs["offhand" if shield else "weapon"][pid] = {"name": name, "group": "shield" if shield else "melee", "item": False}
        n += 1
    for pid, name, png in pack_held(args.sprites, have_melee, "Sword", "weapon", "Weapon"):
        d = os.path.join(GEAR, "weapon", pid)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "Sword.png"), "wb") as f:
            f.write(png)
        bag_icon(Image.open(io.BytesIO(png)).convert("RGBA"), (1, 3)).save(os.path.join(d, "icon.png"))
        catalogs["weapon"][pid] = {"name": name, "group": "melee", "item": False}
        n += 1
    for pid, name, png in pack_held(args.sprites, have_bows, "Bow", "bow", "Bow"):
        d = os.path.join(GEAR, "weapon", pid)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "Bow.png"), "wb") as f:
            f.write(png)
        fit(Image.open(io.BytesIO(png)).convert("RGBA"), 2 * CELL, 3 * CELL).save(os.path.join(d, "icon.png"))
        catalogs["weapon"][pid] = {"name": name, "group": "bow", "item": False}
        n += 1
    for folder, cat in catalogs.items():
        with open(os.path.join(GEAR, folder, "catalog.json"), "w") as f:
            json.dump(dict(sorted(cat.items())), f, indent="\t")
    groups = {}
    for cat in catalogs.values():
        for v in cat.values():
            groups[v["group"]] = groups.get(v["group"], 0) + 1
    print("wrote %d looks; by group (items' own included): %s" % (n, groups))


if __name__ == "__main__":
    main()
