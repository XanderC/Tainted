"""Draws frames of a baked rig (rig.json, as RigSprite does) to images, for checking animations
without the game: a sheet of chosen frames, optionally with weapon art in the Sword's place.

Usage:  python tools/rig_render.py <rig dir> <out.png> <animation>[:frame,frame...] ... [--sword <png>]
          e.g. rig_render.py assets/rigs/twohand sheet.png Idle:0 Slashing:0,6,12,18
"""
import argparse
import json
import math
import os

from PIL import Image, ImageDraw

STRIDE = 10


def load(rig_dir):
    d = json.load(open(os.path.join(rig_dir, "rig.json")))
    tex = [Image.open(os.path.join(rig_dir, "parts", f["name"] + ".png")).convert("RGBA") for f in d["files"]]
    return d, tex


def draw(d, tex, anim, frame, size=900, origin=(450, 700), scale=1.0, override=None, marks=()):
    """One frame on a size x size canvas, the rig's feet at `origin`. override: object name -> image.
    marks: points (rig space) to dot, to check where things are."""
    out = Image.new("RGBA", (size, size), (70, 90, 70, 255))
    data = d["animations"][anim]["frames"][frame]
    objs = d["objects"]
    order = sorted(range(len(objs)), key=lambda i: data[i * STRIDE + 7])
    for i in order:
        o = data[i * STRIDE:(i + 1) * STRIDE]
        fi = int(o[0])
        if fi < 0 or o[6] <= 0.001:
            continue
        im = (override or {}).get(objs[i], tex[fi])
        w, h = im.size
        px, py = o[8], o[9]
        ox, oy = -w * px, -h * (1 - py)
        c, s = math.cos(o[3]), math.sin(o[3])
        sx, sy = o[4] * scale, o[5] * scale
        # local (u, v) -> screen: origin + scale * (pos + R * S * ((u, v) + offset))
        a, b = c * sx, -s * sy
        cc, dd = s * sx, c * sy
        tx = origin[0] + o[1] * scale + a * ox + b * oy
        ty = origin[1] + o[2] * scale + cc * ox + dd * oy
        det = a * dd - b * cc
        if abs(det) < 1e-9:
            continue
        # PIL wants screen -> local
        ia, ib, ic = dd / det, -b / det, (b * ty - dd * tx) / det
        id_, ie, if_ = -cc / det, a / det, (cc * tx - a * ty) / det
        layer = im.transform((size, size), Image.AFFINE, (ia, ib, ic, id_, ie, if_), Image.BICUBIC)
        if o[6] < 1:
            layer.putalpha(layer.getchannel("A").point(lambda v, k=o[6]: int(v * k)))
        out.alpha_composite(layer)
    dr = ImageDraw.Draw(out)
    for (mx, my), col in marks:
        X, Y = origin[0] + mx * scale, origin[1] + my * scale
        dr.ellipse([X - 5, Y - 5, X + 5, Y + 5], fill=col)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rig")
    ap.add_argument("out")
    ap.add_argument("frames", nargs="+")
    ap.add_argument("--sword")
    ap.add_argument("--cell", type=int, default=300)
    args = ap.parse_args()
    d, tex = load(args.rig)
    override = {"Sword": Image.open(args.sword).convert("RGBA")} if args.sword else None
    shots = []
    for spec in args.frames:
        name, _, fr = spec.partition(":")
        n = len(d["animations"][name]["frames"])
        frames = [int(x) for x in fr.split(",")] if fr else list(range(0, n, max(1, n // 6)))
        shots += [(name, f) for f in frames]
    cols = min(6, len(shots))
    C = args.cell
    sheet = Image.new("RGB", (cols * C, ((len(shots) + cols - 1) // cols) * (C + 14)), (40, 40, 40))
    dr = ImageDraw.Draw(sheet)
    for k, (name, f) in enumerate(shots):
        im = draw(d, tex, name, f, override=override).resize((C, C), Image.LANCZOS)
        x, y = (k % cols) * C, (k // cols) * (C + 14)
        sheet.paste(im, (x, y + 14))
        dr.text((x + 3, y + 1), "%s %d" % (name, f), fill=(255, 255, 160))
    sheet.save(args.out)


if __name__ == "__main__":
    main()
