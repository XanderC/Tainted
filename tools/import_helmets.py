"""Makes helmet art from the helmets the character packs draw on their heads (assets/skins/<skin>/Head.png).

  assets/gear/helmet/<id>/Head.png  - worn: the helmet alone, on the Head part's 480 x 480 canvas, so
                                      it sits on a character exactly as that skin's head does. The face
                                      opening (the flat skin colour) is cut out, so the wearer's own face
                                      shows through; great helms that cover the face are kept whole.
  assets/gear/helmet/<id>/icon.png  - in the bag: the same helmet, fitted into its 2 x 2 cells

ART maps a helmet base (LootGenerator._build_bases) to its skin and how to cut it:
  "open"  - flood-fill the face colour out from a seed point (a fraction of the head's size), and
            optionally cut off everything below a line (a third number, below the helmet's rim)
  "crop"  - keep only the part above a line (a fraction of the head's height): beards and chins go
  "whole" - keep it all (a full helm)
The skins are all on the zombie rig's 480 px Head canvas (the archers' 600 px heads aren't used).

Usage:  python tools/import_helmets.py
"""
import os

import cv2
import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
SKINS = os.path.join(HERE, "..", "assets", "skins")
ROOT = os.path.join(HERE, "..", "assets", "gear", "helmet")
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)
TOLERANCE = 34  # how far (RGB) a pixel may be from the face colour and still be cut out

# id: (skin, treatment, seed (x, y) as fractions of the head's box, or the crop line)
ART = {
    "linen_wrap": ("merchant", "open", (0.5, 0.80, 0.64)),
    "leather_cap": ("jeweler", "open", (0.5, 0.74, 0.64)),
    "iron_helm": ("stash_keeper", "open", (0.5, 0.46, 0.53)),
    "gilded_turban": ("sage", "open", (0.5, 0.80, 0.64)),
    "horned_cap": ("skeleton_viking_2", "open", (0.5, 0.82, 0.64)),
    "knights_helm": ("skeleton_warrior_2", "open", (0.5, 0.82, 0.66)),
    "crusader_helm": ("skeleton_crusader_1", "open", (0.5, 0.82, 0.64)),
    "viking_helm": ("skeleton_viking_1", "open", (0.5, 0.82, 0.64)),
    "elven_helm": ("dark_elf_2", "open", (0.5, 0.80, 0.70)),
    "shadow_helm": ("dark_elf_1", "open", (0.5, 0.80, 0.70)),
    "frost_greathelm": ("ghost_knight", "whole", None),
    "death_visage": ("death_knight", "whole", None),
    "infernal_crown": ("hell_knight", "open", (0.5, 0.78, 0.64)),
    "lich_crown": ("lich", "whole", None),
}


def box_of(a):
    ys, xs = np.nonzero(a > 8)
    return xs.min(), ys.min(), xs.max(), ys.max()


def cut(im, how, arg):
    """The helmet part of a head image, as RGBA."""
    arr = np.array(im.convert("RGBA"))
    x0, y0, x1, y1 = box_of(arr[:, :, 3])
    w, h = x1 - x0, y1 - y0
    if how == "crop":
        arr[int(y0 + h * arg):, :, 3] = 0
    elif how == "open":
        crop_at = None
        if len(arg) == 3:
            arg, crop_at = arg[:2], arg[2]
        sx, sy = int(x0 + w * arg[0]), int(y0 + h * arg[1])
        rgb = arr[:, :, :3].copy()
        seed = rgb[sy, sx].astype(np.int32)
        near = (np.abs(rgb.astype(np.int32) - seed).sum(axis=2) <= TOLERANCE) & (arr[:, :, 3] > 200)
        near = near.astype(np.uint8)
        n, labels = cv2.connectedComponents(near, connectivity=4)
        region = labels == labels[sy, sx]
        if labels[sy, sx] == 0:
            raise SystemExit("seed not on a flat colour")
        # a clean edge: the cut-out is eased by a pixel so no skin-coloured fringe is left
        region = cv2.dilate(region.astype(np.uint8), np.ones((3, 3), np.uint8))
        # the skull's speckles and pits are darker dots inside the opening: close them with it
        region = cv2.morphologyEx(region, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))).astype(bool)
        arr[region, 3] = 0
        if crop_at is not None:  # below the rim: the skull's jaw and teeth are no part of a helmet
            arr[int(y0 + h * crop_at):, :, 3] = 0
    return Image.fromarray(arr, "RGBA")


def fit(im, w, h):
    """`im` cropped to its picture and centred in a w x h canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = min((w * 0.9) / im.width, (h * 0.9) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def main():
    for hid, (skin, how, arg) in ART.items():
        head = Image.open(os.path.join(SKINS, skin, "Head.png"))
        if head.size != (480, 480):
            raise SystemExit("%s: head is %s, not 480 x 480" % (skin, head.size))
        helmet = cut(head, how, arg)
        d = os.path.join(ROOT, hid)
        os.makedirs(d, exist_ok=True)
        helmet.save(os.path.join(d, "Head.png"))
        fit(helmet, 2 * CELL, 2 * CELL).save(os.path.join(d, "icon.png"))
    print("wrote %d helmets under %s" % (len(ART), os.path.abspath(ROOT)))


if __name__ == "__main__":
    main()
