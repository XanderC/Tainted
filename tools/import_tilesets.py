"""Imports the CraftPix "2D RPG" tilesets as map themes (assets/tiles/<theme>/), from the packs on the
NAS (Tainted > assets > maps), and makes the wall pieces a maze needs from them (<theme>/walls/).

The packs all share one layout of 18 ground pieces (land_N.png, 256 px each): a raised plateau's
corners and edges, its bottom lip, the rock cliff below it, and stairs. They are drawn for single
square plateaus, so they have no inner (concave) corners, which a maze needs wherever two walls meet,
and each piece's surface is drawn a little differently, so pieces only join cleanly at their edges.
scripts/wall_tiles.gd draws every quarter of a wall cell on its own, so here every piece is remade on
the middle piece's surface (land_6), keeping only its own edge band, and the missing ones are added:

  top_left top top_right / left middle right / lip_left lip lip_right   the plateau (land_1 ... 18)
  inner_tl inner_tr      the top edge turning into the left / right edge (a concave corner)
  inner_bl inner_br      the bottom lip turning into the left / right edge
  cliff_left cliff cliff_right      the rock face under a plateau's lip (land_12, 17, 14)
  ledge_left ledge ledge_right      a rock face with nothing above it (a wall one cell thick): the
                                    cliff with a thin strip of plateau along its top

Plateau surfaces are darkened by the theme's tint so they read as out of bounds. The pack's own
land_N pieces are kept as they are, for painting ground by hand in the map editor.

Usage:  python tools/import_tilesets.py [--src <folder with the zips>] [theme ...]
"""
import argparse
import os
import zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
TILES = os.path.join(HERE, "..", "assets", "tiles")
SRC = "Y:/Tainted/assets/maps"  # the NAS share (\\OPENMEDIAVAULT\Storage)

# theme: (pack zip, plateau tint)
THEMES = {
    "desert": ("craftpix-891121-free-2d-rpg-desert-tileset.zip", (0.86, 0.76, 0.66)),
    "woodland": ("craftpix-611011-2d-rpg-autumn-tileset.zip", (0.78, 0.80, 0.70)),
}
SIZE = 256
HALF = SIZE // 2
KEEP, FADE = 52, 92  # an edge piece keeps its own pixels this far in from its edges, then fades to land_6

# wall piece: (pack piece, the sides with an edge)
PLATEAU = {
    "top_left": ("land_1", "tl"), "top": ("land_2", "t"), "top_right": ("land_3", "tr"),
    "left": ("land_15", "l"), "middle": ("land_6", ""), "right": ("land_16", "r"),
    "lip_left": ("land_9", "bl"), "lip": ("land_18", "b"), "lip_right": ("land_11", "br"),
}
CLIFF = {"cliff_left": ("land_12", "l"), "cliff": ("land_17", ""), "cliff_right": ("land_14", "r")}
STRIP_TOP, STRIP_LIP = 40, 56  # px of the top edge and of the lip that make a ledge's strip


def extract(zip_path, out):
    """The pack's PNG pieces (not its preview) and its licence and readme, into `out`."""
    os.makedirs(out, exist_ok=True)
    text = {"TXT/license.txt": "LICENSE_craftpix.txt", "TXT/readme.txt": "README_craftpix.txt"}
    with zipfile.ZipFile(zip_path) as z:
        for n in z.namelist():
            base = os.path.basename(n)
            if n in text:
                base = text[n]
            elif not n.startswith("PNG/") or not base.endswith(".png") or base.startswith("Preview"):
                continue
            with open(os.path.join(out, base.lower() if n not in text else base), "wb") as f:
                f.write(z.read(n))


def arr(folder, name):
    return np.asarray(Image.open(os.path.join(folder, name + ".png")).convert("RGBA")).astype(np.float32)


def save(a, path):
    Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA").save(path)


def on_surface(piece, surface, sides):
    """`piece` near its `sides` (any of "tblr"), fading into `surface` further in."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    d = np.full((SIZE, SIZE), 1e9, np.float32)
    for s, dist in (("t", yy), ("b", SIZE - 1 - yy), ("l", xx), ("r", SIZE - 1 - xx)):
        if s in sides:
            d = np.minimum(d, dist)
    w = np.clip((FADE - d) / (FADE - KEEP), 0.0, 1.0)[..., None]
    out = piece * w + surface * (1.0 - w)
    out[..., 3] = np.where(w[..., 0] > 0, piece[..., 3], surface[..., 3])
    return out


def outline(a, side, i):
    """How far in from `side` ("l", "r", "t") row / column `i` of `a` turns opaque (None: never)."""
    line = {"l": a[i, :, 3], "r": a[i, ::-1, 3], "t": a[:, i, 3]}[side] > 128
    return int(np.argmax(line)) if line.any() else None


def splice(corner, straight, side, cut_axis, lo, hi, straight_after):
    """`corner` with `straight` taking over past a cut, so a corner piece's quarter lines match the
    straight edge pieces exactly. The cut is a row (cut_axis 0) or column (1) between lo and hi where
    the two outlines along `side` ("l", "r", "t") are closest, or for "b" (the lip, which has no
    transparent outline) where the bottom bands differ least; it is softened over a few px.
    `straight` is used after the cut (rows below / columns right) if straight_after, else before."""
    def miss(i):
        if side == "b":
            return float(np.abs(corner[SIZE - 64:, i, :3] - straight[SIZE - 64:, i, :3]).mean())
        p, q = outline(corner, side, i), outline(straight, side, i)
        return 1e9 if p is None or q is None else abs(p - q)
    cut = min(range(lo, hi), key=lambda i: (miss(i), abs(i - (lo + hi) / 2)))
    idx = np.arange(SIZE, dtype=np.float32)
    w = np.clip((idx - cut) / 8.0 + 0.5, 0.0, 1.0)
    if not straight_after:
        w = 1.0 - w
    w = (w[:, None] if cut_axis == 0 else w[None, :])[..., None]
    return straight * w + corner * (1.0 - w)


def edge_from_start(a, axis):
    """Median distance (px) from the start of `axis` to where the piece turns opaque."""
    opaque = a[..., 3] > 128
    if axis == 1:
        opaque = opaque.T
    first = np.argmax(opaque, axis=0)
    return float(np.median(first[opaque.any(axis=0)]))


def lip_from_bottom(a):
    """Median distance (px) from the bottom to the lip's outline: the darkest row near the bottom."""
    lum = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
    band = lum[SIZE - 76:, :]
    return float(np.median(76 - np.argmin(band, axis=0)))


def inner(horiz, vert, h_dist, v_dist, corner, middle):
    """An inner corner in `corner` ("tl" ...) on the middle piece: `horiz` (the piece with the top
    edge or lip, its outline h_dist px in from that side) turning into `vert` (the left or right
    edge, v_dist px in). Near the side the horizontal piece shows and near the top / bottom the
    vertical one, split along the line from the corner through the point where the outlines cross."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    u = xx if corner[1] == "l" else SIZE - 1 - xx   # distance from the side
    v = yy if corner[0] == "t" else SIZE - 1 - yy   # distance from the top / bottom
    joined = np.where((v * v_dist > u * h_dist)[..., None], horiz, vert)
    out = middle.copy()
    ys = slice(0, HALF) if corner[0] == "t" else slice(HALF, SIZE)
    xs = slice(0, HALF) if corner[1] == "l" else slice(HALF, SIZE)
    out[ys, xs] = joined[ys, xs]
    return out


def tinted(a, tint):
    out = a.copy()
    out[..., :3] *= np.array(tint, np.float32)
    return out


def make_walls(folder, tint):
    out_dir = os.path.join(folder, "walls")
    os.makedirs(out_dir, exist_ok=True)
    middle = arr(folder, "land_6")
    p = {name: on_surface(arr(folder, src), middle, sides) for name, (src, sides) in PLATEAU.items()}
    # The outer corners keep the pack's own corner only near it: away from the corner their edges
    # are the straight pieces', so they meet those at every quarter line
    lo, hi = (64, 120), (136, 192)
    for name, side_name, rows, edge_name, cols in (
            ("top_left", "left", lo, "top", lo), ("top_right", "right", lo, "top", hi),
            ("lip_left", "left", hi, "lip", lo), ("lip_right", "right", hi, "lip", hi)):
        left = side_name == "left"
        c = splice(p[name], p[side_name], "l" if left else "r", 0, *rows, straight_after=edge_name == "top")
        p[name] = splice(c, p[edge_name], "t" if edge_name == "top" else "b", 1, *cols, straight_after=left)
    t = edge_from_start(p["top"], 0)
    lft = edge_from_start(p["left"], 1)
    rgt = edge_from_start(p["right"][:, ::-1], 1)
    b = lip_from_bottom(p["lip"])
    p["inner_tl"] = inner(p["top"], p["left"], t, lft, "tl", middle)
    p["inner_tr"] = inner(p["top"], p["right"], t, rgt, "tr", middle)
    p["inner_bl"] = inner(p["lip"], p["left"], b, lft, "bl", middle)
    p["inner_br"] = inner(p["lip"], p["right"], b, rgt, "br", middle)
    for name, a in p.items():
        save(tinted(a, tint), os.path.join(out_dir, name + ".png"))

    cliff = arr(folder, "land_17")
    for name, (src, sides) in CLIFF.items():
        c = on_surface(arr(folder, src), cliff, sides)
        save(c, os.path.join(out_dir, name + ".png"))
        # The ledge: the plateau's top edge and lip squeezed into a strip over the cliff's top
        end = {"cliff_left": "_left", "cliff": "", "cliff_right": "_right"}[name]
        strip = np.concatenate([p["top" + end][:STRIP_TOP], p["lip" + end][SIZE - STRIP_LIP:]])
        ledge = c.copy()
        h = STRIP_TOP + STRIP_LIP
        a = strip[..., 3:4] / 255.0
        ledge[:h, :, :3] = tinted(strip, tint)[..., :3] * a + c[:h, :, :3] * (1.0 - a)
        ledge[:h, :, 3] = np.maximum(strip[..., 3], c[:h, :, 3])
        ledge[:STRIP_TOP, :, 3] = strip[:STRIP_TOP, :, 3]  # open floor above the strip's outline
        save(ledge, os.path.join(out_dir, "ledge" + end + ".png"))
    print("  walls/: edges top %.0f, left %.0f, right %.0f, lip %.0f px in" % (t, lft, rgt, b))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("themes", nargs="*", default=list(THEMES))
    args = ap.parse_args()
    for theme in args.themes:
        zip_name, tint = THEMES[theme]
        out = os.path.join(TILES, theme)
        print(theme)
        extract(os.path.join(args.src, zip_name), out)
        make_walls(out, tint)


if __name__ == "__main__":
    main()
