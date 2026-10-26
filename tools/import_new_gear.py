"""Makes the one-handed crossbows and the shoulder pieces from the concept sheets in tools/art/
(hand_crossbows.jpg, shoulders.jpg: each piece drawn on a light grey ground around a character):

  assets/gear/weapon/<id>/Sword.png    - a hand crossbow in the hand: on the rig sword's 400 x 128
                                         canvas, its grip at HAND_GRIP (the hand crossbow rig,
                                         tools/make_weapon_rigs.py, holds it there), bolt forward
  assets/gear/weapon/<id>/icon.png     - in the bag (2 x 2 cells)
  assets/gear/shoulders/<id>/Right Arm.png, Left Arm.png - worn: on each arm's 128 x 128 canvas, over
                                         the top of the arm (RigSprite draws it at the shoulder)
  assets/gear/shoulders/<id>/icon.png  - in the bag (2 x 2 cells)
  assets/gear/shoulders/catalog.json   - every piece, for the Wardrobe

Each piece is found as a patch of the sheet that isn't its grey ground (flooded in from the edges, so
it stops at the pieces' dark outlines; ground shut in by a piece, inside a crossbow's string, is
ground too), and its edge softened by how dark each edge pixel is against the ground, so no grey
halo is left. A piece is picked by its top-left corner on the sheet (PIECES).

Usage:  python tools/import_new_gear.py
"""
import json
import os
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
GEAR = os.path.join(HERE, "..", "assets", "gear")
ART = os.path.join(HERE, "art")
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)
GROUND = np.array([220.0, 220.0, 220.0])
GROUND_TOL = 30  # summed RGB distance from the ground that is still ground
ENCLOSED_MIN = 60  # px: a patch of ground colour shut in by a piece, at least this big, is ground

# The hand crossbow on the rig sword's canvas: this wide, its grip (the hand) here
WEAPON_CANVAS = (400, 128)
HAND_GRIP = (52.0, 92.0)
CROSSBOW_H = 118.0  # its height on that canvas
GRIP_AT = (0.17, 0.74)  # where the grip is on the cut-out picture (fractions of its box)
# A shoulder piece on an arm's canvas: centred on the shoulder, this wide, its top this far above it
SHOULDER = {"Right Arm": (57.5, 33.0), "Left Arm": (70.5, 37.0)}  # (RigSprite.SHOULDER_ART)
SHOULDER_W = 96.0
SHOULDER_UP = 24.0

# sheet: [(id, name, top-left of its patch on the sheet)]
PIECES = {
    "hand_crossbows.jpg": [
        ("hand_crossbow", "Hand Crossbow", (145, 54)),
        ("iron_hand_crossbow", "Iron Hand Crossbow", (147, 286)),
        ("bone_hand_crossbow", "Bone Hand Crossbow", (147, 514)),
        ("horn_hand_crossbow", "Horn Hand Crossbow", (1015, 53)),
        ("gilded_hand_crossbow", "Gilded Hand Crossbow", (1013, 284)),
        ("jade_hand_crossbow", "Jade Hand Crossbow", (1015, 515)),
    ],
    "shoulders.jpg": [
        ("iron_pauldrons", "Iron Pauldrons", (83, 72)),
        ("spiked_pauldrons", "Spiked Pauldrons", (88, 293)),
        ("strapped_pauldrons", "Strapped Pauldrons", (85, 519)),
        ("gilded_pauldrons", "Gilded Pauldrons", (308, 69)),
        ("warlord_pauldrons", "Warlord Pauldrons", (311, 299)),
        ("bonebound_mantle", "Bonebound Mantle", (304, 509)),
        ("hunters_mantle", "Hunter's Mantle", (862, 72)),
        ("leaf_mantle", "Leaf Mantle", (863, 288)),
        ("void_spaulders", "Void Spaulders", (874, 497)),
        ("skull_pauldron", "Skull Pauldron", (1109, 77)),
        ("horned_skull_pauldron", "Horned Skull Pauldron", (1107, 285)),
        ("frost_spaulders", "Frost Spaulders", (1116, 508)),
    ],
}


def cut_all(path):
    """Every piece on the sheet: {(left, top): RGBA image cropped to it}."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    near = np.abs(a - GROUND).sum(2) < GROUND_TOL
    ground = np.zeros((h, w), bool)
    q = deque([(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)])
    while q:
        y, x = q.popleft()
        if ground[y, x] or not near[y, x]:
            continue
        ground[y, x] = True
        if y > 0: q.append((y - 1, x))
        if y < h - 1: q.append((y + 1, x))
        if x > 0: q.append((y, x - 1))
        if x < w - 1: q.append((y, x + 1))
    # Ground shut in by a piece (inside a crossbow's string): patches of ground colour big enough
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y in range(h):
        for x in range(w):
            if near[y, x] and not ground[y, x] and not lab[y, x]:
                n += 1
                stack, pts = [(y, x)], []
                lab[y, x] = n
                while stack:
                    cy, cx = stack.pop()
                    pts.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not ground[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
                if len(pts) >= ENCLOSED_MIN:
                    for p in pts:
                        ground[p] = True
    fg = ~ground
    # Soft edge: a piece pixel next to the ground is as opaque as it is darker than the ground
    lum = a @ np.array([0.299, 0.587, 0.114])
    edge = fg & (np.roll(ground, 1, 0) | np.roll(ground, -1, 0) | np.roll(ground, 1, 1) | np.roll(ground, -1, 1))
    alpha = fg.astype(np.float32)
    alpha[edge] = np.clip((220.0 - lum[edge]) / 120.0, 0.0, 1.0)
    out = {}
    seen = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            if not fg[y, x] or seen[y, x]:
                continue
            stack, pts = [(y, x)], []
            seen[y, x] = True
            while stack:
                cy, cx = stack.pop()
                pts.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and fg[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(pts) < 800:
                continue
            ys, xs = zip(*pts)
            y0, y1, x0, x1 = min(ys), max(ys) + 1, min(xs), max(xs) + 1
            mask = np.zeros((y1 - y0, x1 - x0), bool)
            mask[np.array(ys) - y0, np.array(xs) - x0] = True
            rgba = np.dstack([a[y0:y1, x0:x1], alpha[y0:y1, x0:x1] * 255.0 * mask])
            out[(x0, y0)] = Image.fromarray(rgba.clip(0, 255).astype(np.uint8), "RGBA")
    return out


def find(pieces, corner):
    """The piece whose patch starts nearest `corner`."""
    key = min(pieces, key=lambda k: abs(k[0] - corner[0]) + abs(k[1] - corner[1]))
    if abs(key[0] - corner[0]) + abs(key[1] - corner[1]) > 12:
        raise SystemExit("no piece at %s" % (corner,))
    return pieces[key]


def fit(im, w, h, margin=0.9):
    """`im` centred in a w x h canvas, as big as fits."""
    s = min(w * margin / im.width, h * margin / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def place(im, canvas, width, at_x, top):
    """`im` scaled to `width`, centred on at_x with its top at `top`, on a `canvas` (w, h)."""
    s = width / im.width
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    out = Image.new("RGBA", canvas)
    out.alpha_composite(im, (round(at_x - im.width / 2), round(top)), )
    return out


def crossbow_in_hand(im):
    """On the rig sword's canvas: CROSSBOW_H tall, its grip (GRIP_AT on the picture) at HAND_GRIP."""
    s = CROSSBOW_H / im.height
    sm = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    out = Image.new("RGBA", WEAPON_CANVAS)
    gx, gy = GRIP_AT[0] * sm.width, GRIP_AT[1] * sm.height
    out.alpha_composite(sm, (round(HAND_GRIP[0] - gx), round(HAND_GRIP[1] - gy)))
    return out


def main():
    made = {}
    for sheet, items in PIECES.items():
        pieces = cut_all(os.path.join(ART, sheet))
        for pid, name, corner in items:
            im = find(pieces, corner)
            if sheet.startswith("hand"):
                d = os.path.join(GEAR, "weapon", pid)
                os.makedirs(d, exist_ok=True)
                crossbow_in_hand(im).save(os.path.join(d, "Sword.png"))
                fit(im, 2 * CELL, 2 * CELL).save(os.path.join(d, "icon.png"))
            else:
                d = os.path.join(GEAR, "shoulders", pid)
                os.makedirs(d, exist_ok=True)
                for arm, (sx, sy) in SHOULDER.items():
                    place(im, (128, 128), SHOULDER_W, sx, sy - SHOULDER_UP).save(os.path.join(d, arm + ".png"))
                fit(im, 2 * CELL, 2 * CELL).save(os.path.join(d, "icon.png"))
                made[pid] = {"name": name, "item": True}
    path = os.path.join(GEAR, "shoulders", "catalog.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(made)
    with open(path, "w") as f:
        json.dump(dict(sorted(old.items())), f, indent="\t")
    print("wrote 6 hand crossbows and %d shoulder pieces" % len(made))


if __name__ == "__main__":
    main()
