"""Makes the bag icons of the wrist (bracers) and legs (shorts and guards) pieces from the concept
sheets in tools/art/ (wrists.jpg, legs.jpg: each piece drawn on a light grey ground):

  assets/gear/wrists/<id>/icon.png  - in the bag (2 x 2 cells)
  assets/gear/legs/<id>/icon.png

These slots are never drawn on the character, so an icon is all a piece needs. The cut-out is
tools/import_new_gear.py's (each piece is a patch of the sheet that isn't its grey ground). A piece
drawn as a pair (the leather bracers) is two patches: both are listed, and put together.
The ids and names are in LootGenerator (WRIST_BASES, LEG_BASES).

Usage:  python tools/import_wrist_legs.py
"""
import os

from PIL import Image

import import_new_gear as g

# sheet: slot, [(id, [top-left of each patch of the piece on the sheet])]
SHEETS = {
    "wrists.jpg": ("wrists", [
        ("laced_bracers", [(24, 56), (80, 65)]),
        ("spiked_bracers", [(178, 55)]),
        ("gilded_bracers", [(292, 53)]),
        ("banded_bracers", [(407, 55)]),
        ("furred_bracers", [(32, 163)]),
        ("leaf_bracers", [(161, 165)]),
        ("frost_bracers", [(285, 161)]),
        ("bandaged_wraps", [(405, 165)]),
    ]),
    "legs.jpg": ("legs", [
        ("ragged_shorts", [(31, 56)]),
        ("iron_guards", [(153, 54)]),
        ("gilded_trunks", [(278, 56)]),
        ("shadow_guards", [(392, 54)]),
        ("furred_kilt", [(31, 168)]),
        ("leaf_kilt", [(155, 164)]),
        ("frost_kilt", [(278, 168)]),
        ("bonebound_shorts", [(396, 170)]),
    ]),
}


def together(patches):
    """Several cut-out patches ([(corner, image)]) as one picture, each where it was on the sheet."""
    if len(patches) == 1:
        return patches[0][1]
    x0 = min(c[0] for c, _ in patches)
    y0 = min(c[1] for c, _ in patches)
    x1 = max(c[0] + im.width for c, im in patches)
    y1 = max(c[1] + im.height for c, im in patches)
    out = Image.new("RGBA", (x1 - x0, y1 - y0))
    for c, im in patches:
        out.alpha_composite(im, (c[0] - x0, c[1] - y0))
    return out


def main():
    n = 0
    for sheet, (slot, items) in SHEETS.items():
        pieces = g.cut_all(os.path.join(g.ART, sheet))
        for pid, corners in items:
            patches = []
            for corner in corners:
                key = min(pieces, key=lambda k: abs(k[0] - corner[0]) + abs(k[1] - corner[1]))
                if abs(key[0] - corner[0]) + abs(key[1] - corner[1]) > 12:
                    raise SystemExit("no piece at %s on %s" % (corner, sheet))
                patches.append((key, pieces[key]))
            d = os.path.join(g.GEAR, slot, pid)
            os.makedirs(d, exist_ok=True)
            g.fit(together(patches), 2 * g.CELL, 2 * g.CELL).save(os.path.join(d, "icon.png"))
            n += 1
    print("wrote %d icons" % n)


if __name__ == "__main__":
    main()
