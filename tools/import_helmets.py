"""Makes helmet art from the helmets the character packs draw on their heads (assets/skins/<skin>/Head.png).

  assets/gear/helmet/<id>/Head.png  - worn: the helmet alone, on the Head part's 480 x 480 canvas, so
                                      it sits on a character exactly as that skin's head does
  assets/gear/helmet/<id>/icon.png  - in the bag: the same helmet, fitted into its 2 x 2 cells

A helmet is cut out the way tools/build_appearance.py cuts out hair: everything on the head that
isn't skin (its colour sampled in the middle of the face) or outline, in big pieces, plus the outline
that runs along those pieces. So the face, ears and chin go, the helmet keeps its own outline and no
straight cuts or holes are left. A beard or chin strap below the eyes isn't helmet (below_eyes).
Great helms that cover the face ("whole") are kept as they are.

ART maps a helmet base (LootGenerator.HELMET_BASES) to the skin it comes from and how to cut it:
  brim  - a cap or crown: nothing below this line (y), where the character's own hair and ears hang
  erase - boxes (x0, y0, x1, y1) of the character's own to take away (an elf's pointed ear)
  erase_colour - [(box, rgb)]: a colour of the character's own in a box (the crown wearer's ear)
  fill  - every gap it closes in is its own (a light highlight the skin test took)
  dark  - it is as dark as the outline (a black crown): its dark pixels are helmet too
  whole - a great helm that covers the face: kept as it is
The skins are all on the zombie rig's 480 px Head canvas (the archers' 600 px heads aren't used).

Usage:  python tools/import_helmets.py
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from build_appearance import EYE_Y, FACE_X, arr, grow, head_masks, img, keep_big  # noqa: E402

HERE = os.path.dirname(__file__)
SKINS = os.path.join(HERE, "..", "assets", "skins")
ROOT = os.path.join(HERE, "..", "assets", "gear", "helmet")
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)
MIN_PIECE = 600  # px: smaller bits of "not skin" are freckles, scars and texture, not helmet

ART = {
    "linen_wrap": {"skin": "merchant"},
    "leather_cap": {"skin": "jeweler", "brim": 238, "erase": [(436, 150, 480, 260)]},  # a strap end
    "iron_helm": {"skin": "stash_keeper", "brim": 254},
    "gilded_turban": {"skin": "sage", "fill": True},
    "horned_cap": {"skin": "skeleton_viking_2"},
    "knights_helm": {"skin": "skeleton_warrior_2"},
    "crusader_helm": {"skin": "skeleton_crusader_1"},
    "viking_helm": {"skin": "skeleton_viking_1"},
    "elven_helm": {"skin": "dark_elf_2", "erase": [(0, 190, 82, 300)]},  # its own pointed ear
    "shadow_helm": {"skin": "dark_elf_1", "erase": [(0, 190, 82, 300)]},
    "frost_greathelm": {"skin": "ghost_knight", "whole": True},
    "death_visage": {"skin": "death_knight", "whole": True},
    "infernal_crown": {"skin": "hell_knight", "brim": 292,
                       "erase_colour": [((318, 70, 405, 205), (0.95, 0.61, 0.51))]},  # its own ear
    "lich_crown": {"skin": "lich", "whole": True},
}


def below_eyes():
    """The lower face, where a beard or chin would be: not helmet."""
    yy, xx = np.mgrid[0:480, 0:480]
    return (xx >= FACE_X[0] - 40) & (xx <= FACE_X[1] + 40) & (yy > EYE_Y + 30)


_bald = None


def bald_head():
    """Where a bald head is (the appearance base head, same canvas): anything of a helmet beyond it
    (horns, crown spikes, a plume) is helmet whatever its colour."""
    global _bald
    if _bald is None:
        base = arr(Image.open(os.path.join(HERE, "..", "assets", "appearance", "base_male.png")).convert("RGBA"))
        _bald = grow(base[:, :, 3] > 0.5, 3)
    return _bald


def fill_holes(mask):
    """`mask` with every gap it closes in filled (a rivet's middle, a highlight the skin test took)."""
    outside = np.zeros_like(mask)
    H, W = mask.shape
    stack = [(y, x) for y in (0, H - 1) for x in range(W)] + [(y, x) for x in (0, W - 1) for y in range(H)]
    while stack:
        y, x = stack.pop()
        if outside[y, x] or mask[y, x]:
            continue
        outside[y, x] = True
        if y > 0: stack.append((y - 1, x))
        if y < H - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < W - 1: stack.append((y, x + 1))
    return ~outside


def cut(head, spec):
    a = arr(head.convert("RGBA"))
    skin, rest, outline = head_masks(a)
    opaque = a[:, :, 3] > 0.5
    helmet = keep_big(rest & ~below_eyes(), MIN_PIECE)
    helmet |= opaque & ~skin & ~bald_head() & ~below_eyes()  # horns and spikes, dark or not (not ears)
    brim = int(spec.get("brim", 0))
    if spec.get("dark", False):
        helmet |= outline & ~below_eyes()
    if brim:
        helmet[brim:, :] = False
    # Its outline: the dark pixels along it
    keep = helmet | (outline & grow(helmet, 7))
    # Small holes it closes in are its own (a rivet's middle); big ones are skin showing through
    holes = fill_holes(keep) & ~keep
    if spec.get("fill", False):  # a light highlight the skin test took (the turban's folds)
        keep |= holes
    else:
        keep |= holes & ~keep_big(holes, 1500) & ~keep_big(holes & skin, 900)
    keep &= opaque
    for x0, y0, x1, y1 in spec.get("erase", []):
        keep[y0:y1, x0:x1] = False
    # A colour of the character's own (an ear) in a box, leaving the rest of the box alone
    for (x0, y0, x1, y1), rgb in spec.get("erase_colour", []):
        near = np.abs(a[:, :, :3] - np.array(rgb)).sum(2) < 0.35
        box = np.zeros_like(keep)
        box[y0:y1, x0:x1] = True
        keep &= ~(grow(near & box, 10) & box)
    if brim:
        keep[brim:, :] = False
    # Scraps left over (a strap end, the rim of an ear) aren't helmet
    keep = keep_big(keep, 2500)
    out = a.copy()
    out[~keep, 3] = 0
    return img(out)


def fit(im, w, h):
    """`im` cropped to its picture and centred in a w x h canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = min((w * 0.9) / im.width, (h * 0.9) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def main():
    for hid, spec in ART.items():
        head = Image.open(os.path.join(SKINS, spec["skin"], "Head.png"))
        if head.size != (480, 480):
            raise SystemExit("%s: head is %s, not 480 x 480" % (spec["skin"], head.size))
        helmet = head.convert("RGBA") if spec.get("whole", False) else cut(head, spec)
        d = os.path.join(ROOT, hid)
        os.makedirs(d, exist_ok=True)
        helmet.save(os.path.join(d, "Head.png"))
        fit(helmet, 2 * CELL, 2 * CELL).save(os.path.join(d, "icon.png"))
    print("wrote %d helmets under %s" % (len(ART), os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
