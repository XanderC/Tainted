"""Composes rig parts as they sit in the zombie rig's idle pose (frame 0), for item icons: a body
with its arms, a pair of hands, a pair of legs. Rotations there are whole turns, so parts are pasted
at their place, back to front."""
import json
import os

from PIL import Image

RIG = os.path.join(os.path.dirname(__file__), "..", "assets", "rigs", "zombie", "rig.json")
STRIDE = 10


def idle_places():
    """object name -> (x, y, z) of its top-left corner in the idle pose's first frame."""
    r = json.load(open(RIG))
    data = r["animations"]["Idle"]["frames"][0]
    out = {}
    for i, name in enumerate(r["objects"]):
        o = data[i * STRIDE:(i + 1) * STRIDE]
        out[name] = (o[1], o[2], o[7])
    return out


def compose(parts):
    """parts: {object name: RGBA image}. The parts placed as in the idle pose, cropped to them."""
    places = idle_places()
    items = sorted(parts.items(), key=lambda kv: places[kv[0]][2])
    x0 = min(places[n][0] for n in parts)
    y0 = min(places[n][1] for n in parts)
    x1 = max(places[n][0] + im.width for n, im in parts.items())
    y1 = max(places[n][1] + im.height for n, im in parts.items())
    canvas = Image.new("RGBA", (int(x1 - x0) + 2, int(y1 - y0) + 2))
    for n, im in items:
        canvas.alpha_composite(im, (int(places[n][0] - x0), int(places[n][1] - y0)))
    return canvas.crop(canvas.getbbox())
