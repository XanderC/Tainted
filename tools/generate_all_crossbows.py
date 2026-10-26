"""Generates complete, game-ready assets for all 7 cartoon crossbows:
  - Sword.png (400x128): in-hand side profile view (grip at (73, 59))
  - Bow.png (200x320): in-hand vertical view for the archer rig
  - icon.png (192x288): 2x3 bag cells inventory icon with rich cartoon cel-shading
"""
import math
import os
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw

SS = 4
OUT_COL = (0.11, 0.10, 0.10)  # Matches game's warm dark outline

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

def bezier(p0, p1, p2, n=30):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / n for i in range(n + 1))]

def cubic_bezier(p0, p1, p2, p3, n=40):
    return [((1 - t)**3 * p0[0] + 3*(1 - t)**2 * t * p1[0] + 3*(1 - t) * t**2 * p2[0] + t**3 * p3[0],
             (1 - t)**3 * p0[1] + 3*(1 - t)**2 * t * p1[1] + 3*(1 - t) * t**2 * p2[1] + t**3 * p3[1])
            for t in (i / n for i in range(n + 1))]

class Layer:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)

    def blend(self, m, color):
        col = np.broadcast_to(np.array(color, np.float32), self.rgb.shape) if np.ndim(color) == 1 else color
        m3 = m[..., None]
        oa = m + self.a * (1 - m)
        self.rgb = np.where(oa[..., None] > 1e-6,
                            (col * m3 + self.rgb * self.a[..., None] * (1 - m3)) / np.maximum(oa[..., None], 1e-6), 0)
        self.a = oa

    def paint(self, mask, color, outline=0, outline_col=OUT_COL):
        if outline > 0:
            out_mask = np.clip(dilate(mask, outline) - mask, 0, 1)
            self.blend(out_mask, outline_col)
        self.blend(mask, color)

    def detail(self, mask, color, strength=1.0):
        self.blend(mask * self.a * strength, color)

    def glow(self, mask, color, radius=5, strength=0.7):
        b = blur(mask, radius)
        col = np.array(color, np.float32)[None, None, :]
        self.rgb = np.clip(self.rgb + b[..., None] * col * strength, 0, 1)
        self.a = np.clip(self.a + b * strength * 0.8, 0, 1)

    def to_image(self):
        arr = np.dstack([np.clip(self.rgb, 0, 1), np.clip(self.a, 0, 1)])
        return Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")

def shade(mask, base, rim=7.0, dark=0.32, light=0.22, light_dir=(-1, -1)):
    m = (mask > 0.4).astype(np.uint8)
    if not np.any(m):
        return np.broadcast_to(np.array(base, np.float32), (mask.shape[0], mask.shape[1], 3))
    dist = cv2.distanceTransform(m, cv2.DIST_L2, 5)
    edge = np.clip(dist / rim, 0, 1)
    k = 1 - dark * (1 - edge) ** 1.3
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    lx, ly = light_dir
    norm = math.hypot(lx, ly)
    lx, ly = lx / norm, ly / norm
    grad = (xx / w - 0.5) * (-lx * 0.4) + (yy / h - 0.5) * (-ly * 0.4)
    col = np.array(base, np.float32)[None, None, :] * k[..., None] * (1 + light * grad)[..., None]
    hl = np.clip(mask - shift(mask, int(-lx * 3), int(-ly * 3)), 0, 1)
    hl = blur(hl, 1.2)
    col = col + hl[..., None] * 0.25
    return np.clip(col, 0, 1)

def fit_bag(im, w=192, h=288, pad_frac=0.90):
    bbox = im.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
    if not bbox:
        return Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cropped = im.crop(bbox)
    s = min((w * pad_frac) / cropped.width, (h * pad_frac) / cropped.height)
    new_w, new_h = max(1, int(cropped.width * s)), max(1, int(cropped.height * s))
    resized = cropped.resize((new_w, new_h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(resized, ((w - new_w) // 2, (h - new_h) // 2))
    return out


# ==============================================================================
# 1. HUNTING CROSSBOW (Tier 1)
# ==============================================================================
def draw_hunting_crossbow():
    # --- SWORD.PNG (400x128) ---
    w, h = 400, 128
    L = Layer(w, h)

    # String behind
    c = Canvas(w, h)
    c.line([(305, 14), (155, 58)], 2.5)
    c.line([(155, 60), (305, 104)], 2.5)
    L.paint(c.array(), (0.85, 0.82, 0.72), outline=1)

    # Stock
    pts = [(22, 50), (45, 48), (70, 52), (140, 52), (325, 52), (325, 66), (290, 68), (140, 66), (85, 68), (76, 85), (60, 85), (66, 68), (35, 75), (22, 70)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    L.paint(stock_m, shade(stock_m, (0.54, 0.36, 0.20), rim=7), outline=3)

    # Grain
    c = Canvas(w, h)
    c.line([(30, 56), (65, 56)], 1.5)
    c.line([(85, 58), (280, 57)], 1.8)
    c.line([(100, 62), (260, 62)], 1.5)
    L.detail(c.array() * stock_m, (0.35, 0.22, 0.12), 0.75)

    # Grip leather wrap
    c = Canvas(w, h); c.poly([(58, 66), (82, 66), (78, 86), (56, 86)]); grip_m = c.array() * stock_m
    L.paint(grip_m, shade(grip_m, (0.38, 0.24, 0.14), rim=4), outline=2)
    c = Canvas(w, h)
    for y in range(68, 84, 4): c.line([(58, y), (80, y + 2)], 1.5)
    L.detail(c.array() * grip_m, (0.22, 0.13, 0.08), 0.85)

    # Butt cap & trigger
    c = Canvas(w, h); c.poly([(20, 48), (28, 49), (28, 71), (20, 71)])
    L.paint(c.array(), shade(c.array(), (0.42, 0.44, 0.46), rim=4), outline=2)
    c = Canvas(w, h); c.line([(76, 68), (88, 82), (105, 82), (105, 66)], 2.5); L.paint(c.array(), (0.30, 0.32, 0.35), outline=1)
    c = Canvas(w, h); c.line([(88, 67), (85, 76)], 2.2); L.paint(c.array(), (0.45, 0.48, 0.50), outline=1)

    # Bolt
    c = Canvas(w, h); c.rect(155, 50, 318, 54); c.poly([(316, 48), (330, 52), (316, 56)]); bolt_m = c.array()
    L.paint(bolt_m, shade(bolt_m, (0.65, 0.50, 0.35), rim=3), outline=2)
    c = Canvas(w, h); c.poly([(316, 48), (330, 52), (316, 56)]); L.paint(c.array(), shade(c.array(), (0.75, 0.78, 0.82), rim=3), outline=1)
    c = Canvas(w, h); c.poly([(155, 47), (170, 51), (155, 51)]); c.poly([(155, 53), (170, 53), (155, 57)])
    L.paint(c.array(), (0.85, 0.82, 0.75), outline=1)

    # Lock
    c = Canvas(w, h); c.rect(142, 49, 162, 57, r=2); L.paint(c.array(), shade(c.array(), (0.50, 0.52, 0.55), rim=3), outline=2)

    # Prod
    top_limb = cubic_bezier((292, 58), (318, 48), (325, 26), (305, 14), 25)
    bot_limb = cubic_bezier((292, 60), (318, 70), (325, 92), (305, 104), 25)
    c = Canvas(w, h); c.line(top_limb, 7.5); c.line(bot_limb, 7.5); prod_m = c.array()
    L.paint(prod_m, shade(prod_m, (0.52, 0.55, 0.58), rim=5), outline=3)
    c = Canvas(w, h); c.line(top_limb, 2.5); c.line(bot_limb, 2.5); L.detail(c.array() * prod_m, (0.85, 0.88, 0.92), 0.8)
    c = Canvas(w, h); c.ellipse((299, 10, 311, 20)); c.ellipse((299, 98, 311, 108)); L.paint(c.array(), shade(c.array(), (0.42, 0.44, 0.47), rim=3), outline=2)

    # Bracket & stirrup
    c = Canvas(w, h); c.rect(286, 48, 304, 70, r=3); brk_m = c.array(); L.paint(brk_m, shade(brk_m, (0.38, 0.40, 0.43), rim=4), outline=2)
    c = Canvas(w, h); c.line([(324, 53), (350, 48), (362, 59), (350, 70), (324, 65)], 4.5); st_m = c.array()
    L.paint(st_m, shade(st_m, (0.45, 0.48, 0.52), rim=3), outline=2)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    # Bow limbs curve vertically, stock extends left
    c = Canvas(bw, bh)
    c.line([(70, 20), (125, 160)], 2.5); c.line([(125, 160), (70, 300)], 2.5)
    BL.paint(c.array(), (0.85, 0.82, 0.72), outline=1)
    # Stock horizontal
    c = Canvas(bw, bh); c.rect(25, 150, 160, 170, r=4); st_m = c.array()
    BL.paint(st_m, shade(st_m, (0.54, 0.36, 0.20), rim=5), outline=3)
    # Vertical prod limbs
    t_limb = cubic_bezier((65, 160), (45, 110), (50, 50), (72, 20), 25)
    b_limb = cubic_bezier((65, 160), (45, 210), (50, 270), (72, 300), 25)
    c = Canvas(bw, bh); c.line(t_limb, 9.0); c.line(b_limb, 9.0); p_m = c.array()
    BL.paint(p_m, shade(p_m, (0.52, 0.55, 0.58), rim=5), outline=3)
    # Stirrup at left tip of stock
    c = Canvas(bw, bh); c.line([(25, 154), (10, 160), (25, 166)], 4.5)
    BL.paint(c.array(), shade(c.array(), (0.45, 0.48, 0.52), rim=3), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


# ==============================================================================
# 2. LIGHT CROSSBOW (Tier 2)
# ==============================================================================
def draw_light_crossbow():
    w, h = 400, 128
    L = Layer(w, h)

    # String
    c = Canvas(w, h); c.line([(310, 12), (150, 58)], 2.5); c.line([(150, 60), (310, 106)], 2.5)
    L.paint(c.array(), (0.92, 0.90, 0.85), outline=1)

    # Cherry/walnut stock with sleek tapered profile
    pts = [(20, 52), (48, 49), (80, 51), (150, 51), (328, 51), (328, 67), (290, 67), (140, 65), (90, 67), (78, 87), (60, 87), (68, 67), (38, 76), (20, 68)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    L.paint(stock_m, shade(stock_m, (0.48, 0.25, 0.14), rim=7), outline=3)

    # Polished wood highlight
    c = Canvas(w, h); c.line([(90, 55), (310, 55)], 2.2); L.detail(c.array() * stock_m, (0.75, 0.45, 0.28), 0.7)

    # Brass corner plates & trim
    c = Canvas(w, h)
    c.poly([(20, 52), (32, 51), (32, 70), (20, 68)]) # butt brass plate
    c.poly([(140, 51), (165, 51), (165, 65), (140, 65)]) # lock brass frame
    brass_m = c.array()
    brass_col = (0.84, 0.68, 0.24)
    L.paint(brass_m, shade(brass_m, brass_col, rim=4), outline=2)
    # Brass rivets
    c = Canvas(w, h)
    for x in (26, 146, 158): c.ellipse((x - 2, 56, x + 2, 60))
    L.detail(c.array(), (0.98, 0.95, 0.60), 0.95)

    # Grip wrap
    c = Canvas(w, h); c.poly([(58, 66), (82, 66), (79, 87), (56, 87)]); grip_m = c.array() * stock_m
    L.paint(grip_m, shade(grip_m, (0.28, 0.35, 0.22), rim=4), outline=2) # dark hunter green
    c = Canvas(w, h); c.ellipse((68, 72, 72, 76)); c.ellipse((66, 79, 70, 83))
    L.paint(c.array(), shade(c.array(), brass_col, rim=2), outline=1)

    # Trigger & guard
    c = Canvas(w, h); c.line([(78, 67), (90, 84), (108, 84), (108, 65)], 2.5); L.paint(c.array(), brass_col, outline=1)
    c = Canvas(w, h); c.line([(92, 67), (88, 78)], 2.2); L.paint(c.array(), (0.60, 0.62, 0.66), outline=1)

    # Bolt with green fletching
    c = Canvas(w, h); c.rect(152, 49, 322, 53); bolt_m = c.array()
    L.paint(bolt_m, shade(bolt_m, (0.75, 0.65, 0.50), rim=2), outline=2)
    c = Canvas(w, h); c.poly([(320, 47), (336, 51), (320, 55)]); L.paint(c.array(), shade(c.array(), (0.82, 0.85, 0.90), rim=3), outline=1)
    c = Canvas(w, h); c.poly([(150, 46), (168, 50), (150, 50)]); c.poly([(150, 52), (168, 52), (150, 56)])
    L.paint(c.array(), shade(c.array(), (0.25, 0.58, 0.30), rim=2), outline=1)

    # Prod: tempered steel with brass tip caps
    top_limb = cubic_bezier((292, 58), (322, 46), (330, 24), (310, 12), 25)
    bot_limb = cubic_bezier((292, 60), (322, 72), (330, 94), (310, 106), 25)
    c = Canvas(w, h); c.line(top_limb, 8.0); c.line(bot_limb, 8.0); prod_m = c.array()
    steel_col = (0.64, 0.68, 0.72)
    L.paint(prod_m, shade(prod_m, steel_col, rim=5), outline=3)
    c = Canvas(w, h); c.line(top_limb, 2.5); c.line(bot_limb, 2.5); L.detail(c.array() * prod_m, (0.94, 0.96, 0.98), 0.85)

    # Brass tip caps
    c = Canvas(w, h); c.ellipse((304, 8, 318, 18)); c.ellipse((304, 100, 318, 110)); L.paint(c.array(), shade(c.array(), brass_col, rim=3), outline=2)

    # Brass stirrup with flared diamond shape
    c = Canvas(w, h); c.line([(326, 52), (356, 44), (370, 59), (356, 74), (326, 66)], 4.8); st_m = c.array()
    L.paint(st_m, shade(st_m, brass_col, rim=3), outline=2)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    c = Canvas(bw, bh); c.line([(72, 18), (128, 160)], 2.5); c.line([(128, 160), (72, 302)], 2.5); BL.paint(c.array(), (0.92, 0.90, 0.85), outline=1)
    c = Canvas(bw, bh); c.rect(25, 149, 162, 171, r=4); BL.paint(c.array(), shade(c.array(), (0.48, 0.25, 0.14), rim=5), outline=3)
    t_limb = cubic_bezier((65, 160), (42, 110), (48, 48), (74, 18), 25)
    b_limb = cubic_bezier((65, 160), (42, 210), (48, 272), (74, 302), 25)
    c = Canvas(bw, bh); c.line(t_limb, 9.5); c.line(b_limb, 9.5); BL.paint(c.array(), shade(c.array(), steel_col, rim=5), outline=3)
    c = Canvas(bw, bh); c.ellipse((68, 12, 80, 24)); c.ellipse((68, 296, 80, 308)); BL.paint(c.array(), shade(c.array(), brass_col, rim=3), outline=2)
    c = Canvas(bw, bh); c.line([(25, 153), (8, 160), (25, 167)], 5.0); BL.paint(c.array(), shade(c.array(), brass_col, rim=3), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


# ==============================================================================
# 3. ARBALEST (Tier 3)
# ==============================================================================
def draw_arbalest():
    w, h = 400, 128
    L = Layer(w, h)

    # Cable
    c = Canvas(w, h); c.line([(318, 10), (145, 57)], 3.0); c.line([(145, 61), (318, 108)], 3.0)
    L.paint(c.array(), (0.70, 0.72, 0.76), outline=1)

    # Heavy stock with iron reinforcement plates
    pts = [(18, 48), (50, 46), (85, 49), (160, 49), (330, 49), (330, 69), (280, 69), (145, 67), (95, 69), (82, 89), (62, 89), (70, 69), (36, 78), (18, 70)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    L.paint(stock_m, shade(stock_m, (0.32, 0.22, 0.15), rim=8), outline=3)

    # Heavy riveted iron plates across the stock
    c = Canvas(w, h)
    c.poly([(18, 48), (34, 47), (34, 73), (18, 70)]) # butt plate
    c.rect(130, 48, 175, 68)                         # receiver plate
    c.rect(275, 48, 305, 70)                         # front nose plate
    plates_m = c.array()
    iron_col = (0.55, 0.58, 0.62)
    L.paint(plates_m, shade(plates_m, iron_col, rim=5), outline=2)
    # Plate rivets
    c = Canvas(w, h)
    for x in (25, 138, 150, 166, 282, 296):
        c.ellipse((x - 2.5, 51, x + 2.5, 56))
        c.ellipse((x - 2.5, 61, x + 2.5, 66))
    L.detail(c.array(), (0.90, 0.92, 0.95), 0.9)

    # Cranequin winder track on top receiver
    c = Canvas(w, h); c.rect(175, 46, 220, 50); L.paint(c.array(), shade(c.array(), (0.75, 0.65, 0.35), rim=2), outline=1)

    # Heavy Quarrel (bolt) with red fletching
    c = Canvas(w, h); c.rect(148, 47, 322, 52); bolt_m = c.array()
    L.paint(bolt_m, shade(bolt_m, (0.60, 0.60, 0.65), rim=2), outline=2)
    # Armor piercing chisel head
    c = Canvas(w, h); c.poly([(320, 44), (340, 49), (320, 54)]); L.paint(c.array(), shade(c.array(), (0.85, 0.88, 0.92), rim=3), outline=1)
    # Red fletchings
    c = Canvas(w, h); c.poly([(146, 43), (166, 48), (146, 48)]); c.poly([(146, 51), (166, 51), (146, 56)])
    L.paint(c.array(), shade(c.array(), (0.78, 0.20, 0.18), rim=2), outline=1)

    # Wide heavy steel recurve limbs
    top_limb = cubic_bezier((290, 57), (330, 44), (342, 20), (318, 10), 25)
    bot_limb = cubic_bezier((290, 61), (330, 74), (342, 98), (318, 108), 25)
    c = Canvas(w, h); c.line(top_limb, 10.0); c.line(bot_limb, 10.0); prod_m = c.array()
    steel_col = (0.68, 0.72, 0.76)
    L.paint(prod_m, shade(prod_m, steel_col, rim=6), outline=3)
    c = Canvas(w, h); c.line(top_limb, 3.5); c.line(bot_limb, 3.5); L.detail(c.array() * prod_m, (0.95, 0.97, 1.0), 0.9)

    # Heavy notched limb hooks
    c = Canvas(w, h); c.poly([(314, 6), (324, 6), (320, 16), (310, 14)]); c.poly([(314, 112), (324, 112), (320, 102), (310, 104)])
    L.paint(c.array(), shade(c.array(), iron_col, rim=3), outline=2)

    # Solid D-shaped steel stirrup
    c = Canvas(w, h); c.line([(328, 51), (360, 44), (376, 59), (360, 74), (328, 67)], 5.5); L.paint(c.array(), shade(c.array(), iron_col, rim=4), outline=2)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    c = Canvas(bw, bh); c.line([(76, 14), (130, 160)], 3.0); c.line([(130, 160), (76, 306)], 3.0); BL.paint(c.array(), (0.70, 0.72, 0.76), outline=1)
    c = Canvas(bw, bh); c.rect(22, 148, 165, 172, r=4); BL.paint(c.array(), shade(c.array(), (0.32, 0.22, 0.15), rim=6), outline=3)
    t_limb = cubic_bezier((68, 160), (40, 108), (44, 44), (78, 14), 25)
    b_limb = cubic_bezier((68, 160), (40, 212), (44, 276), (78, 306), 25)
    c = Canvas(bw, bh); c.line(t_limb, 11.5); c.line(b_limb, 11.5); BL.paint(c.array(), shade(c.array(), steel_col, rim=6), outline=3)
    c = Canvas(bw, bh); c.line([(24, 152), (6, 160), (24, 168)], 6.0); BL.paint(c.array(), shade(c.array(), iron_col, rim=4), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


# ==============================================================================
# 4. REPEATING CROSSBOW (Tier 4)
# ==============================================================================
def draw_repeating_crossbow():
    w, h = 400, 128
    L = Layer(w, h)

    # Dual strings for stacked split limbs
    c = Canvas(w, h)
    c.line([(305, 14), (160, 58)], 2.2); c.line([(160, 60), (305, 104)], 2.2)
    c.line([(318, 22), (160, 58)], 2.2); c.line([(160, 60), (318, 96)], 2.2)
    L.paint(c.array(), (0.88, 0.85, 0.75), outline=1)

    # Mahogany stock
    pts = [(20, 52), (48, 50), (80, 52), (160, 52), (325, 52), (325, 68), (285, 68), (150, 67), (90, 68), (76, 88), (58, 88), (66, 68), (35, 76), (20, 68)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    L.paint(stock_m, shade(stock_m, (0.46, 0.18, 0.14), rim=7), outline=3)

    # Top-mounted bronze bolt magazine/hopper
    c = Canvas(w, h); c.rect(130, 32, 225, 52, r=3); mag_m = c.array()
    bronze_col = (0.82, 0.58, 0.22)
    L.paint(mag_m, shade(mag_m, bronze_col, rim=5), outline=2)
    # Magazine bolts visible in slot
    c = Canvas(w, h); c.rect(142, 38, 212, 46, r=2)
    L.paint(c.array(), (0.20, 0.15, 0.10), outline=1)
    c = Canvas(w, h)
    for x in range(148, 205, 10): c.line([(x, 40), (x, 44)], 2.0)
    L.paint(c.array(), (0.85, 0.75, 0.40), outline=0)

    # Articulated bronze pump / cocking lever under stock
    c = Canvas(w, h); c.line([(70, 78), (115, 92), (180, 75)], 4.0); lever_m = c.array()
    L.paint(lever_m, shade(lever_m, bronze_col, rim=3), outline=2)
    # Bronze gears / circular pivot housings
    c = Canvas(w, h); c.ellipse((64, 72, 76, 84)); c.ellipse((108, 86, 122, 100))
    L.paint(c.array(), shade(c.array(), bronze_col, rim=3), outline=2)

    # Stacked double-decker bow limbs (Dual limbs!)
    top1 = cubic_bezier((290, 56), (318, 44), (325, 24), (305, 14), 25)
    bot1 = cubic_bezier((290, 62), (318, 74), (325, 94), (305, 104), 25)
    top2 = cubic_bezier((295, 57), (328, 48), (336, 32), (318, 22), 25)
    bot2 = cubic_bezier((295, 61), (328, 70), (336, 86), (318, 96), 25)
    c = Canvas(w, h)
    c.line(top1, 6.5); c.line(bot1, 6.5); c.line(top2, 6.5); c.line(bot2, 6.5)
    prod_m = c.array()
    blue_steel = (0.50, 0.58, 0.68)
    L.paint(prod_m, shade(prod_m, blue_steel, rim=4), outline=3)
    c = Canvas(w, h); c.line(top1, 2.0); c.line(bot1, 2.0); c.line(top2, 2.0); c.line(bot2, 2.0)
    L.detail(c.array() * prod_m, (0.88, 0.92, 0.98), 0.85)

    # Bronze limb tips
    c = Canvas(w, h)
    c.ellipse((300, 10, 310, 20)); c.ellipse((300, 98, 310, 108))
    c.ellipse((313, 18, 323, 28)); c.ellipse((313, 90, 323, 100))
    L.paint(c.array(), shade(c.array(), bronze_col, rim=3), outline=2)

    # Front bracket & stirrup
    c = Canvas(w, h); c.rect(284, 48, 305, 70, r=3); L.paint(c.array(), shade(c.array(), bronze_col, rim=4), outline=2)
    c = Canvas(w, h); c.line([(324, 53), (350, 48), (362, 59), (350, 70), (324, 65)], 4.5)
    L.paint(c.array(), shade(c.array(), bronze_col, rim=3), outline=2)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    c = Canvas(bw, bh)
    c.line([(70, 20), (125, 160)], 2.5); c.line([(125, 160), (70, 300)], 2.5)
    c.line([(85, 32), (125, 160)], 2.5); c.line([(125, 160), (85, 288)], 2.5)
    BL.paint(c.array(), (0.88, 0.85, 0.75), outline=1)
    c = Canvas(bw, bh); c.rect(25, 149, 160, 171, r=4); BL.paint(c.array(), shade(c.array(), (0.46, 0.18, 0.14), rim=5), outline=3)
    c = Canvas(bw, bh); c.rect(75, 134, 140, 152, r=3); BL.paint(c.array(), shade(c.array(), bronze_col, rim=3), outline=2)
    t1 = cubic_bezier((65, 160), (44, 110), (48, 50), (70, 20), 25)
    b1 = cubic_bezier((65, 160), (44, 210), (48, 270), (70, 300), 25)
    t2 = cubic_bezier((72, 160), (56, 115), (60, 62), (85, 32), 25)
    b2 = cubic_bezier((72, 160), (56, 205), (60, 258), (85, 288), 25)
    c = Canvas(bw, bh); c.line(t1, 7.5); c.line(b1, 7.5); c.line(t2, 7.5); c.line(b2, 7.5)
    BL.paint(c.array(), shade(c.array(), blue_steel, rim=4), outline=3)
    c = Canvas(bw, bh); c.line([(25, 153), (10, 160), (25, 167)], 4.5); BL.paint(c.array(), shade(c.array(), bronze_col, rim=3), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


# ==============================================================================
# 5. SIEGE CROSSBOW (Tier 5)
# ==============================================================================
def draw_siege_crossbow():
    w, h = 400, 128
    L = Layer(w, h)

    # Heavy wire cable
    c = Canvas(w, h); c.line([(315, 8), (145, 57)], 3.2); c.line([(145, 61), (315, 110)], 3.2)
    L.paint(c.array(), (0.60, 0.60, 0.65), outline=1)

    # Blackened gothic stock
    pts = [(16, 46), (48, 44), (85, 48), (160, 48), (328, 48), (328, 70), (280, 70), (145, 68), (95, 70), (84, 92), (60, 92), (68, 70), (35, 79), (16, 72)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    black_iron = (0.25, 0.26, 0.28)
    L.paint(stock_m, shade(stock_m, black_iron, rim=7), outline=3)

    # Gunmetal bevel edge
    c = Canvas(w, h); c.line([(50, 48), (320, 48)], 2.5); L.detail(c.array() * stock_m, (0.50, 0.52, 0.56), 0.85)

    # Spiked butt & winch gears
    c = Canvas(w, h)
    c.poly([(16, 46), (28, 45), (28, 73), (16, 72)])
    c.poly([(16, 56), (4, 59), (16, 62)]) # rear skull-crusher spike!
    L.paint(c.array(), shade(c.array(), (0.38, 0.40, 0.44), rim=3), outline=2)
    c = Canvas(w, h); c.ellipse((22, 52, 34, 66)); L.paint(c.array(), shade(c.array(), (0.45, 0.48, 0.52), rim=2), outline=1)

    # Harpoon bolt with serrated barbed head
    c = Canvas(w, h); c.rect(145, 46, 315, 52); bolt_m = c.array()
    L.paint(bolt_m, shade(bolt_m, (0.35, 0.36, 0.38), rim=2), outline=2)
    # Wicked serrated head
    c = Canvas(w, h)
    c.poly([(312, 42), (342, 49), (312, 56), (322, 49)]) # barbed harpoon
    L.paint(c.array(), shade(c.array(), (0.75, 0.78, 0.82), rim=3), outline=2)
    # Black raven fletching
    c = Canvas(w, h); c.poly([(143, 40), (168, 47), (143, 47)]); c.poly([(143, 51), (168, 51), (143, 58)])
    L.paint(c.array(), (0.15, 0.15, 0.18), outline=1)

    # Massive gothic steel limbs with forward-cleaving bayonet horn spikes!
    top_limb = cubic_bezier((285, 56), (330, 42), (344, 18), (315, 8), 25)
    bot_limb = cubic_bezier((285, 62), (330, 76), (344, 100), (315, 110), 25)
    c = Canvas(w, h); c.line(top_limb, 11.0); c.line(bot_limb, 11.0); prod_m = c.array()
    steel_col = (0.42, 0.45, 0.50)
    L.paint(prod_m, shade(prod_m, steel_col, rim=6), outline=3)
    c = Canvas(w, h); c.line(top_limb, 3.5); c.line(bot_limb, 3.5); L.detail(c.array() * prod_m, (0.78, 0.82, 0.88), 0.9)

    # Forward-jutting limb spikes!
    c = Canvas(w, h)
    c.poly([(336, 26), (362, 16), (342, 38)]) # top spike
    c.poly([(336, 92), (362, 102), (342, 80)]) # bot spike
    spikes_m = c.array()
    L.paint(spikes_m, shade(spikes_m, (0.70, 0.74, 0.78), rim=4), outline=2)

    # Barbed ramming stirrup
    c = Canvas(w, h)
    c.line([(324, 50), (355, 42), (378, 59), (355, 76), (324, 68)], 6.0)
    c.poly([(374, 55), (392, 59), (374, 63)]) # front stabbing bayonet tip!
    st_m = c.array()
    L.paint(st_m, shade(st_m, steel_col, rim=4), outline=2)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    c = Canvas(bw, bh); c.line([(76, 12), (130, 160)], 3.2); c.line([(130, 160), (76, 308)], 3.2); BL.paint(c.array(), (0.60, 0.60, 0.65), outline=1)
    c = Canvas(bw, bh); c.rect(20, 147, 165, 173, r=4); BL.paint(c.array(), shade(c.array(), black_iron, rim=6), outline=3)
    t_limb = cubic_bezier((68, 160), (38, 106), (42, 42), (76, 12), 25)
    b_limb = cubic_bezier((68, 160), (38, 214), (42, 278), (76, 308), 25)
    c = Canvas(bw, bh); c.line(t_limb, 12.0); c.line(b_limb, 12.0); BL.paint(c.array(), shade(c.array(), steel_col, rim=6), outline=3)
    c = Canvas(bw, bh)
    c.poly([(42, 48), (18, 36), (54, 38)]) # top horn
    c.poly([(42, 272), (18, 284), (54, 282)]) # bot horn
    BL.paint(c.array(), shade(c.array(), (0.70, 0.74, 0.78), rim=4), outline=2)
    c = Canvas(bw, bh); c.line([(22, 151), (2, 160), (22, 169)], 6.0); BL.paint(c.array(), shade(c.array(), steel_col, rim=4), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


# ==============================================================================
# 6. RUNIC ARBALEST (Tier 6)
# ==============================================================================
def draw_runic_arbalest():
    w, h = 400, 128
    L = Layer(w, h)

    # Glowing ethereal cyan energy cord
    c = Canvas(w, h); c.line([(316, 10), (148, 58)], 2.8); c.line([(148, 60), (316, 108)], 2.8); cord_m = c.array()
    L.paint(cord_m, (0.50, 0.95, 1.0), outline=1, outline_col=(0.08, 0.35, 0.45))
    L.glow(cord_m, (0.10, 0.85, 1.0), radius=4, strength=0.8)

    # Midnight-indigo polished heartwood stock
    pts = [(20, 50), (48, 48), (82, 50), (155, 50), (328, 50), (328, 68), (285, 68), (145, 66), (92, 68), (80, 88), (60, 88), (68, 68), (36, 76), (20, 68)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    night_wood = (0.18, 0.20, 0.28)
    L.paint(stock_m, shade(stock_m, night_wood, rim=7), outline=3)

    # Glowing cyan runes engraved along the stock
    c = Canvas(w, h)
    for x in (180, 205, 230, 255):
        c.line([(x, 54), (x + 8, 62)], 2.0); c.line([(x + 8, 54), (x, 62)], 2.0)
    c.line([(95, 58), (140, 58)], 2.0)
    runes_m = c.array() * stock_m
    L.paint(runes_m, (0.40, 0.95, 1.0), outline=0)
    L.glow(runes_m, (0.15, 0.85, 1.0), radius=5, strength=0.9)

    # Silver filigree plates
    c = Canvas(w, h)
    c.poly([(20, 50), (32, 49), (32, 70), (20, 68)])
    c.rect(138, 49, 165, 66, r=2)
    c.rect(280, 49, 305, 69, r=3)
    silver_m = c.array()
    silver_col = (0.78, 0.84, 0.92)
    L.paint(silver_m, shade(silver_m, silver_col, rim=4), outline=2)

    # Embedded glowing cyan mana crystal at receiver (150, 58)
    c = Canvas(w, h); c.poly([(146, 58), (152, 52), (158, 58), (152, 64)]); gem_m = c.array()
    L.paint(gem_m, (0.60, 1.0, 1.0), outline=1, outline_col=(0.08, 0.35, 0.45))
    L.glow(gem_m, (0.20, 0.90, 1.0), radius=6, strength=1.0)

    # Crystalline mithril bolt with luminous trail
    c = Canvas(w, h); c.rect(150, 48, 324, 52); bolt_m = c.array()
    L.paint(bolt_m, (0.80, 0.92, 1.0), outline=2, outline_col=(0.10, 0.30, 0.40))
    # Glowing crystal spearhead
    c = Canvas(w, h); c.poly([(320, 45), (338, 50), (320, 55)]); head_m = c.array()
    L.paint(head_m, (0.60, 1.0, 1.0), outline=1, outline_col=(0.10, 0.40, 0.50))
    L.glow(head_m, (0.30, 0.90, 1.0), radius=4, strength=0.8)

    # Sweeping mithril limbs with glowing edge line
    top_limb = cubic_bezier((288, 57), (325, 44), (338, 20), (316, 10), 25)
    bot_limb = cubic_bezier((288, 61), (325, 74), (338, 98), (316, 108), 25)
    c = Canvas(w, h); c.line(top_limb, 9.5); c.line(bot_limb, 9.5); prod_m = c.array()
    L.paint(prod_m, shade(prod_m, silver_col, rim=5), outline=3)
    # Glowing cyan rune channel in the limbs
    c = Canvas(w, h); c.line(top_limb, 2.8); c.line(bot_limb, 2.8); rune_line = c.array() * prod_m
    L.paint(rune_line, (0.40, 0.95, 1.0), outline=0)
    L.glow(rune_line, (0.15, 0.85, 1.0), radius=4, strength=0.7)

    # Mithril stirrup holding a glowing crystal
    c = Canvas(w, h); c.line([(326, 52), (356, 44), (372, 59), (356, 74), (326, 66)], 5.0); st_m = c.array()
    L.paint(st_m, shade(st_m, silver_col, rim=4), outline=2)
    c = Canvas(w, h); c.poly([(352, 59), (358, 54), (364, 59), (358, 64)]); gem2 = c.array()
    L.paint(gem2, (0.60, 1.0, 1.0), outline=1, outline_col=(0.08, 0.35, 0.45))
    L.glow(gem2, (0.20, 0.90, 1.0), radius=5, strength=0.9)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    c = Canvas(bw, bh); c.line([(74, 14), (128, 160)], 2.8); c.line([(128, 160), (74, 306)], 2.8); cord_b = c.array()
    BL.paint(cord_b, (0.50, 0.95, 1.0), outline=1, outline_col=(0.08, 0.35, 0.45)); BL.glow(cord_b, (0.10, 0.85, 1.0), radius=4, strength=0.8)
    c = Canvas(bw, bh); c.rect(22, 148, 164, 172, r=4); BL.paint(c.array(), shade(c.array(), night_wood, rim=6), outline=3)
    t_limb = cubic_bezier((66, 160), (40, 108), (45, 44), (76, 14), 25)
    b_limb = cubic_bezier((66, 160), (40, 212), (45, 276), (76, 306), 25)
    c = Canvas(bw, bh); c.line(t_limb, 10.5); c.line(b_limb, 10.5); BL.paint(c.array(), shade(c.array(), silver_col, rim=5), outline=3)
    c = Canvas(bw, bh); c.line(t_limb, 2.5); c.line(b_limb, 2.5); BL.paint(c.array(), (0.40, 0.95, 1.0), outline=0); BL.glow(c.array(), (0.15, 0.85, 1.0), radius=4, strength=0.8)
    c = Canvas(bw, bh); c.line([(24, 153), (6, 160), (24, 167)], 5.5); BL.paint(c.array(), shade(c.array(), silver_col, rim=3), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


# ==============================================================================
# 7. DRAGON CROSSBOW (Tier 7)
# ==============================================================================
def draw_dragon_crossbow():
    w, h = 400, 128
    L = Layer(w, h)

    # Braided incandescent golden dragon-tendon
    c = Canvas(w, h); c.line([(324, 12), (145, 57)], 3.2); c.line([(145, 61), (324, 106)], 3.2); cord_m = c.array()
    L.paint(cord_m, (1.0, 0.85, 0.35), outline=1, outline_col=(0.45, 0.20, 0.05))
    L.glow(cord_m, (1.0, 0.60, 0.10), radius=4, strength=0.7)

    # Volcanic obsidian & carved dragon bone stock
    pts = [(16, 48), (50, 46), (85, 48), (155, 48), (325, 48), (325, 70), (285, 70), (145, 68), (95, 70), (84, 92), (60, 92), (68, 70), (35, 78), (16, 70)]
    c = Canvas(w, h); c.poly(pts); stock_m = c.array()
    obsidian_col = (0.24, 0.16, 0.16)
    L.paint(stock_m, shade(stock_m, obsidian_col, rim=7), outline=3)

    # Overlapping golden dragon scales along the stock
    c = Canvas(w, h)
    for x in range(95, 275, 16):
        c.ellipse((x, 52, x + 14, 66))
    scales_m = c.array() * stock_m
    gold_col = (0.95, 0.78, 0.24)
    L.paint(scales_m, shade(scales_m, gold_col, rim=3), outline=1, outline_col=(0.40, 0.25, 0.08))

    # Molten volcanic fire chamber in receiver
    c = Canvas(w, h); c.rect(135, 49, 165, 67, r=3); ch_m = c.array()
    L.paint(ch_m, (1.0, 0.35, 0.08), outline=2, outline_col=(0.35, 0.12, 0.06))
    L.glow(ch_m, (1.0, 0.50, 0.10), radius=6, strength=0.9)

    # Dragon claw trigger guard & pommel
    c = Canvas(w, h)
    c.line([(76, 68), (92, 88), (110, 88), (110, 67)], 3.0) # guard
    c.poly([(16, 52), (4, 59), (16, 66)])                    # tail claw pommel
    L.paint(c.array(), shade(c.array(), gold_col, rim=3), outline=2)

    # Dragon fang quarrel with molten flame tip
    c = Canvas(w, h); c.rect(145, 47, 318, 52); bolt_m = c.array()
    L.paint(bolt_m, shade(bolt_m, gold_col, rim=2), outline=2)
    # Flame tip
    c = Canvas(w, h); c.poly([(314, 43), (338, 49), (314, 55)]); tip_m = c.array()
    L.paint(tip_m, (1.0, 0.40, 0.08), outline=1, outline_col=(0.45, 0.15, 0.05))
    L.glow(tip_m, (1.0, 0.65, 0.15), radius=5, strength=1.0)
    # Golden wing fletchings
    c = Canvas(w, h); c.poly([(142, 42), (166, 47), (142, 47)]); c.poly([(142, 52), (166, 52), (142, 57)])
    L.paint(c.array(), shade(c.array(), (0.85, 0.20, 0.15), rim=2), outline=1)

    # Swept-back dramatic crimson and gold dragon wing limbs
    top_limb = cubic_bezier((286, 56), (335, 40), (352, 16), (324, 12), 25)
    bot_limb = cubic_bezier((286, 62), (335, 78), (352, 102), (324, 106), 25)
    c = Canvas(w, h); c.line(top_limb, 12.0); c.line(bot_limb, 12.0); prod_m = c.array()
    crimson_col = (0.82, 0.16, 0.16)
    L.paint(prod_m, shade(prod_m, crimson_col, rim=6), outline=3)

    # Golden serrated dragon wing edge trim
    c = Canvas(w, h); c.line(top_limb, 4.0); c.line(bot_limb, 4.0); L.paint(c.array() * prod_m, shade(c.array(), gold_col, rim=2), outline=0)

    # Golden dragon wing tip talons/claws
    c = Canvas(w, h)
    c.poly([(320, 8), (338, 2), (328, 18)])
    c.poly([(320, 110), (338, 116), (328, 100)])
    L.paint(c.array(), shade(c.array(), gold_col, rim=3), outline=2)

    # Golden dragon head stirrup maw at front tip!
    c = Canvas(w, h)
    c.poly([(325, 50), (355, 40), (378, 48), (386, 59), (378, 70), (355, 78), (325, 68), (350, 59)])
    dragon_head = c.array()
    L.paint(dragon_head, shade(dragon_head, gold_col, rim=5), outline=2)
    # Glowing ember eyes in dragon head
    c = Canvas(w, h); c.ellipse((356, 47, 362, 53)); c.ellipse((356, 65, 362, 71)); eye_m = c.array()
    L.paint(eye_m, (1.0, 0.90, 0.20), outline=0)
    L.glow(eye_m, (1.0, 0.50, 0.10), radius=4, strength=1.0)

    sw_img = L.to_image()

    # --- BOW.PNG (200x320) ---
    bw, bh = 200, 320
    BL = Layer(bw, bh)
    c = Canvas(bw, bh); c.line([(78, 14), (130, 160)], 3.2); c.line([(130, 160), (78, 306)], 3.2); cord_b = c.array()
    BL.paint(cord_b, (1.0, 0.85, 0.35), outline=1, outline_col=(0.45, 0.20, 0.05)); BL.glow(cord_b, (1.0, 0.60, 0.10), radius=4, strength=0.8)
    c = Canvas(bw, bh); c.rect(20, 147, 165, 173, r=4); BL.paint(c.array(), shade(c.array(), obsidian_col, rim=6), outline=3)
    t_limb = cubic_bezier((68, 160), (36, 106), (40, 42), (80, 14), 25)
    b_limb = cubic_bezier((68, 160), (36, 214), (40, 278), (80, 306), 25)
    c = Canvas(bw, bh); c.line(t_limb, 13.0); c.line(b_limb, 13.0); BL.paint(c.array(), shade(c.array(), crimson_col, rim=6), outline=3)
    c = Canvas(bw, bh); c.line(t_limb, 4.0); c.line(b_limb, 4.0); BL.paint(c.array(), shade(c.array(), gold_col, rim=2), outline=0)
    c = Canvas(bw, bh); c.poly([(76, 8), (96, 2), (86, 22)]); c.poly([(76, 312), (96, 318), (86, 298)]); BL.paint(c.array(), shade(c.array(), gold_col, rim=3), outline=2)
    # Dragon head front
    c = Canvas(bw, bh); c.poly([(24, 150), (4, 144), (-2, 160), (4, 176), (24, 170)]); BL.paint(c.array(), shade(c.array(), gold_col, rim=4), outline=2)
    bow_img = BL.to_image()

    return sw_img, bow_img


CROSSBOW_BUILDERS = {
    "hunting_crossbow": draw_hunting_crossbow,
    "light_crossbow": draw_light_crossbow,
    "arbalest": draw_arbalest,
    "repeating_crossbow": draw_repeating_crossbow,
    "siege_crossbow": draw_siege_crossbow,
    "runic_arbalest": draw_runic_arbalest,
    "dragon_crossbow": draw_dragon_crossbow,
}

def main():
    root = Path("assets/gear/weapon")
    for cid, builder in CROSSBOW_BUILDERS.items():
        out_dir = root / cid
        out_dir.mkdir(parents=True, exist_ok=True)
        sw_img, bow_img = builder()
        # Save Sword.png (400x128)
        sw_img.save(out_dir / "Sword.png")
        # Save Bow.png (200x320)
        bow_img.save(out_dir / "Bow.png")
        # Generate bag icon: rotated by 52 degrees into 192x288 bag cells
        pad = max(sw_img.size)
        big = Image.new("RGBA", (pad * 2, pad * 2), (0, 0, 0, 0))
        big.paste(sw_img, (pad - sw_img.width // 2, pad - sw_img.height // 2))
        rot = big.rotate(52, resample=Image.BICUBIC)
        icon_img = fit_bag(rot, 192, 288, pad_frac=0.92)
        icon_img.save(out_dir / "icon.png")
        print(f"Generated {cid}: Sword.png (400x128), Bow.png (200x320), icon.png (192x288)")

if __name__ == "__main__":
    main()
