"""Makes the currency icons from the concept sheets in tools/art/ (currency_orbs.jpg, currency_1.jpg,
currency_3.jpg: each item drawn on a light grey ground, with its name under it):

  assets/icons/orbs/<orb id>.png         - an orb's icon (CraftingDB.orb_icon), 128 x 128
  assets/icons/materials/portal_scroll.png - the Town Portal scroll (IconFactory.scroll_icon)

The cut-out is tools/import_new_gear.py's (each item is a patch of the sheet that isn't its grey
ground; the names under them are too small to count). An item is picked by its top-left corner on
the sheet. Orbs with no picture here (Transmutation, Alteration, Augmentation, Scouring keep their
older art; Identify, Chance, Blessed and Regret are drawn by IconFactory) are left as they are.

Usage:  python tools/import_currency_icons.py
"""
import os

import import_new_gear as g

SIZE = 128
OUT = os.path.join(g.HERE, "..", "assets", "icons")

# sheet: [(file under assets/icons, top-left of the item on the sheet)]
ICONS = {
    "currency_orbs.jpg": [
        ("orbs/chaos.png", (24, 54)),
        ("orbs/exalt.png", (124, 51)),
        ("orbs/divine.png", (224, 50)),
        ("orbs/regal.png", (331, 45)),
        ("orbs/vaal.png", (419, 53)),
        ("orbs/alchemy.png", (21, 170)),
        ("orbs/jeweller.png", (327, 175)),
        ("orbs/mirror.png", (424, 173)),
    ],
    "currency_1.jpg": [
        ("orbs/armourer.png", (375, 16)),  # Armourer's Scrap
        ("orbs/whetstone.png", (232, 84)),  # Blacksmith's Whetstone
    ],
    "currency_3.jpg": [
        ("orbs/gemcutter.png", (271, 35)),  # Gemcutter's Prism
        ("orbs/annul.png", (328, 218)),  # Orb of Annulment
        ("materials/portal_scroll.png", (448, 217)),
    ],
}


def main():
    n = 0
    for sheet, items in ICONS.items():
        pieces = g.cut_all(os.path.join(g.ART, sheet))
        for path, corner in items:
            dest = os.path.join(OUT, path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            g.fit(g.find(pieces, corner), SIZE, SIZE, 0.94).save(dest)
            n += 1
    print("wrote %d icons" % n)


if __name__ == "__main__":
    main()
