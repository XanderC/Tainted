"""Makes the gem and rune icons from the CraftPix gem and rune packs:

  assets/icons/gems/<type>_<tier>.png  - socketable gems (GemDef): Chipped and Flawed are raw crystal
                                         clusters, the middle and Flawless tiers cut stones, Perfect
                                         a polished gem; Diamond is the blue art turned white
  assets/icons/runes/<rank>.png        - the 33 runes (SocketRune ladder, El = 1 ... Zod = 33), in
                                         the pack's order: 8 stone shapes, each in 6 ever brighter
                                         colours, so a rune further up the ladder looks rarer

Usage:  python tools/import_gems_runes.py <folder with the gem and rune pack zips>
"""
import io
import os
import sys
import zipfile

from PIL import Image, ImageEnhance, ImageOps

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
SIZE = 128

# type: icon numbers for tiers 1..5 (PNG/without_shadow/<n>.png), and whether to whiten them
GEMS = {
    "ruby": ([13, 19, 37, 43, 29], False),
    "topaz": ([14, 20, 38, 44, 26], False),
    "sapphire": ([16, 22, 40, 46, 25], False),
    "emerald": ([18, 24, 42, 48, 31], False),
    "amethyst": ([15, 21, 39, 45, 33], False),
    "diamond": ([16, 22, 40, 46, 32], True),
}
RUNES = 33


def fit(im):
    im = im.crop(im.getbbox())
    s = SIZE * 0.9 / max(im.size)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE))
    out.alpha_composite(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2))
    return out


def whiten(im):
    """Blue gem art turned to a pale, bright diamond (alpha kept)."""
    a = im.getchannel("A")
    g = ImageOps.grayscale(im.convert("RGB"))
    g = ImageEnhance.Brightness(g).enhance(1.35)
    rgb = Image.merge("RGB", (g, g, g.point(lambda v: min(255, v + 18))))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    zips = os.listdir(src)
    gem_zip = zipfile.ZipFile(os.path.join(src, next(z for z in zips if "gems" in z and z.endswith(".zip"))))
    rune_zip = zipfile.ZipFile(os.path.join(src, next(z for z in zips if "rune" in z and z.endswith(".zip"))))
    os.makedirs(os.path.join(ROOT, "gems"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "runes"), exist_ok=True)
    for gtype, (nums, white) in GEMS.items():
        for tier, n in enumerate(nums, 1):
            im = Image.open(io.BytesIO(gem_zip.read("PNG/without_shadow/%d.png" % n))).convert("RGBA")
            if white and tier < 5:  # the Perfect diamond (a cut crystal) already reads as one
                im = whiten(im)
            fit(im).save(os.path.join(ROOT, "gems", "%s_%d.png" % (gtype, tier)))
    for rank in range(1, RUNES + 1):
        # The six highest runes (Ber to Zod) take the pack's last, glowing blue stones
        num = rank if rank <= RUNES - 6 else 48 - (RUNES - rank)
        im = Image.open(io.BytesIO(rune_zip.read("PNG/runes+bricks/without_shadow/%d.png" % num))).convert("RGBA")
        fit(im).save(os.path.join(ROOT, "runes", "%d.png" % rank))
    print("wrote %d gems and %d runes" % (len(GEMS) * 5, RUNES))


if __name__ == "__main__":
    main()
