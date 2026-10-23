"""Makes the spell effects (SpellFx) from the CraftPix top-down magic packs on the NAS
(Y:/Tainted/assets/spells): each effect's frames, cropped to the area any of them uses, scaled down
for a phone, side by side in one strip.

  assets/fx/<id>.png   the frames in a row
  assets/fx/fx.json    per effect: frames, frame w / h (px), and where the original canvas's centre
                       is in a frame (cx, cy: the point SpellFx.play puts at the given position)

The packs' other effects (and the pixel-art packs, another style) aren't used.

Usage:  python tools/import_spells.py [Y:/Tainted/assets/spells]
"""
import io
import json
import os
import re
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "assets", "fx")

FIRE_EARTH = "craftpix-net-153715-fire-and-earth-magic-sprites-for-top-down-games.zip"
WIND_LIGHTNING = "craftpix-net-821246-top-down-wind-and-lightning-magic-effects-pack.zip"
SHIELDS = "craftpix-net-865099-magic-shield-animation-asset-pack.zip"
VECTOR = "craftpix-net-560683-magic-sprite-effects-vector-pack.zip"

# id: (zip, regex for its frames' paths (group 1: the frame number), the largest side in px)
EFFECTS = {
    "earth_fissure": (FIRE_EARTH, r"Earth Fissure/PNG/Earth Fissure_Frame_(\d+)\.png$", 256),
    "earth_spike": (FIRE_EARTH, r"Earth Spike/PNG/Earth Spike_Frame_(\d+)\.png$", 224),
    "ground_hit": (FIRE_EARTH, r"Ground Hit/PNG/Ground Hit_Frame_(\d+)\.png$", 256),
    "fire_explosion": (FIRE_EARTH, r"Fire Explosion/PNG/Fire Explosion_Frame_(\d+)\.png$", 224),
    "flame": (FIRE_EARTH, r"Flame/PNG/Flame_Frame_(\d+)\.png$", 160),
    "lightning_strike": (WIND_LIGHTNING, r"Lightning Strike/PNG/Lightning Strike_Frame_(\d+)\.png$", 224),
    "typhoon": (WIND_LIGHTNING, r"Typhoon/PNG/Typhoon_Frame_(\d+)\.png$", 256),
    "earth_shield": (SHIELDS, r"Earth Shield/PNG/Earth Shield_Frame_(\d+)\.png$", 192),
    "fire_shield": (SHIELDS, r"Fire Shield/PNG/Fire Shield_Frame_(\d+)\.png$", 192),
    "leaf_shield": (SHIELDS, r"Leaf Shield/PNG/Leaf Shield_Frame_(\d+)\.png$", 224),
    "lightning_shield": (SHIELDS, r"Lightning Shield/PNG/Lightning Shield_Frame_(\d+)\.png$", 192),
    # small hit sparks, by damage type
    "hit_physical": (VECTOR, r"PNG/8/(\d+)\.png$", 96),
    "hit_fire": (VECTOR, r"PNG/7/(\d+)\.png$", 112),
    "hit_cold": (VECTOR, r"PNG/6/(\d+)\.png$", 96),
    "hit_lightning": (VECTOR, r"PNG/4/(\d+)\.png$", 112),
    "hit_poison": (VECTOR, r"PNG/9/(\d+)\.png$", 112),
}


def frames_of(zf: zipfile.ZipFile, pattern: str) -> list:
    rx = re.compile(pattern)
    found = []
    for name in zf.namelist():
        if "__MACOSX" in name or os.path.basename(name).startswith("._"):
            continue
        m = rx.search(name.replace("\\", "/"))
        if m:
            found.append((int(m.group(1)), name))
    found.sort()
    return [Image.open(io.BytesIO(zf.read(n))).convert("RGBA") for _, n in found]


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "Y:/Tainted/assets/spells"
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    zips = {}
    for fx_id, (zname, pattern, largest) in EFFECTS.items():
        if zname not in zips:
            zips[zname] = zipfile.ZipFile(os.path.join(src, zname))
        frames = frames_of(zips[zname], pattern)
        if not frames:
            raise SystemExit("no frames for %s" % fx_id)
        w0, h0 = frames[0].size
        # The area any frame uses, so every frame keeps its place in it
        box = None
        for f in frames:
            b = f.getbbox()
            if b:
                box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        box = (max(box[0] - 2, 0), max(box[1] - 2, 0), min(box[2] + 2, w0), min(box[3] + 2, h0))
        bw, bh = box[2] - box[0], box[3] - box[1]
        s = min(1.0, largest / max(bw, bh))
        fw, fh = max(int(round(bw * s)), 1), max(int(round(bh * s)), 1)
        strip = Image.new("RGBA", (fw * len(frames), fh))
        for i, f in enumerate(frames):
            strip.paste(f.crop(box).resize((fw, fh), Image.LANCZOS), (i * fw, 0))
        strip.save(os.path.join(OUT, fx_id + ".png"), optimize=True)
        meta[fx_id] = {"frames": len(frames), "w": fw, "h": fh,
                       "cx": round((w0 / 2 - box[0]) * s, 1), "cy": round((h0 / 2 - box[1]) * s, 1)}
        print("%-17s %2d frames  %3dx%-3d  %6.1f KB" % (fx_id, len(frames), fw, fh,
              os.path.getsize(os.path.join(OUT, fx_id + ".png")) / 1024))
    with open(os.path.join(OUT, "fx.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
