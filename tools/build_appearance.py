"""Builds the character-creation art (assets/appearance) from the CraftPix chibi packs.

The packs draw hair and beards into each head, so this cuts them out as separate layers:
  base_male.png / base_female.png  - a bald head, divided by its skin colour so tinting it with
                                     a skin tone gives that tone (the default tone gives the original)
  hands/Left Hand.png, Right Hand.png - the same for the hands
  hair/<id>.png, beard/<id>.png    - hair / beard (with the outline around them) in grey, so
                                     tinting gives any colour with the original shading
  face/<id>/Face 0N.png            - a face's expressions without eyebrows
  face/<id>/Brows 0N.png           - its eyebrows in grey, tinted with the hair colour
  outfit/<id>/<part>.png           - a starter outfit's body, arms and legs
  appearance.json                  - the options, for the game to list

Usage:  python tools/build_appearance.py <folder with the CraftPix zips>
"""
import io
import json
import os
import re
import sys
import zipfile
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "appearance")

BASE_HEAD = "Evil Bald Guy"  # a clean bald head, the base every hairstyle sits on
BLUSH_FROM = "Citizen-Women_1"  # the women's cheek blush, added to the female base

# id: (character, label). Hair takes everything on the head that isn't skin, except a beard.
HAIR = {
    "short": ("Citizen_1", "Slicked"),
    "bowl": ("Citizen_3", "Bowl"),
    "spiky": ("Medieval Warrior", "Spiky"),
    "messy": ("Romanian Settler", "Messy"),
    "swept": ("Vampire_Hunter_1", "Swept"),
    "long": ("Viking_3", "Long"),
    "bob": ("Citizen-Women_1", "Bob"),
    "fringe": ("Medieval Warrior Girl", "Fringe"),
    "straight": ("Citizen-Women_2", "Straight"),
    "flowing": ("Amazon_Warrior_1", "Flowing"),
}
BEARDS = {
    "full": ("Romanian Settler", "Full"),
    "thick": ("Barbarian Warrior", "Thick"),
    "viking": ("Viking_3", "Viking"),
    "goatee": ("Old Guy", "Goatee"),
    "grizzled": ("Old_hero_1", "Grizzled"),
    "mercenary": ("Mercenaries_3", "Mercenary"),
}
FACES = {  # id: (character, label, gender)
    "stern": ("Romanian Settler", "Stern", "male"),
    "calm": ("Monk Guy", "Calm", "male"),
    "scarred": ("Vampire_Hunter_1", "Scarred", "male"),
    "fierce": ("Evil Bald Guy", "Fierce", "male"),
    "bright": ("Citizen-Women_1", "Bright", "female"),
    "keen": ("Citizen-Women_2", "Keen", "female"),
    "proud": ("Amazon_Warrior_1", "Proud", "female"),
    "bold": ("Medieval Warrior Girl", "Bold", "female"),
}
OUTFITS = {  # id: (character, label)
    "peasant": ("Citizen_1", "Peasant"),
    "townsfolk": ("Citizen_2", "Townsfolk"),
    "dress": ("Citizen-Women_1", "Dress"),
    "tunic": ("Citizen-Women_3", "Tunic"),
    "ranger": ("Forest_Ranger_1", "Ranger"),
    "mercenary": ("Mercenaries_1", "Mercenary"),
}
OUTFIT_PARTS = ["Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]

# The face opening on every head (480 x 480): its columns, and the row of the eyes
FACE_X = (205, 440)
EYE_Y = 255


def load_chars(src: str, wanted: set) -> dict:
    """character name -> {part name -> RGBA image}, read straight from the zips."""
    out = {}
    for z in sorted(os.listdir(src)):
        if not z.endswith(".zip") or " (1)" in z:
            continue
        zf = zipfile.ZipFile(os.path.join(src, z))
        for n in zf.namelist():
            if "/Vector Parts/" not in n or not n.endswith(".png") or n.split("/")[-1].startswith("._"):
                continue
            ch = n.split("/Vector Parts/")[0].split("/")[0]
            ch = re.sub(r"^Chibi[ _-]", "", ch)
            if ch not in wanted:
                continue
            out.setdefault(ch, {})[n.split("/")[-1][:-4]] = Image.open(io.BytesIO(zf.read(n))).convert("RGBA")
    missing = wanted - set(out)
    if missing:
        sys.exit("not found in the packs: %s" % sorted(missing))
    return out


def hsv(a):
    rgb = a[:, :, :3]
    mx = rgb.max(2)
    mn = rgb.min(2)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def arr(im):
    return np.asarray(im).astype(float) / 255


def img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype("uint8"), "RGBA")


def skin_colour(a):
    """The face's skin colour: the median colour in the middle of the face opening."""
    patch = a[300:380, 260:380]
    keep = patch[:, :, 3] > 0.9
    return np.median(patch[keep][:, :3], axis=0)


def head_masks(a):
    """skin, hair and outline masks of a head."""
    ref = skin_colour(a)
    op = a[:, :, 3] > 0.5
    h, s, v = hsv(a)
    rgb = a[:, :, :3]
    lum = rgb.mean(2)
    rlum = ref.mean()
    # chroma: the colour with its brightness taken out, so a shadowed cheek is still skin
    chroma = rgb / np.maximum(lum[:, :, None], 1e-3)
    rchroma = ref / max(rlum, 1e-3)
    dist = np.abs(chroma - rchroma).sum(2)
    skin = op & (dist < 0.16) & (lum > rlum * 0.72) & (lum < rlum * 1.2)
    outline = op & (v < 0.13)  # the black outline; very dark hair is a little lighter
    hair = op & ~skin & ~outline
    # specks of "hair" inside the skin (freckles, scars) aren't hair: keep only big pieces
    hair = keep_big(hair, 400)
    return skin, hair, outline


def keep_big(mask, min_px):
    out = np.zeros_like(mask)
    seen = np.zeros_like(mask)
    H, W = mask.shape
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        part = []
        while q:
            y, x = q.popleft()
            part.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if len(part) >= min_px:
            for y, x in part:
                out[y, x] = True
    return out


def grow(mask, px):
    m = Image.fromarray((mask * 255).astype("uint8")).filter(ImageFilter.MaxFilter(px * 2 + 1))
    return np.asarray(m) > 0


def beard_area():
    yy, xx = np.mgrid[0:480, 0:480]
    return (xx >= FACE_X[0]) & (xx <= FACE_X[1]) & (yy > EYE_Y + 30)


def grey(a, mask):
    """The masked pixels as grey shading around 0.85 (so a tint shows close to its own colour),
    with the outline left black; everything else transparent."""
    lum = a[:, :, :3].mean(2)
    ref = np.median(lum[mask]) if mask.any() else 0.5
    g = np.clip(lum / max(ref, 1e-3) * 0.85, 0, 1)
    out = np.zeros_like(a)
    for c in range(3):
        out[:, :, c] = g
    out[:, :, 3] = 0
    out[mask, 3] = a[mask, 3]
    return out


def layer(a, piece, outline):
    """A hair or beard piece with its share of the outline: dark pixels next to it."""
    ol = outline & grow(piece, 6)
    g = grey(a, piece)
    g[ol, :3] = a[ol, :3]
    g[ol, 3] = a[ol, 3]
    return g


def divide_by(a, ref):
    """For tinting with a skin tone: the image divided by its skin colour."""
    out = a.copy()
    for c in range(3):
        out[:, :, c] = np.clip(a[:, :, c] / max(ref[c], 1e-3), 0, 1)
    return out


def split_brows(face):
    """A face's eyebrows (the coloured strokes above the eye whites) and the rest."""
    a = arr(face)
    h, s, v = hsv(a)
    op = a[:, :, 3] > 0.3
    white = op & (v > 0.85) & (s < 0.15)
    outline = op & (v < 0.2)
    brow = np.zeros(op.shape, bool)
    for x in range(a.shape[1]):
        ys = np.nonzero(white[:, x])[0]
        top = ys.min() if len(ys) else a.shape[0] // 2
        col = op[:top, x] & ~outline[:top, x] & ~white[:top, x]
        brow[:top, x] = col
    brow = keep_big(brow, 60)
    rest = a.copy()
    rest[brow, 3] = 0
    return img(rest), img(grey(a, brow))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    wanted = {BASE_HEAD, BLUSH_FROM}
    for table in (HAIR, BEARDS, FACES, OUTFITS):
        wanted |= {v[0] for v in table.values()}
    chars = load_chars(sys.argv[1], wanted)
    for sub in ("hair", "beard", "face", "outfit", "hands"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)

    # Base heads: bald, divided by the skin colour; the female one with the women's cheek blush
    base = arr(chars[BASE_HEAD]["Head"])
    skin_ref = skin_colour(base)
    img(divide_by(base, skin_ref)).save(os.path.join(OUT, "base_male.png"))
    wb = arr(chars[BLUSH_FROM]["Head"])
    h, s, v = hsv(wb)
    blush = (wb[:, :, 3] > 0.5) & ((h > 0.9) | (h < 0.02)) & (s > 0.2) & (v > 0.75) & beard_area()
    fem = base.copy()
    fem[blush] = wb[blush]
    img(divide_by(fem, skin_ref)).save(os.path.join(OUT, "base_female.png"))
    for hand in ("Left Hand", "Right Hand"):
        img(divide_by(arr(chars[BASE_HEAD][hand]), skin_ref)).save(os.path.join(OUT, "hands", hand + ".png"))

    data = {"skin_ref": [round(float(c), 4) for c in skin_ref], "hair": [], "beards": [], "faces": [], "outfits": []}
    for hid, (ch, label) in HAIR.items():
        a = arr(chars[ch]["Head"])
        skin, hair, outline = head_masks(a)
        hair = hair & ~(beard_area() & (np.mgrid[0:480, 0:480][0] > EYE_Y + 60))
        img(layer(a, keep_big(hair, 400), outline)).save(os.path.join(OUT, "hair", hid + ".png"))
        data["hair"].append({"id": hid, "label": label})
    for bid, (ch, label) in BEARDS.items():
        a = arr(chars[ch]["Head"])
        skin, hair, outline = head_masks(a)
        img(layer(a, keep_big(hair & beard_area(), 300), outline)).save(os.path.join(OUT, "beard", bid + ".png"))
        data["beards"].append({"id": bid, "label": label})
    for fid, (ch, label, gender) in FACES.items():
        d = os.path.join(OUT, "face", fid)
        os.makedirs(d, exist_ok=True)
        for n in ("01", "02", "03"):
            rest, brows = split_brows(chars[ch]["Face " + n])
            rest.save(os.path.join(d, "Face %s.png" % n))
            brows.save(os.path.join(d, "Brows %s.png" % n))
        data["faces"].append({"id": fid, "label": label, "gender": gender})
    for oid, (ch, label) in OUTFITS.items():
        d = os.path.join(OUT, "outfit", oid)
        os.makedirs(d, exist_ok=True)
        for p in OUTFIT_PARTS:
            chars[ch][p].save(os.path.join(d, p + ".png"))
        data["outfits"].append({"id": oid, "label": label})
    with open(os.path.join(OUT, "appearance.json"), "w") as f:
        json.dump(data, f, indent=1)
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
