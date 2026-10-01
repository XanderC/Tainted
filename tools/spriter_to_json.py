#!/usr/bin/env python3
"""Bake a Spriter (.scml) skeletal rig into plain per-frame transforms for Godot.

Usage:
    python tools/spriter_to_json.py <Animations.scml> <out_dir> [--fps 60]

Writes  <out_dir>/rig.json          (baked animation data)
        <out_dir>/parts/<Name>.png  (the part images next to the .scml)

Every animation is sampled at --fps with Spriter's own rules (bone hierarchy,
spin-aware angle interpolation), so Godot only has to place sprites each frame
and needs no Spriter runtime. Frame data is in Godot space (y down, radians).

Each frame is a flat list, 10 numbers per object, in the order of "objects":
    file_index (-1 = hidden), x, y, rotation, scale_x, scale_y, alpha, z, pivot_x, pivot_y
"""
import argparse
import json
import math
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

FIELDS = 10


def _f(el, name, default):
    v = el.get(name)
    return float(v) if v is not None else default


def parse(scml_path):
    root = ET.parse(scml_path).getroot()
    files, file_index = [], {}
    for folder in root.findall("folder"):
        for fl in folder.findall("file"):
            file_index[(int(folder.get("id")), int(fl.get("id")))] = len(files)
            files.append({
                "id": len(files),
                "name": Path(fl.get("name")).stem,
                "src": fl.get("name"),
                "w": int(fl.get("width")),
                "h": int(fl.get("height")),
                "pivot": [_f(fl, "pivot_x", 0.0), _f(fl, "pivot_y", 1.0)],
            })
    entity = root.find("entity")
    anims = {}
    for a in entity.findall("animation"):
        length = float(a.get("length"))
        timelines = {}
        for tl in a.findall("timeline"):
            keys = []
            for k in tl.findall("key"):
                el = k.find("object")
                if el is None:
                    el = k.find("bone")
                d = {
                    "time": _f(k, "time", 0.0),
                    "spin": int(k.get("spin", "1")),
                    "x": _f(el, "x", 0.0), "y": _f(el, "y", 0.0),
                    "angle": _f(el, "angle", 0.0),
                    "sx": _f(el, "scale_x", 1.0), "sy": _f(el, "scale_y", 1.0),
                    "a": _f(el, "a", 1.0),
                }
                if el.tag == "object":
                    d["file"] = file_index[(int(el.get("folder")), int(el.get("file")))]
                    d["px"] = _f(el, "pivot_x", None) if el.get("pivot_x") is not None else None
                    d["py"] = _f(el, "pivot_y", None) if el.get("pivot_y") is not None else None
                keys.append(d)
            timelines[int(tl.get("id"))] = {"name": tl.get("name"), "keys": keys,
                                            "is_object": any("file" in k for k in keys)}
        mainline = []
        for k in a.find("mainline").findall("key"):
            mainline.append({
                "time": _f(k, "time", 0.0),
                "bones": [{"id": int(b.get("id")),
                           "parent": int(b.get("parent")) if b.get("parent") is not None else None,
                           "tl": int(b.get("timeline"))} for b in k.findall("bone_ref")],
                "objects": [{"id": int(o.get("id")),
                             "parent": int(o.get("parent")) if o.get("parent") is not None else None,
                             "tl": int(o.get("timeline")),
                             "z": int(o.get("z_index", "0"))} for o in k.findall("object_ref")],
            })
        anims[a.get("name")] = {"length": length, "timelines": timelines, "mainline": mainline}
    return files, anims


def interp(keys, t, length):
    """Spriter linear interpolation between the key in effect at t and the next one."""
    i = 0
    for n, k in enumerate(keys):
        if k["time"] <= t + 1e-6:
            i = n
    k = keys[i]
    if len(keys) == 1:
        return dict(k)
    j = (i + 1) % len(keys)
    nk = keys[j]
    ta = k["time"]
    tb = nk["time"] + (length if j <= i else 0.0)
    f = (t - ta) / (tb - ta) if tb > ta else 0.0
    out = dict(k)
    for name in ("x", "y", "sx", "sy", "a"):
        out[name] = k[name] + (nk[name] - k[name]) * f
    a1, a2 = k["angle"], nk["angle"]
    if k["spin"] == 0:
        out["angle"] = a1
    else:
        if k["spin"] > 0 and a2 < a1:
            a2 += 360.0
        elif k["spin"] < 0 and a2 > a1:
            a2 -= 360.0
        out["angle"] = a1 + (a2 - a1) * f
    return out


def compose(child, parent):
    cx, cy = child["x"] * parent["sx"], child["y"] * parent["sy"]
    ca = -child["angle"] if parent["sx"] * parent["sy"] < 0 else child["angle"]
    r = math.radians(parent["angle"])
    c, s = math.cos(r), math.sin(r)
    out = dict(child)
    out["x"] = cx * c - cy * s + parent["x"]
    out["y"] = cx * s + cy * c + parent["y"]
    out["angle"] = ca + parent["angle"]
    out["sx"] = child["sx"] * parent["sx"]
    out["sy"] = child["sy"] * parent["sy"]
    out["a"] = child["a"] * parent["a"]
    return out


def pose(anim, t):
    """World transform of every visible object at time t (ms), in Spriter space (y up)."""
    length = anim["length"]
    ml = [m for m in anim["mainline"] if m["time"] <= t + 1e-6][-1]
    bones = {b["id"]: b for b in ml["bones"]}
    cache = {}

    def bone_world(bid):
        if bid not in cache:
            b = bones[bid]
            local = interp(anim["timelines"][b["tl"]]["keys"], t, length)
            cache[bid] = compose(local, bone_world(b["parent"])) if b["parent"] is not None else local
        return cache[bid]

    out = {}
    for o in ml["objects"]:
        tl = anim["timelines"][o["tl"]]
        local = interp(tl["keys"], t, length)
        world = compose(local, bone_world(o["parent"])) if o["parent"] is not None else local
        world["z"] = o["z"]
        out[tl["name"]] = world
    return out


def bake(scml, out_dir, fps):
    files, anims = parse(scml)
    # object slots = timelines that draw an image, in timeline-id order
    first = next(iter(anims.values()))
    objects = [tl["name"] for _, tl in sorted(first["timelines"].items()) if tl["is_object"]]
    result = {"rig": Path(scml).parent.name, "fps": fps, "files": files, "objects": objects, "animations": {}}
    pivot_overrides = 0
    for name, anim in anims.items():
        if name.lower() == "base":
            continue
        n = max(1, round(anim["length"] / 1000.0 * fps))
        frames = []
        for i in range(n):
            t = i * anim["length"] / n
            p = pose(anim, t)
            row = []
            for obj in objects:
                w = p.get(obj)
                if w is None:
                    row += [-1, 0, 0, 0, 1, 1, 1, 0, 0, 1]
                    continue
                f = files[w["file"]]
                px = w["px"] if w.get("px") is not None else f["pivot"][0]
                py = w["py"] if w.get("py") is not None else f["pivot"][1]
                if [px, py] != f["pivot"]:
                    pivot_overrides += 1
                row += [w["file"], round(w["x"], 2), round(-w["y"], 2),
                        round(-math.radians(w["angle"]), 4), round(w["sx"], 4),
                        round(w["sy"], 4), round(w["a"], 3), w["z"], px, py]
            frames.append(row)
        result["animations"][name] = {"length": anim["length"] / 1000.0, "frames": frames}
    out = Path(out_dir)
    (out / "parts").mkdir(parents=True, exist_ok=True)
    for f in files:
        shutil.copyfile(Path(scml).parent / f["src"], out / "parts" / (f["name"] + ".png"))
    with open(out / "rig.json", "w") as fh:
        json.dump(result, fh, separators=(",", ":"))
    print(f"baked {len(result['animations'])} animations, {len(objects)} objects, "
          f"{sum(len(a['frames']) for a in result['animations'].values())} frames "
          f"(pivot overrides differing from file pivot: {pivot_overrides})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("scml")
    ap.add_argument("out_dir")
    ap.add_argument("--fps", type=int, default=60)
    args = ap.parse_args()
    bake(args.scml, args.out_dir, args.fps)
