"""Makes the game's app icon: the Death Visage helm (assets/gear/helmet) over a glowing purple rift,
like the Rift Gate's rings.

  assets/icon/icon.png             - 512 px, the project icon (window, Windows exe)
  assets/icon/icon_192.png         - Android launcher icon
  assets/icon/icon_fg_432.png      - Android adaptive icon foreground (inside the 66% safe zone)
  assets/icon/icon_bg_432.png      - Android adaptive icon background

Usage:  python tools/make_app_icon.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "assets", "icon")
HELM = os.path.join(HERE, "..", "assets", "gear", "helmet", "death_visage", "Head.png")
S = 1024  # drawn this big, then scaled down


def background(size):
    """Dark purple to black, with the rift's glow in the middle."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size - 0.5
    r = np.sqrt(xx * xx + yy * yy) / 0.7
    inner, outer = np.array([0.42, 0.12, 0.55]), np.array([0.05, 0.02, 0.08])
    t = np.clip(r, 0, 1)[..., None] ** 0.8
    rgb = inner * (1 - t) + outer * t
    return Image.fromarray((np.dstack([rgb, np.ones((size, size, 1))]) * 255).astype(np.uint8), "RGBA")


def rings(size):
    """Broken arcs round the middle, purple to pale violet, blurred into a glow."""
    layer = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(layer)
    c = size / 2
    for i, (rad, start, col, w) in enumerate([(0.44, 20, (190, 110, 255), 0.030), (0.38, 200, (215, 150, 255), 0.024),
                                               (0.32, 110, (235, 190, 255), 0.018)]):
        r = rad * size
        d.arc([c - r, c - r, c + r, c + r], start, start + 280, fill=col + (255,), width=int(w * size))
    glow = layer.filter(ImageFilter.GaussianBlur(size * 0.02))
    out = Image.alpha_composite(glow, glow)
    return Image.alpha_composite(out, layer)


def helm(size, fill):
    """The helm, `fill` of the canvas wide, centred (a little high: its visor reads as a face)."""
    im = Image.open(HELM).convert("RGBA")
    im = im.crop(im.getbbox())
    k = size * fill / max(im.size)
    im = im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)
    shadow = Image.new("RGBA", (size, size))
    out = Image.new("RGBA", (size, size))
    at = ((size - im.width) // 2, int((size - im.height) * 0.47))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sh.putalpha(im.getchannel("A").point(lambda a: int(a * 0.8)))
    shadow.alpha_composite(sh, (at[0], at[1] + int(size * 0.02)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.015))
    out.alpha_composite(shadow)
    out.alpha_composite(im, at)
    return out


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    out = im.copy()
    out.putalpha(mask)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    full = background(S)
    full.alpha_composite(rings(S))
    full.alpha_composite(helm(S, 0.62))
    rounded(full, int(S * 0.18)).resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
    full.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "icon_192.png"))
    # Adaptive: the launcher crops to its own shape and may show only the middle 66%
    bg = background(S)
    bg.alpha_composite(rings(S))
    bg.resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "icon_bg_432.png"))
    helm(S, 0.46).resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "icon_fg_432.png"))
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
