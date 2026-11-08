"""Turns the CraftPix animal packs (hedgehog/snail/turtle, boar/monkey/mouse/piranha, bee/crab/bird)
into small sprite sheets for the pets (PetDB, Pet): assets/pets/<id>/idle.png, walk.png and run.png,
each a single row of frames, and meta.json with the frame size and counts.

Every frame of an animal is cropped to the same box (the union of what it draws in all its
animations), so its feet stay put from frame to frame, and scaled down so its longer side is STORE_LONG
pixels: the art is drawn at 400-800 px and shown at about 60. The animal faces right. Animals with no
walking or running animation (the bee and bird) have only idle: they hover.

Usage:  python tools/import_pets.py <folder with the pet zips>
"""
import json
import os
import re
import sys
import zipfile
from io import BytesIO

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "pets")
STORE_LONG = 160  # px: the longer side of an animal's frame, as stored

# id -> (part of the zip's name, the animal's folder in it, idle animation, walk, run)
# walk / run: the animation folder's name, or None
PETS = {
    "hedgehog": ("hedgehog-snail-turtle", "Hedgehog", "Idle", "Walking", None),
    "snail": ("hedgehog-snail-turtle", "Snail", "Idle", "Walking", None),
    "turtle": ("hedgehog-snail-turtle", "Turtle", "Idle", "Walking", None),
    "boar": ("boar-monkey-mouse-piranha", "Boar", "Idle", "Walking", "Running"),
    "monkey": ("boar-monkey-mouse-piranha", "Monkey", "Idle", "Running", None),
    "mouse": ("boar-monkey-mouse-piranha", "Mouse", "Idle", "Running", None),
    "crab": ("bee-crab-bird", "Crab", "Idle", "Walking", None),
    "bee": ("bee-crab-bird", "Bee", "Idle", None, None),
    "bird": ("bee-crab-bird", "Bird", "Idle", None, None),
}


def frames_of(zf, animal, anim):
    """The animation's frame images, in order."""
    pat = re.compile(r"^PNG/%s/PNG Sequences/%s/.*_(\d+)\.png$" % (re.escape(animal), re.escape(anim)))
    found = []
    for n in zf.namelist():
        m = pat.match(n)
        if m:
            found.append((int(m.group(1)), n))
    if not found:
        sys.exit("%s/%s: no frames" % (animal, anim))
    return [Image.open(BytesIO(zf.read(n))).convert("RGBA") for _, n in sorted(found)]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    zips = [z for z in sorted(os.listdir(src)) if z.endswith(".zip") and " (1)" not in z]
    for pid, (zip_part, animal, idle, walk, run) in PETS.items():
        matches = [z for z in zips if zip_part in z]
        if len(matches) != 1:
            sys.exit("%s: %d zips match %r" % (pid, len(matches), zip_part))
        zf = zipfile.ZipFile(os.path.join(src, matches[0]))
        anims = {"idle": frames_of(zf, animal, idle)}
        if walk:
            anims["walk"] = frames_of(zf, animal, walk)
        if run:
            anims["run"] = frames_of(zf, animal, run)

        # One box for every frame of every animation
        box = None
        for frames in anims.values():
            for f in frames:
                b = f.getbbox()
                if b:
                    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        w, h = box[2] - box[0], box[3] - box[1]
        k = STORE_LONG / max(w, h)
        fw, fh = max(1, round(w * k)), max(1, round(h * k))

        d = os.path.join(OUT, pid)
        os.makedirs(d, exist_ok=True)
        meta = {"fw": fw, "fh": fh, "idle": 0, "walk": 0, "run": 0}
        for name, frames in anims.items():
            sheet = Image.new("RGBA", (fw * len(frames), fh))
            for i, f in enumerate(frames):
                sheet.paste(f.crop(box).resize((fw, fh), Image.LANCZOS), (i * fw, 0))
            sheet.save(os.path.join(d, name + ".png"), optimize=True)
            meta[name] = len(frames)
        with open(os.path.join(d, "meta.json"), "w") as fh_:
            json.dump(meta, fh_)
        print("%-9s %dx%d  %s" % (pid, fw, fh, {k_: v for k_, v in meta.items() if k_ not in ("fw", "fh")}))
    print("wrote %d pets to %s" % (len(PETS), os.path.abspath(OUT)))


if __name__ == "__main__":
    main()
