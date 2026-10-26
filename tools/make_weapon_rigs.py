"""Makes the weapon rigs from the sword rig (assets/rigs/zombie): the same character and timing, with
the weapon held and swung its own way. RigSprite.rig_for_weapon picks one by the weapon held:

  twohand  - two-handed swords, axes and maces: both hands on the handle, a chop
  spear    - spears: both hands along the shaft, a thrust
  dagger   - daggers: in the weapon hand, a short stab
  handxbow - one-handed crossbows: aimed forward in the weapon hand, raised and loosed

Every frame keeps the sword rig's body, head, face and legs, and poses the weapon itself:
  hold   (idle, walking, running, hurt, jumping, kicking...) - the style's guard, moving with the
         body's own bob and lean
  attack (the three slashes) - the hands travel from the style's wind-up to its strike, timed by the
         sword rig's own swing (its sword's angle): a chop follows the sword rig's angles, a thrust
         and a stab keep the weapon level and drive it forward
  as is  (throwing, dying) - the sword rig's own, the weapon its style's size
Then the weapon hand (Left Hand, behind the body) goes to the grip, the near hand (Right Hand) along
the weapon for two-handed styles, and each arm that moved turns from its shoulder towards its hand,
stretching a little where it must reach (chibi arms are short). A two-handed weapon is drawn over the
body but under the near hand, which is seen holding it. A thrust or stab has no slash trail.

A style's weapon is drawn `scale` times its art (one-handed art reused is bigger in both hands),
about its grip.

Usage:  python tools/make_weapon_rigs.py [style ...]
"""
import argparse
import json
import math
import os
import shutil

import numpy as np
from PIL import Image

HERE = os.path.dirname(__file__)
RIGS = os.path.join(HERE, "..", "assets", "rigs")
SRC = os.path.join(RIGS, "zombie")
STRIDE = 10

GRIP = (73.0, 58.8)     # where the weapon art is held (the sword rig's hand on it, art pixels)
STRETCH = (0.85, 1.45)  # how far an arm may shorten / stretch to reach its hand
TWO_HAND_Z = 6.5        # a two-handed weapon: over the Body (6), under the Head (7) and the near hand (9)
HOLD_ANIMS = ["Idle", "Idle Blinking", "Walking", "Running", "Hurt", "Kicking", "Sliding", "Jump Start",
              "Jump Loop", "Falling Down"]
ATTACK_ANIMS = ["Slashing", "Run Slashing", "Slashing in The Air"]
# The sword rig's swing, by its sword's angle: the wind-up and the strike (degrees)
WIND_ANGLE, STRIKE_ANGLE = -160.0, -3.0

# Poses are in the sword rig's idle frame (feet at 0, y down, facing right), carried along with the
# body each frame; angles in degrees (0 = level, forward; + = tip down).
#   hand_gap: the near hand's centre from the grip along the weapon (+ towards the tip), None = one hand
#   grip: where on the weapon art the weapon hand holds it (default GRIP, the sword rig's)
#   stretch: how far its arms may shorten / stretch (default STRETCH)
#   hand_over: the weapon hand is drawn over the weapon (a spear's thick shaft would hide it), its arm
#   still behind the body
#   attack "chop": angle from the sword rig's swing (+ `extra` at the strike); "thrust": level, from
#   the wind-up's angle to the strike's
STYLES = {
    "twohand": {
        "scale": 1.35, "hand_gap": -44.0, "trail": True,
        "hold": {"grip": (-2.0, -112.0), "angle": 22.0},
        "attack": {"kind": "chop", "wind": (-28.0, -196.0), "strike": (30.0, -122.0), "extra": 16.0},
    },
    # The weapon hand forward of the body (it is the far one: seen only out in front), a third of the
    # way up the shaft; the near hand well back towards the butt; both arms reach along the shaft
    "spear": {
        "scale": 1.5, "hand_gap": -100.0, "trail": False, "grip": (150.0, 58.8), "stretch": (0.5, 1.7),
        "hand_over": True,
        "hold": {"grip": (100.0, -122.0), "angle": 10.0},
        "attack": {"kind": "thrust", "wind": (62.0, -140.0), "wind_angle": 6.0,
                   "strike": (148.0, -136.0), "strike_angle": 1.0},
    },
    # Low and forward, out from the body (the weapon hand is the far one), then a jab at the chest
    "dagger": {
        "scale": 1.15, "hand_gap": None, "trail": False, "stretch": (0.5, 1.45),
        "hold": {"grip": (106.0, -108.0), "angle": 34.0},
        "attack": {"kind": "thrust", "wind": (62.0, -146.0), "wind_angle": -12.0,
                   "strike": (162.0, -156.0), "strike_angle": -4.0},
    },
    # Aimed forward at chest height, out from the body (the weapon hand is the far one); the shot
    # lifts it to the eye and pushes it out, the arm straight. Its grip is where the art's handle is
    # (tools/import_new_gear.py HAND_GRIP).
    "handxbow": {
        "scale": 1.6, "hand_gap": None, "trail": False, "grip": (52.0, 92.0), "stretch": (0.5, 1.5),
        "hold": {"grip": (110.0, -118.0), "angle": 6.0},
        "attack": {"kind": "thrust", "wind": (92.0, -122.0), "wind_angle": 16.0,
                   "strike": (150.0, -148.0), "strike_angle": -6.0},
    },
}


def rot(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s], [s, c]])


def norm(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


class Rig:
    def __init__(self, d, rig_dir):
        self.d = d
        self.objects = d["objects"]
        ims = [Image.open(os.path.join(rig_dir, "parts", f["name"] + ".png")) for f in d["files"]]
        self.size = [im.size for im in ims]
        self.bbox = [im.getbbox() for im in ims]

    def o(self, fr, name):
        k = self.objects.index(name)
        return fr[k * STRIDE:(k + 1) * STRIDE]

    def put(self, fr, name, o):
        k = self.objects.index(name)
        fr[k * STRIDE:(k + 1) * STRIDE] = [float(v) for v in o]

    def offset(self, o):
        w, h = self.size[int(o[0])]
        return np.array([-w * o[8], -h * (1 - o[9])])

    def matrix(self, o):
        """3x3: the object's art pixels -> rig space."""
        M = np.eye(3)
        M[:2, :2] = rot(o[3]) @ np.diag([o[4], o[5]])
        M[:2, 2] = np.array([o[1], o[2]]) + M[:2, :2] @ self.offset(o)
        return M

    def centre(self, fi):
        b = self.bbox[fi]
        return np.array([(b[0] + b[2]) / 2.0, (b[1] + b[3]) / 2.0])

    def place(self, o, angle, sx, sy, at_world, at_local):
        """Sets o's rotation and scale, and its position so art point at_local lands on at_world."""
        o[3], o[4], o[5] = angle, sx, sy
        p = np.array(at_world) - rot(angle) @ np.diag([sx, sy]) @ (np.array(at_local) + self.offset(o))
        o[1], o[2] = float(p[0]), float(p[1])


def build(src_dir, style):
    d = json.load(open(os.path.join(src_dir, "rig.json")))
    rig = Rig(d, src_dir)
    idle = d["animations"]["Idle"]["frames"][0]
    body0 = rig.matrix(rig.o(idle, "Body"))
    body0_rot = rig.o(idle, "Body")[3]
    # The arms' shoulder and hand points in their art, from the idle pose
    arm_pts = {}
    for arm, hand in (("Right Arm", "Right Hand"), ("Left Arm", "Left Hand")):
        oa, oh = rig.o(idle, arm), rig.o(idle, hand)
        b = rig.bbox[int(oa[0])]
        shoulder = np.array([(b[0] + b[2]) / 2.0, b[1] + 8.0])
        hand_c = (np.linalg.inv(rig.matrix(oa)) @ (rig.matrix(oh) @ np.append(rig.centre(int(oh[0])), 1)))[:2]
        arm_pts[arm] = (shoulder, hand_c)
    # The weapon hand on the weapon: hand art -> weapon art (the same in every frame of the sword rig)
    sl = d["animations"]["Slashing"]["frames"][6]
    hand_in_sword = np.linalg.inv(rig.matrix(rig.o(sl, "Sword"))) @ rig.matrix(rig.o(sl, "Left Hand"))
    sword_file = next(i for i, f in enumerate(d["files"]) if f["name"] == "Sword")
    scale, gap = style["scale"], style["hand_gap"]
    grip_art = np.array(style.get("grip", GRIP))
    stretch = style.get("stretch", STRETCH)
    # The weapon hand held at grip_art instead of GRIP: hand art -> weapon art, moved along the weapon
    shift = np.eye(3)
    shift[:2, 2] = grip_art - np.array(GRIP)
    hand_on_weapon = shift @ hand_in_sword
    two = gap is not None
    hold, attack = style["hold"], style["attack"]
    wind_a, strike_a = math.radians(WIND_ANGLE), math.radians(STRIKE_ANGLE)

    def reach(fr, arm, target):
        """Turns `arm` from its shoulder towards `target` (rig space), stretching it to reach."""
        oa = rig.o(fr, arm)
        shoulder_l, hand_l = arm_pts[arm]
        shoulder_w = (rig.matrix(oa) @ np.append(shoulder_l, 1))[:2]
        v = hand_l - shoulder_l
        want = np.array(target) - shoulder_w
        sy = min(max(np.linalg.norm(want) / np.linalg.norm(v), stretch[0]), stretch[1])
        vs = np.array([v[0], v[1] * sy])
        ang = math.atan2(want[1], want[0]) - math.atan2(vs[1], vs[0])
        rig.place(oa, ang, 1.0, sy, shoulder_w, shoulder_l)
        rig.put(fr, arm, oa)

    for name, anim in d["animations"].items():
        for fr in anim["frames"]:
            ob = rig.o(fr, "Body")
            carry = rig.matrix(ob) @ np.linalg.inv(body0)  # idle-frame space -> this frame
            lean = ob[3] - body0_rot
            os_ = rig.o(fr, "Sword")
            if not style["trail"]:
                fx = rig.o(fr, "SlashFX")
                fx[6] = 0.0
                rig.put(fr, "SlashFX", fx)
            if name in HOLD_ANIMS:
                grip_idle, angle = np.array(hold["grip"]), math.radians(hold["angle"])
            elif name in ATTACK_ANIMS:
                src_a = norm(os_[3])
                if src_a > math.radians(60.0):
                    src_a -= 2 * math.pi  # wound up past straight back: still winding up
                p = min(max((src_a - wind_a) / (strike_a - wind_a), 0.0), 1.0)
                p = p * p * (3 - 2 * p)  # ease in and out
                grip_idle = (1 - p) * np.array(attack["wind"]) + p * np.array(attack["strike"])
                if attack["kind"] == "chop":
                    angle = src_a + p * math.radians(attack["extra"]) - lean
                else:
                    angle = math.radians((1 - p) * attack["wind_angle"] + p * attack["strike_angle"])
            else:
                # As is: the weapon stays in the weapon hand, its style's size about its grip
                grip_w = (rig.matrix(os_) @ np.append(GRIP, 1))[:2]
                rig.place(os_, os_[3], os_[4] * scale, os_[5] * scale, grip_w, GRIP)
                if two:
                    os_[7] = TWO_HAND_Z
                rig.put(fr, "Sword", os_)
                continue
            grip_w = (carry @ np.append(grip_idle, 1))[:2]
            a = norm(angle + lean)
            # The weapon, shown in every frame (the sword rig hides it when not slashing)
            if os_[0] < 0:
                os_[0] = sword_file
            rig.place(os_, a, scale, scale, grip_w, grip_art)
            os_[6] = 1.0
            if two:
                os_[7] = TWO_HAND_Z
            rig.put(fr, "Sword", os_)
            # The weapon hand at the grip, as it holds the sword in the sword rig
            ol = rig.o(fr, "Left Hand")
            unit = np.eye(3)
            unit[:2, :2] = rot(a)
            unit[:2, 2] = grip_w - rot(a) @ (grip_art + rig.offset(os_))
            M = unit @ hand_on_weapon
            ol[3], ol[4], ol[5] = math.atan2(M[1, 0], M[0, 0]), 1.0, 1.0
            p_ = M[:2, 2] - rot(ol[3]) @ rig.offset(ol)
            ol[1], ol[2], ol[6] = float(p_[0]), float(p_[1]), 1.0
            if style.get("hand_over"):
                ol[7] = TWO_HAND_Z + 0.2  # over the weapon, under the Head
            rig.put(fr, "Left Hand", ol)
            reach(fr, "Left Arm", (rig.matrix(ol) @ np.append(rig.centre(int(ol[0])), 1))[:2])
            if two:
                # The near hand along the weapon, turned as the weapon hand is
                orh = rig.o(fr, "Right Hand")
                near = grip_w + rot(a) @ np.array([gap, 0.0])
                rig.place(orh, ol[3], 1.0, 1.0, near, rig.centre(int(orh[0])))
                orh[6] = 1.0
                rig.put(fr, "Right Hand", orh)
                reach(fr, "Right Arm", near)
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("styles", nargs="*", default=list(STYLES))
    args = ap.parse_args()
    for name in args.styles:
        d = build(SRC, STYLES[name])
        out = os.path.join(RIGS, name)
        os.makedirs(os.path.join(out, "parts"), exist_ok=True)
        for f in os.listdir(os.path.join(SRC, "parts")):
            if f.endswith(".png"):
                shutil.copyfile(os.path.join(SRC, "parts", f), os.path.join(out, "parts", f))
        with open(os.path.join(out, "rig.json"), "w") as f:
            json.dump(d, f, separators=(",", ":"))
        print("wrote", os.path.abspath(out))


if __name__ == "__main__":
    main()
