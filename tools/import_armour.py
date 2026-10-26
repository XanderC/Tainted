"""Makes body armour, gloves and boots from every character in the CraftPix chibi packs (on the NAS,
Tainted > assets > sprites): a character's body and arms are a suit of armour, its hands a pair of
gloves, its legs a pair of boots. Every pack draws these parts on the same canvases as the game's
rigs, so they are worn exactly as they are:

  assets/gear/chest/<id>/Body.png, Left Arm.png, Right Arm.png
  assets/gear/gloves/<id>/Left Hand.png, Right Hand.png
  assets/gear/boots/<id>/Left Leg.png, Right Leg.png
  assets/gear/<slot>/<id>/icon.png  - in the bag: the parts as they sit in the idle pose (tools/rig_pose.py),
                                      fitted into the item's cells (armour 2 x 3, gloves and boots 2 x 2)
  assets/gear/<slot>/catalog.json   - every piece: name, source character

A part is left out when it is the character's bare skin (bare hands, a bare chest) or bones: mostly
the colour of its own head's skin (the bare head shape in the character's vector source, as
tools/import_headgear.py finds it). Pieces drawn the same in several packs are kept once.
SKIP leaves out more (creatures whose bodies aren't clothes); ITEMS keeps the ids the game's items
(LootGenerator CHEST_BASES, GLOVE_BASES, BOOT_BASES) already use for their sources.

Usage:  python tools/import_armour.py [--src <folder with the zips>] [--dest <gear folder>]
        python tools/import_armour.py --sheets <folder>   (review sheets of everything found)
"""
import argparse
import hashlib
import io
import json
import multiprocessing
import os
import re
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from import_headgear import SKIN_TONES, Head, bare_head  # noqa: E402
from import_skins import SKINS as SKIN_SOURCES  # noqa: E402
from rig_pose import compose  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "assets", "gear")
SRC = "Y:/Tainted/assets/sprites"  # the NAS share (\\OPENMEDIAVAULT\Storage)
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)
BARE = 0.5  # a part this much its character's skin colour (not counting its outline) is bare
NEAR = 0.16  # colour distance (summed RGB, 0..1) that counts as the skin's

SLOTS = [
    ("chest", ["Body", "Left Arm", "Right Arm"], (2, 3), "Armour"),
    ("gloves", ["Left Hand", "Right Hand"], (2, 2), "Gloves"),
    ("boots", ["Left Leg", "Right Leg"], (2, 2), "Boots"),
]
# The game's items: id -> the skin (tools/import_skins.py) its art comes from
ITEMS = {
    "chest": {
        "linen_robe": "sage", "padded_vest": "merchant", "leather_jerkin": "forest_ranger_3",
        "chain_mail": "skeleton_crusader_2", "studded_leather": "stash_keeper", "brigandine": "caravan_guard",
        "crusader_hauberk": "skeleton_crusader_1", "scale_mail": "skeleton_warrior_2", "battle_plate": "battlemaster",
        "shadow_mail": "dark_elf_1", "frost_plate": "ghost_knight", "demon_plate": "blood_demon",
        "death_plate": "death_knight",
    },
    "gloves": {
        "linen_wraps": "mummy", "leather_gloves": "forest_ranger_3", "heavy_gloves": "battlemaster",
        "iron_gauntlets": "caravan_guard", "frost_gauntlets": "ghost_knight", "death_gauntlets": "blood_demon",
    },
    "boots": {
        "worn_boots": "zombie_villager_1", "leather_boots": "forest_ranger_3", "riding_boots": "stash_keeper",
        "chain_boots": "skeleton_crusader_2", "plated_boots": "caravan_guard", "frost_greaves": "ghost_knight",
        "death_greaves": "death_knight",
    },
}
# Library ids to leave out (see --sheets): creatures whose bodies aren't clothes (molten rock, fire,
# red demon skin, bone legs)
SKIP = {
    "golem_3_armour", "elementals_1_armour", "elementals_2_armour", "mimic_1_armour", "blood_demon_2_armour",
    "devil_armour",
    "blood_demon_2_gloves", "devil_gloves", "magician_demon_1_gloves", "elemental_spirits_1_gloves",
    "elemental_spirits_2_gloves", "elementals_2_gloves", "golem_3_gloves", "pyromancer_3_gloves",
    "zombie_villager_2_gloves",
    "elemental_spirits_1_boots", "elemental_spirits_2_boots", "elementals_1_boots", "mimic_3_boots",
    "skeleton_hunter_1_boots", "skeleton_viking_2_boots", "undead_archer_3_boots", "zombie_villager_2_boots",
    "devil_masked_guy_boots",
}
GENERIC = {"chibi", "free", "2d", "game", "sprites", "sprite", "character", "characters", "net", "pack", "craftpix"}


# ---------------------------------------------------------------- finding the parts

def characters(zip_path):
    """(character folder, {part: png bytes}, head .ai bytes) for each character in a pack."""
    out = []
    with zipfile.ZipFile(zip_path) as z:
        names = set(z.namelist())
        for n in sorted(names):
            m = re.match(r"(.+?)/PNG/Vector Parts/Body\.png$", n)
            if not m:
                continue
            char, base = m.group(1), n.rsplit("/", 1)[0]
            parts = {p: z.read("%s/%s.png" % (base, p)) for s in SLOTS for p in s[1] + ["Head"]
                     if "%s/%s.png" % (base, p) in names}
            ai = sorted(a for a in names if a.lower().endswith(".ai") and a.startswith(char + "/AI/"))
            out.append((char, parts, z.read(ai[0]) if ai else None))
    return out


def skin_colour(ai, head_png):
    """The character's skin: Head.png's colour where the bare head shape of its vector source shows
    (not under hair, a beard or headgear). The vector colours themselves are CMYK and don't come out
    as the PNGs do. None when too little of it shows (a great helm)."""
    if ai is None or head_png is None:
        return None
    png = np.asarray(Image.open(io.BytesIO(head_png)).convert("RGBA")).astype(np.float32) / 255.0
    head = Head(ai)
    scale = png.shape[1] / head.size
    first = [head.render({i}, 48.0 / head.size) for i in range(min(9, len(head.objects)))]
    skin_i = bare_head(first)[0]
    shape = head.render({skin_i}, scale)[..., 3] > 0.5
    over = head.render(set(range(skin_i + 1, len(head.objects))), scale)[..., 3] > 0.1
    h, w = min(shape.shape[0], png.shape[0]), min(shape.shape[1], png.shape[1])
    shows = shape[:h, :w] & ~over[:h, :w] & (png[:h, :w, 3] > 0.9)
    if shows.sum() < 0.02 * h * w:
        return None
    return np.median(png[:h, :w, :3][shows], axis=0)


def bare(png, skin):
    """Whether a part is mostly `skin` coloured."""
    a = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).astype(np.float32) / 255.0
    solid = a[..., 3] > 0.5
    if skin is None or not solid.any():
        return not solid.any()
    return bare_share(a, skin) > BARE


def bare_share(a, skin):
    """How much of a part's coloured pixels (not its outline) are its skin's colour, lit or shaded
    (brightness can change, the hue can't much)."""
    solid = (a[..., 3] > 0.5) & (a[..., :3].max(2) > 0.2)  # not the outline (small parts are mostly that)
    if not solid.any():
        return 0.0
    rgb = a[..., :3][solid]
    k = (rgb * skin).sum(1) / max((skin * skin).sum(), 1e-6)  # how lit: the skin colour scaled
    near = (np.abs(rgb - k[:, None] * skin).sum(1) < NEAR) & (k > 0.55) & (k < 1.3)
    return near.mean()


def scan(args):
    """Every character of one pack: (pack, character, {slot: ({part: png}, bare)})."""
    zip_path, pack = args
    out = []
    for char, parts, ai in characters(zip_path):
        skin = skin_colour(ai, parts.get("Head"))
        found = {}
        for slot, names, _, _ in SLOTS:
            if not all(p in parts for p in names):
                continue
            pngs = {p: parts[p] for p in names}
            # Bare when most of it is skin: a body by itself (arms can be bare under a vest)
            check = [names[0]] if slot == "chest" else names
            # Hands are often a different tone from the face: bare if they're any skin's colour
            tones = [skin] + ([np.array(t) for t in SKIN_TONES] if slot == "gloves" else [])
            is_bare = all(any(bare(pngs[p], t) for t in tones) for p in check)
            found[slot] = (pngs, is_bare)
        out.append((pack, char, found))
    return out


# ---------------------------------------------------------------- naming

def pack_slug(zip_name, zips):
    """The shortest run of words from a pack's name that names only it ("dark-elves")."""
    words = re.sub(r"^\d+-", "", re.sub(r"^craftpix-(net-)?", "", zip_name[:-4])).split("-")
    for k in range(1, len(words) + 1):
        cand = "-".join(words[:k])
        if len(cand) > 4 and sum(cand in z for z in zips) == 1:
            return cand
    return "-".join(words)


def piece_id(pack, char, clash):
    """A character's piece name: its folder name, with its pack's words when the name is shared."""
    words = re.findall(r"[a-z0-9]+", char.lower())
    if clash:
        words = [w for w in pack.split("-") if w not in GENERIC] + words
    out = []
    for w in words:
        if w not in out or w.isdigit():
            out.append(w)
    return "_".join(out)


def label(pid):
    return " ".join(w.upper() if w in ("ii", "iii") else w.capitalize() for w in pid.split("_"))


# ---------------------------------------------------------------- writing

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


def icon(slot, pngs, cells):
    imgs = {p: Image.open(io.BytesIO(b)).convert("RGBA") for p, b in pngs.items()}
    names = list(pngs)
    im = compose(imgs) if slot == "chest" else pair(imgs[names[0]], imgs[names[1]])
    return fit(im, cells[0] * CELL, cells[1] * CELL)


def library(src):
    """{slot: {id: (pngs, source)}}: every piece found, once each, the game's items under their ids."""
    zips = sorted(z for z in os.listdir(src) if z.endswith(".zip") and "(1)" not in z)
    packs = {z: pack_slug(z, zips) for z in zips}
    with multiprocessing.Pool() as pool:
        found = [c for part in pool.map(scan, [(os.path.join(src, z), packs[z]) for z in zips]) for c in part]
    counts = {}
    for _, char, _ in found:
        k = re.sub(r"[^a-z0-9]+", "_", char.lower())
        counts[k] = counts.get(k, 0) + 1
    # The items' sources: (pack words, character folder) -> item id, per slot
    item_of = {slot: {SKIN_SOURCES[skin]: gid for gid, skin in table.items()} for slot, table in ITEMS.items()}
    out = {slot: {} for slot, _, _, _ in SLOTS}
    seen = {slot: {} for slot, _, _, _ in SLOTS}
    for pack, char, pieces in found:
        clash = counts[re.sub(r"[^a-z0-9]+", "_", char.lower())] > 1
        for slot, _, _, word in SLOTS:
            if slot not in pieces:
                continue
            pngs, is_bare = pieces[slot]
            gid = next((g for (p, c), g in item_of[slot].items() if c == char and p in _zip_of(pack, packs)), None)
            if is_bare and not gid:  # (an item keeps its art whatever it looks like)
                continue
            pid = gid or "%s_%s" % (piece_id(pack, char, clash), word.lower())
            digest = hashlib.md5(b"".join(_pixels(b) for b in pngs.values())).hexdigest()
            if digest in seen[slot]:
                if gid:  # an item's own source wins over the copy found first
                    out[slot].pop(seen[slot][digest], None)
                else:
                    continue
            if pid in SKIP and not gid:
                continue
            seen[slot][digest] = pid
            out[slot][pid] = (pngs, "%s/%s" % (pack, char))
    return out


def _zip_of(pack, packs):
    return next(z for z, p in packs.items() if p == pack)


def _pixels(png):
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).tobytes()


def sheets(lib, folder):
    """Every piece's icon, labelled, a few sheets per slot."""
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "ids.json"), "w") as f:
        json.dump({slot: sorted(lib[slot]) for slot in lib}, f, indent=1)
    T, C, PER = 128, 10, 60
    for slot, _, cells, _ in SLOTS:
        ids = sorted(lib[slot])
        for page in range(0, len(ids), PER):
            chunk = ids[page:page + PER]
            sheet = Image.new("RGB", (C * T, ((len(chunk) + C - 1) // C) * (T + 14)), (80, 100, 75))
            d = ImageDraw.Draw(sheet)
            for k, pid in enumerate(chunk):
                im = icon(slot, lib[slot][pid][0], cells)
                im.thumbnail((T, T))
                x, y = (k % C) * T, (k // C) * (T + 14)
                sheet.paste(im, (x + (T - im.width) // 2, y + 14), im)
                d.text((x + 2, y + 1), pid[:21], fill=(255, 255, 160))
            sheet.save(os.path.join(folder, "%s_%d.png" % (slot, page // PER)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--dest", default=ROOT)
    ap.add_argument("--sheets", help="write review sheets of everything found to this folder instead")
    args = ap.parse_args()
    lib = library(args.src)
    if args.sheets:
        sheets(lib, args.sheets)
        print("sheets in", args.sheets, {s: len(v) for s, v in lib.items()})
        return
    for slot, _, cells, _ in SLOTS:
        # Keep the uniques' own looks (tools/make_unique_looks.py)
        old_path = os.path.join(args.dest, slot, "catalog.json")
        old = json.load(open(old_path)) if os.path.exists(old_path) else {}
        catalog = {k: v for k, v in old.items() if k.startswith("u_")}
        for pid, (pngs, source) in sorted(lib[slot].items()):
            d = os.path.join(args.dest, slot, pid)
            os.makedirs(d, exist_ok=True)
            for p, b in pngs.items():
                with open(os.path.join(d, p + ".png"), "wb") as f:
                    f.write(b)
            icon(slot, pngs, cells).save(os.path.join(d, "icon.png"))
            catalog[pid] = {"name": label(pid), "source": source, "item": pid in ITEMS[slot]}
        with open(os.path.join(args.dest, slot, "catalog.json"), "w") as f:
            json.dump(dict(sorted(catalog.items())), f, indent="\t")
        print("%s: %d" % (slot, len(catalog)))


if __name__ == "__main__":
    main()
