"""Makes the gem and rune icons from the concept sheet tools/art/gems_runes.jpg (8 red gems, Chipped
to Flawless Royal, and the 33 Diablo 2 runes, each in a dashed box on a light grey ground):

  assets/icons/gems/<type>_<tier>.png - the 8 gem tiers (GemDef) in each colour. The sheet has only the
                                        red gems: the red of each is turned to green, yellow, purple
                                        or (Diamond) a pale blue-white; the crown's gold and the
                                        dark outline stay as they are
  assets/icons/runes/<rank>.png       - the 33 runes in ladder order (SocketRune: El = 1 ... Zod = 33)

Each icon is the patch of its box that isn't the grey ground (a Chipped gem is three bits), its edge
softened by how dark each edge pixel is against the ground, and fitted into 128 x 128. The sheet is
small (a gem is about 35 px), so icons are enlarged about 3.5 times.

Usage:  python tools/import_gem_sheet.py
"""
import colorsys
import os
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
SHEET = os.path.join(HERE, "art", "gems_runes.jpg")
OUT = os.path.join(HERE, "..", "assets", "icons")
SIZE = 128
GROUND = np.array([222.0, 222.0, 222.0])
GROUND_TOL = 36
RUNE_TOL = 150  # runes: a stone is much darker than the ground, and the box and names fade into it
HALF = 23  # a box's inside, from its centre (the dashed outline is at 25)

GEM_X0, GEM_DX, GEM_Y = 58.3, 58.7, 50  # the 8 gem boxes' centres
RUNE_X0, RUNE_DX = 58.3, 68.9  # the 7 columns of rune boxes
RUNE_Y = [139, 192, 243, 293, 343]  # and the 5 rows (the last holds 5)
GEM_TYPES = ["ruby", "emerald", "topaz", "amethyst", "diamond"]
# Hue (0-1) a type's red is turned to, and for Diamond how pale it goes
HUES = {"ruby": None, "emerald": 0.34, "topaz": 0.125, "amethyst": 0.78, "diamond": 0.56}


def _central(fg, largest_only=False):
    """Only the pieces of `fg` (a box's non-ground) centred near the middle of the box: not the bits
    of its dashed outline or of the name under it that reach into the edges."""
    h, w = fg.shape
    seen = np.zeros_like(fg)
    keep = np.zeros_like(fg)
    best = []
    for y in range(h):
        for x in range(w):
            if not fg[y, x] or seen[y, x]:
                continue
            stack, pts = [(y, x)], []
            seen[y, x] = True
            while stack:
                cy, cx = stack.pop()
                pts.append((cy, cx))
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and fg[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            ys, xs = zip(*pts)
            my, mx = sum(ys) / len(ys), sum(xs) / len(xs)
            if len(pts) >= 6 and abs(my - h / 2) < 17 and abs(mx - w / 2) < 17:
                best.append(pts)
    if largest_only and best:
        best = [max(best, key=len)]
    for pts in best:
        for p in pts:
            keep[p] = True
    if largest_only:  # one stone: shave off thin bits the dashed box sticks to it
        keep = _open(keep, 2)
    return keep


def _shift(m, dy, dx):
    return np.roll(np.roll(m, dy, 0), dx, 1)


def _open(m, r):
    """`m` with anything thinner than about 2r pixels gone: eroded r times, then grown back r times."""
    for _ in range(r):
        m = m & _shift(m, 1, 0) & _shift(m, -1, 0) & _shift(m, 0, 1) & _shift(m, 0, -1)
    for _ in range(r):
        m = m | _shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)
    return m


def cut(sheet, cx, cy, largest_only=False, tol=GROUND_TOL):
    """The piece in the box centred at (cx, cy): RGBA, cropped to it."""
    x0, y0 = int(round(cx)) - HALF, int(round(cy)) - HALF
    a = sheet[y0:y0 + 2 * HALF, x0:x0 + 2 * HALF]
    h, w, _ = a.shape
    near = np.abs(a - GROUND).sum(2) < tol
    ground = np.zeros((h, w), bool)
    q = deque([(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)])
    while q:
        y, x = q.popleft()
        if ground[y, x] or not near[y, x]:
            continue
        ground[y, x] = True
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w:
                q.append((ny, nx))
    fg = _central(~ground, largest_only)
    lum = a @ np.array([0.299, 0.587, 0.114])
    edge = fg & (np.roll(ground, 1, 0) | np.roll(ground, -1, 0) | np.roll(ground, 1, 1) | np.roll(ground, -1, 1))
    alpha = fg.astype(np.float32)
    alpha[edge] = np.clip((222.0 - lum[edge]) / 110.0, 0.0, 1.0)
    ys, xs = np.nonzero(fg)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    rgba = np.dstack([a, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").crop(box)


def fit(im, margin=0.92):
    s = min(SIZE * margin / im.width, SIZE * margin / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE))
    out.alpha_composite(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2))
    return out


def recolour(im, kind):
    """The red parts of a gem turned to `kind`'s colour (the gold crown, sparkles and outline stay)."""
    hue = HUES[kind]
    if hue is None:
        return im
    a = np.asarray(im).astype(np.float32) / 255.0
    out = a.copy()
    flat = a.reshape(-1, 4)
    res = out.reshape(-1, 4)
    for i in range(flat.shape[0]):
        r, g, b, al = flat[i]
        if al <= 0.0:
            continue
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s > 0.12 and (h < 0.085 or h > 0.93):  # a red
            if kind == "diamond":
                s, v = s * 0.38, min(1.0, v * 1.12 + 0.08)
            r, g, b = colorsys.hsv_to_rgb(hue, s, v)
            res[i, :3] = (r, g, b)
    return Image.fromarray((out * 255.0).clip(0, 255).astype(np.uint8), "RGBA")


def main():
    sheet = np.asarray(Image.open(SHEET).convert("RGB")).astype(np.float32)
    os.makedirs(os.path.join(OUT, "gems"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "runes"), exist_ok=True)
    for tier in range(1, 9):
        red = fit(cut(sheet, GEM_X0 + (tier - 1) * GEM_DX, GEM_Y))
        for kind in GEM_TYPES:
            recolour(red, kind).save(os.path.join(OUT, "gems", "%s_%d.png" % (kind, tier)))
    rank = 0
    for row, y in enumerate(RUNE_Y):
        for col in range(5 if row == 4 else 7):
            rank += 1
            fit(cut(sheet, RUNE_X0 + col * RUNE_DX, y, True, RUNE_TOL), 0.96).save(os.path.join(OUT, "runes", "%d.png" % rank))
    print("wrote %d gems and %d runes" % (8 * len(GEM_TYPES), rank))


if __name__ == "__main__":
    main()
