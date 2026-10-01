#!/usr/bin/env python3
"""Draw placeholder gear that fits the zombie rig's part canvases exactly.

    python tools/make_gear_art.py [--rig assets/rigs/zombie] [--out assets/gear]

Output layout (one folder per gear id, one PNG per rig object it draws over):
    gear/weapon/<id>/Sword.png              400x128, grip at (73, 59), blade points +x
    gear/helmet/<id>/Head.png               480x480, same canvas as the Head part
    gear/chest/<id>/Body.png                320x320, same canvas as the Body part
    gear/chest/<id>/Right Arm.png, Left Arm.png   128x128
    gear/<slot>/<id>/icon.png               128x128 for the inventory

The game looks gear up as  res://assets/gear/<slot>/<gear id>/<Object>.png  where the gear id
is the ItemBase id. To use real art, just overwrite these PNGs keeping the same canvas size
and alignment. Helmets and armour are derived from the Head/Body silhouettes, so they always
hug the character. Re-run this for a new rig of the same family.
"""
import argparse
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

SS = 3                        # supersampling for drawn shapes
OUT_COL = (0.11, 0.10, 0.10)  # cartoon outline colour, matches the pack's dark outlines


# ---------------------------------------------------------------- helpers
def load_alpha(path):
    return np.array(Image.open(path).convert("RGBA").getchannel("A")).astype(np.float32) / 255.0


def save_rgba(path, rgb, a):
    path.parent.mkdir(parents=True, exist_ok=True)
    arr = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA").save(path)


def disk(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def dilate(a, r):
    return cv2.dilate(a, disk(r)) if r > 0 else a


def erode(a, r):
    return cv2.erode(a, disk(r)) if r > 0 else a


def blur(a, s):
    return cv2.GaussianBlur(a, (0, 0), s)


def shift(a, dx, dy):
    m = np.float32([[1, 0, dx], [0, 1, dy]])
    return cv2.warpAffine(a, m, (a.shape[1], a.shape[0]))


class Canvas:
    """Supersampled drawing surface producing an antialiased float mask (h, w)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("L", (w * SS, h * SS), 0)
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, v=255):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=v)

    def ellipse(self, box, v=255):
        self.d.ellipse([c * SS for c in box], fill=v)

    def rect(self, x0, y0, x1, y1, v=255, r=0):
        if r:
            self.d.rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=r * SS, fill=v)
        else:
            self.d.rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=v)

    def line(self, pts, width, v=255):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=v, width=max(1, int(width * SS)), joint="curve")

    def array(self):
        return np.array(self.img.resize((self.w, self.h), Image.LANCZOS)).astype(np.float32) / 255.0


def bezier(p0, p1, p2, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / n for i in range(n + 1))]


class Layer:
    """RGBA accumulation buffer with 'paint a shape with a cartoon outline'."""

    def __init__(self, w, h):
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)
        self.w, self.h = w, h

    def blend(self, m, color):
        col = np.broadcast_to(np.array(color, np.float32), self.rgb.shape) if np.ndim(color) == 1 else color
        m3 = m[..., None]
        oa = m + self.a * (1 - m)
        self.rgb = np.where(oa[..., None] > 1e-6,
                            (col * m3 + self.rgb * self.a[..., None] * (1 - m3)) / np.maximum(oa[..., None], 1e-6), 0)
        self.a = oa

    def paint(self, mask, color, outline=0):
        if outline:
            self.blend(np.clip(dilate(mask, outline) - mask, 0, 1), OUT_COL)
        self.blend(mask, color)

    def detail(self, mask, color, strength=1.0):
        """Draw inside the existing silhouette only."""
        self.blend(mask * self.a * strength, color)


def shade(mask, base, rim=9.0, dark=0.32, light=0.20):
    """Rounded cartoon shading for a flat colour: darker toward the edge, lit from the top-left."""
    m = (mask > 0.5).astype(np.uint8)
    dist = cv2.distanceTransform(m, cv2.DIST_L2, 5)
    edge = np.clip(dist / rim, 0, 1)
    k = 1 - dark * (1 - edge) ** 1.4
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    grad = (xx / w) * 0.4 + (yy / h) * 0.6
    col = np.array(base, np.float32)[None, None, :] * k[..., None] * (1 + light * (0.5 - grad))[..., None]
    hl = np.clip(mask - shift(mask, 7, 7), 0, 1)
    hl = blur(hl, 1.5)
    col = col + hl[..., None] * 0.22
    return np.clip(col, 0, 1)


def darker(c, f):
    return tuple(max(0.0, v * f) for v in c)


# ---------------------------------------------------------------- weapons (400x128)
GRIP_Y = 63.5


def sword_rusty():
    L = Layer(400, 128)
    # blade
    c = Canvas(400, 128)
    c.poly([(158, 46), (352, 47), (390, 63.5), (352, 80), (158, 81)])
    blade = c.array()
    col = shade(blade, (0.68, 0.71, 0.74), rim=10)
    L.paint(blade, col, 4)
    # fuller + edge highlight
    c = Canvas(400, 128); c.line([(176, 63.5), (350, 63.5)], 6); L.detail(c.array(), (0.45, 0.48, 0.52), 0.8)
    c = Canvas(400, 128); c.line([(170, 50), (350, 51.5), (382, 63)], 3); L.detail(blade * c.array(), (0.93, 0.95, 0.97), 0.85)
    # rust
    rng = np.random.default_rng(7)
    rust = Canvas(400, 128)
    for _ in range(26):
        x, y, r = rng.uniform(175, 360), rng.uniform(48, 80), rng.uniform(3, 8)
        rust.ellipse((x - r, y - r * .8, x + r, y + r * .8))
    L.detail(rust.array() * blade, (0.62, 0.34, 0.16), 0.85)
    nick = Canvas(400, 128)
    for x in (230, 285, 318):
        nick.poly([(x, 44), (x + 8, 44), (x + 4, 52)])
    L.blend(nick.array() * 0.0, (0, 0, 0))
    # crossguard
    c = Canvas(400, 128); c.rect(138, 27, 162, 100, r=8); guard = c.array()
    L.paint(guard, shade(guard, (0.55, 0.40, 0.22), rim=7), 4)
    # grip with wrap
    c = Canvas(400, 128); c.rect(44, 51, 142, 76, r=6); grip = c.array()
    L.paint(grip, shade(grip, (0.36, 0.22, 0.12), rim=6), 4)
    wrap = Canvas(400, 128)
    for x in range(52, 138, 14):
        wrap.line([(x, 51), (x + 8, 76)], 3)
    L.detail(wrap.array(), (0.18, 0.11, 0.06), 0.9)
    # pommel
    c = Canvas(400, 128); c.ellipse((20, 44, 50, 83)); pom = c.array()
    L.paint(pom, shade(pom, (0.62, 0.50, 0.24), rim=8), 4)
    return L


def axe_battle():
    L = Layer(400, 128)
    # handle
    c = Canvas(400, 128); c.rect(26, 52, 338, 76, r=8); handle = c.array()
    L.paint(handle, shade(handle, (0.52, 0.32, 0.16), rim=6), 4)
    grain = Canvas(400, 128)
    for y in (58, 64, 70):
        grain.line([(60, y), (250, y + 1)], 1.6)
    L.detail(grain.array(), (0.33, 0.19, 0.09), 0.7)
    c = Canvas(400, 128); c.ellipse((20, 46, 52, 82)); cap = c.array()
    L.paint(cap, shade(cap, (0.40, 0.40, 0.44), rim=8), 4)
    # back spike
    c = Canvas(400, 128); c.poly([(262, 47), (214, 63.5), (262, 80)]); spike = c.array()
    L.paint(spike, shade(spike, (0.55, 0.58, 0.62), rim=6), 4)
    # crescent head (edge faces +x)
    top = bezier((258, 44), (300, 2), (352, 12), 22)
    bot = bezier((352, 115), (300, 128), (258, 83), 22)
    edge = bezier((352, 12), (372, 64), (352, 115), 14)
    c = Canvas(400, 128); c.poly(top + edge[1:] + bot[1:]); head = c.array()
    L.paint(head, shade(head, (0.62, 0.66, 0.70), rim=11), 4)
    c = Canvas(400, 128); c.line(edge, 4); L.detail(c.array() * head, (0.96, 0.97, 1.0), 0.9)
    c = Canvas(400, 128); c.line(bezier((272, 42), (305, 16), (336, 22), 16), 3); L.detail(c.array() * head, (0.86, 0.88, 0.92), 0.6)
    # socket band
    c = Canvas(400, 128); c.rect(250, 42, 272, 86, r=4); band = c.array()
    L.paint(band, shade(band, (0.30, 0.30, 0.34), rim=5), 3)
    return L


# ---------------------------------------------------------------- helmets (Head canvas)
def brim_line(w, h, front_y):
    xx = np.arange(w, dtype=np.float32)
    return front_y + 14 * (1 - np.clip((xx - 70) / 230, 0, 1))


def head_geometry(head_a, front_y):
    h, w = head_a.shape
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32)
    brim = brim_line(w, h, front_y)[None, :]
    region = np.clip((brim - yy) / 1.5 + 0.5, 0, 1)
    skull = dilate((head_a > 0.5).astype(np.float32), 5)
    cols_top = np.array([np.argmax(head_a[:, x] > 0.5) if (head_a[:, x] > 0.5).any() else h for x in range(w)], np.float32)
    return skull * region, brim[0], yy, cols_top


def helmet_leather_cap(head_a, front_y):
    h, w = head_a.shape
    cap, brim, yy, top = head_geometry(head_a, front_y)
    L = Layer(w, h)
    L.paint(cap, shade(cap, (0.58, 0.38, 0.20), rim=14), 4)
    band = cap * np.clip((yy - (brim[None, :] - 26)) / 1.5 + 0.5, 0, 1)
    L.paint(band, shade(band, (0.36, 0.22, 0.12), rim=7), 3)
    seams = Canvas(w, h)
    cx, cy = 250, 66
    for ex in (100, 175, 335, 395):
        seams.line(bezier((cx, cy), ((cx + ex) / 2 + (ex - cx) * .15, 130), (ex, brim[int(ex)] - 30), 20), 3)
    L.detail(seams.array() * cap, (0.28, 0.16, 0.08), 0.85)
    stitch = Canvas(w, h)
    for x in range(78, 420, 16):
        yb = brim[min(x, w - 1)] - 13
        stitch.line([(x, yb), (x + 7, yb)], 2.2)
    L.detail(stitch.array() * band, (0.86, 0.72, 0.45), 0.9)
    button = Canvas(w, h); button.ellipse((cx - 11, cy - 6, cx + 11, cy + 14)); b = button.array()
    L.paint(b, shade(b, (0.42, 0.26, 0.14), rim=5), 3)
    return L, cap


def helmet_iron_helm(head_a, front_y):
    h, w = head_a.shape
    cap, brim, yy, top = head_geometry(head_a, front_y)
    L = Layer(w, h)
    # plume first so the dome overlaps its base
    xs = np.arange(150, 345)
    upper, lower = [], []
    for x in xs:
        t = (x - 150) / 195.0
        bump = 46 * math.sin(math.pi * t) ** 0.75
        upper.append((x, top[x] - 3 - bump))
        lower.append((x, top[x] + 14))
    c = Canvas(w, h); c.poly(upper + lower[::-1]); plume = c.array()
    L.paint(plume, shade(plume, (0.70, 0.14, 0.14), rim=10), 4)
    L.paint(cap, shade(cap, (0.66, 0.70, 0.74), rim=16), 4)
    band = cap * np.clip((yy - (brim[None, :] - 28)) / 1.5 + 0.5, 0, 1)
    L.paint(band, shade(band, (0.47, 0.50, 0.55), rim=8), 3)
    rivets = Canvas(w, h)
    for x in range(92, 415, 34):
        yb = brim[min(x, w - 1)] - 14
        rivets.ellipse((x - 4.5, yb - 4.5, x + 4.5, yb + 4.5))
    L.detail(rivets.array(), (0.92, 0.94, 0.97), 0.95)
    ridge = Canvas(w, h)
    ridge.line([(x, top[x] + 8) for x in range(150, 345, 6)], 7)
    L.detail(ridge.array() * cap, (0.46, 0.49, 0.54), 0.9)
    shine = Canvas(w, h)
    shine.line(bezier((130, brim[130] - 60), (150, 120), (215, 96), 18), 6)
    L.detail(shine.array() * cap, (0.96, 0.97, 1.0), 0.75)
    return L, cap


# ---------------------------------------------------------------- chest armour (Body + arms)
def rings_mask(w, h, r=7, step=12):
    c = Canvas(w, h)
    for row, y in enumerate(range(0, h + step, step)):
        for x in range(-step, w + step, step):
            xo = x + (step // 2 if row % 2 else 0)
            c.d.ellipse([(xo - r) * SS, (y - r) * SS, (xo + r) * SS, (y + r) * SS], outline=255, width=int(2.2 * SS))
    return c.array()


def diamonds_mask(w, h, step=30):
    c = Canvas(w, h)
    for k in range(-h, w + h, step):
        c.line([(k, 0), (k + h, h)], 2.4)
        c.line([(k, h), (k + h, 0)], 2.4)
    return c.array()


def chest_set(body_a, right_a, left_a, kind):
    h, w = body_a.shape
    ys = np.where(body_a.max(axis=1) > 0.5)[0]
    y1 = int(ys.max())
    out = {}
    torso = dilate((body_a > 0.5).astype(np.float32), 3)
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32)
    L = Layer(w, h)
    if kind == "padded_vest":
        base, dark, belt_c = (0.58, 0.37, 0.19), (0.28, 0.16, 0.08), (0.30, 0.19, 0.10)
        L.paint(torso, shade(torso, base, rim=16), 4)
        L.detail(diamonds_mask(w, h) * torso, dark, 0.55)
    else:
        base, dark, belt_c = (0.62, 0.66, 0.70), (0.30, 0.33, 0.38), (0.34, 0.36, 0.40)
        L.paint(torso, shade(torso, base, rim=16), 4)
        L.detail(rings_mask(w, h) * torso, dark, 0.65)
    belt = torso * np.clip((yy - (y1 - 40)) / 1.5 + 0.5, 0, 1)
    L.paint(belt, shade(belt, belt_c, rim=8), 3)
    buckle = Canvas(w, h); buckle.rect(196, y1 - 32, 224, y1 - 8, r=4); b = buckle.array()
    L.paint(b, shade(b, (0.86, 0.72, 0.28), rim=5), 3)
    out["Body"] = (L.rgb, L.a)
    for name, arm_a in (("Right Arm", right_a), ("Left Arm", left_a)):
        ah, aw = arm_a.shape
        m = dilate((arm_a > 0.5).astype(np.float32), 3)
        A = Layer(aw, ah)
        A.paint(m, shade(m, base, rim=12), 3)
        A.detail((diamonds_mask(aw, ah, 22) if kind == "padded_vest" else rings_mask(aw, ah, 6, 10)) * m, dark, 0.55)
        ay = np.where(arm_a.max(axis=1) > 0.5)[0]
        cuff = m * np.clip(((np.mgrid[0:ah, 0:aw][0]) - (ay.max() - 22)) / 1.5 + 0.5, 0, 1)
        A.paint(cuff, shade(cuff, belt_c, rim=6), 2)
        out[name] = (A.rgb, A.a)
    return out


# ---------------------------------------------------------------- icons
def make_icon(rgb, a, rotate=0.0):
    img = Image.fromarray((np.dstack([rgb, a]) * 255 + 0.5).astype(np.uint8), "RGBA")
    if rotate:
        pad = max(img.size)
        big = Image.new("RGBA", (pad * 2, pad * 2), (0, 0, 0, 0))
        big.paste(img, (pad - img.width // 2, pad - img.height // 2))
        img = big.rotate(rotate, resample=Image.BICUBIC)
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    img = img.crop(bbox)
    s = 112 / max(img.size)
    img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    out.paste(img, ((128 - img.width) // 2, (128 - img.height) // 2))
    return out


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rig", default="assets/rigs/zombie")
    ap.add_argument("--out", default="assets/gear")
    args = ap.parse_args()
    rig_dir, out = Path(args.rig), Path(args.out)
    rig = json.load(open(rig_dir / "rig.json"))
    objs = rig["objects"]
    idle = rig["animations"]["Idle"]["frames"][0]
    F = 10

    def row(name):
        i = objs.index(name)
        return idle[i * F:(i + 1) * F]

    face_name = next(o for o in objs if o.startswith("Face"))
    front_y = (row(face_name)[2] - row("Head")[2]) + 30     # brim sits 20px above the brow line
    parts = rig_dir / "parts"
    head_a = load_alpha(parts / "Head.png")

    # weapons
    for gid, fn in (("rusty_sword", sword_rusty), ("battle_axe", axe_battle)):
        L = fn()
        save_rgba(out / "weapon" / gid / "Sword.png", L.rgb, L.a)
        make_icon(L.rgb, L.a, rotate=50).save(out / "weapon" / gid / "icon.png")

    # helmets
    for gid, fn in (("leather_cap", helmet_leather_cap), ("iron_helm", helmet_iron_helm)):
        L, _ = fn(head_a, front_y)
        save_rgba(out / "helmet" / gid / "Head.png", L.rgb, L.a)
        make_icon(L.rgb, L.a).save(out / "helmet" / gid / "icon.png")

    # chest armour
    body_a, ra, la = load_alpha(parts / "Body.png"), load_alpha(parts / "Right Arm.png"), load_alpha(parts / "Left Arm.png")
    for gid in ("padded_vest", "chain_mail"):
        layers = chest_set(body_a, ra, la, gid)
        for name, (rgb, a) in layers.items():
            save_rgba(out / "chest" / gid / f"{name}.png", rgb, a)
        make_icon(*layers["Body"]).save(out / "chest" / gid / "icon.png")
    print("gear art written to", out)


if __name__ == "__main__":
    main()
