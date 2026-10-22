"""Makes the window, panel, button, tab, slot and tooltip art from the CraftPix RPG & MMO user
interface pack (craftpix-net-745192-rpg-mmo-game-user-interface): dark charcoal windows with a thin
gold border, a header band with blue scrollwork, tinted bevel buttons.

  assets/ui/mmo/window.png          window body (9-slice, margin 12)
  assets/ui/mmo/window_header.png   window with its title band: scrollwork in both top corners and a
                                    gold rule under the band (9-slice: left / right HEADER_SIDE,
                                    top HEADER_TOP, bottom 12)
  assets/ui/mmo/header_ornament.png the gold V under the middle of a title
  assets/ui/mmo/inset.png           a section inside a window (the pack's list row)
  assets/ui/mmo/tooltip.png         tooltip / card frame
  assets/ui/mmo/slot.png            an item slot
  assets/ui/mmo/button.png          bevel button face, greyscale, tinted per use (9-slice, margin 10)
  assets/ui/mmo/tab_active.png      the open tab: a soft glow with a bright rule along the bottom
  assets/ui/mmo/close*.png          square close button (normal, hover, pressed)
  assets/ui/mmo/slot_icons/<slot>.png  equipment slot silhouettes

Usage:  python tools/import_mmo_ui.py <craftpix-net-745192-rpg-mmo-game-user-interface.zip>
"""
import io
import os
import sys
import zipfile

from PIL import Image, ImageEnhance, ImageOps

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "assets", "ui", "mmo")
T = "Textures/"

HEADER_W, HEADER_H = 560, 200
HEADER_BAND = 70  # the title band's height inside the frame
HEADER_SIDE = 190  # each corner's width (the scrollwork), kept as is when stretched
BORDER = 9  # the window frame's shadow and gold edge
HEADER_TOP = BORDER + HEADER_BAND + 4
SWIRL_W = 170
SWIRL_ALPHA = 0.55  # quiet enough for a row of tabs on the band to read over it
SWIRL_TINT = (70, 170, 215)

HUD_OUT = os.path.join(HERE, "..", "assets", "ui", "hud")
HUD = {
    "HUD/Action Bar/Globes/ActionBar_Globe_Background.png": "globe_bg",
    "HUD/Action Bar/Globes/ActionBar_Globe_Fill_Red.png": "globe_fill_red",
    "HUD/Action Bar/Globes/ActionBar_Globe_Fill_Grayscale.png": "globe_fill_grey",
    "HUD/Action Bar/Globes/ActionBar_Globe_Fill_Empty.png": "globe_fill_empty",
    "Mobile/Action Buttons/ABL_Background.png": "abl_bg",
    "Mobile/Action Buttons/ABM_Background.png": "abm_bg",
    "Mobile/Action Buttons/ABM_CooldownGlow.png": "abm_glow",
    "Mobile/Joystick/Joystick_Background.png": "joy_bg",
    "Mobile/Joystick/Joystick_Handle.png": "joy_handle",
    "HUD/Action Bar/Experience Bar/XPBar_Background.png": "xp_bg",
    "HUD/Action Bar/Experience Bar/XPBar_Fill.png": "xp_bar_fill",
    "HUD/Action Bar/Slots/ActionBar_MainSlot_Background.png": "bar_slot",
    "HUD/Action Bar/XP Tooltip/XPTooltip_Background_Side.png": "xp_tag",
    "HUD/Action Bar/XP Tooltip/XPTooltip_Background_Arrow.png": "xp_tag_arrow",
}

# Equipment slot silhouettes: Tainted slot -> the pack's icon
SLOT_ICONS = {
    "weapon": "MainWeapon", "offhand": "OffWeapon", "helmet": "Helmet", "chest": "Chest",
    "gloves": "Gloves", "boots": "Boots", "belt": "Belt", "ring": "Ring", "amulet": "Necklace",
}


def nine(im, w, h, m):
    """`im` stretched to w x h with its m-pixel border kept (a 9-slice)."""
    out = Image.new("RGBA", (w, h))
    sw, sh = im.size
    xs = [(0, m, 0, m), (m, sw - m, m, w - m), (sw - m, sw, w - m, w)]
    ys = [(0, m, 0, m), (m, sh - m, m, h - m), (sh - m, sh, h - m, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            if dx1 > dx0 and dy1 > dy0:
                out.alpha_composite(im.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS), (dx0, dy0))
    return out


def tint(im, rgb):
    """A greyscale-ish image recoloured: its brightness times `rgb`, alpha kept."""
    grey = ImageOps.grayscale(im.convert("RGB"))
    hi = max(grey.getextrema()[1], 1)  # its brightest becomes the full colour
    r, g, b = (grey.point(lambda v, c=c: min(255, v * c // hi)) for c in rgb)
    return Image.merge("RGBA", (r, g, b, im.getchannel("A")))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    z = zipfile.ZipFile(sys.argv[1])

    def img(path):
        return Image.open(io.BytesIO(z.read(T + path))).convert("RGBA")

    os.makedirs(os.path.join(OUT, "slot_icons"), exist_ok=True)

    def save(im, name):
        im.save(os.path.join(OUT, name + ".png"))

    window = img("Windows/Window/Window_Background.png")
    save(window, "window")
    save(img("Windows/Spellbook/Spellbook_Row_Background.png"), "inset")
    save(img("HUD/Tooltip/Tooltip_Background.png"), "tooltip")
    save(img("Windows/Inventory/Inventory_Slot_Background.png"), "slot")
    save(img("Windows/Window/Header/Window_Header_Border_Center.png"), "header_ornament")

    # The window with its title band
    head = nine(window, HEADER_W, HEADER_H, 12)
    band = Image.new("RGBA", (HEADER_W - 2 * BORDER, HEADER_BAND))
    band.alpha_composite(img("Windows/Window/Header/Window_Header_Background.png").resize(band.size))
    band.alpha_composite(img("Windows/Window/Header/Window_Header_Gradient.png").resize(band.size))
    shadow = img("Windows/Window/Header/Window_Header_Tribals_Background.png")
    swirl = tint(img("Windows/Window/Header/Window_Header_Tribals_Fill.png"), SWIRL_TINT)
    sh = int(swirl.height * SWIRL_W / swirl.width)
    shadow = shadow.resize((SWIRL_W, int(shadow.height * SWIRL_W / shadow.width)), Image.LANCZOS)
    swirl = swirl.resize((SWIRL_W, sh), Image.LANCZOS)
    swirl.putalpha(swirl.getchannel("A").point(lambda v: int(v * SWIRL_ALPHA)))
    for flip in (False, True):
        s, d = (ImageOps.mirror(swirl), ImageOps.mirror(shadow)) if flip else (swirl, shadow)
        x = band.width - SWIRL_W - 2 if flip else 2
        y = (HEADER_BAND - sh) // 2
        band.alpha_composite(d, (x, y))
        band.alpha_composite(s, (x, y))
    head.alpha_composite(band, (BORDER, BORDER))
    # The gold rule under the band, in the frame's own gold, with a dark line beneath it
    y = BORDER + HEADER_BAND
    gold = window.getpixel((7, 32))
    for x in range(BORDER, HEADER_W - BORDER):
        head.putpixel((x, y), gold)
        head.putpixel((x, y + 1), gold)
        head.putpixel((x, y + 2), (0, 0, 0, 160))
    save(head, "window_header")

    # Buttons: the bevel plate at half size (it is drawn for 170 px tall buttons)
    plate = img("Controls/Buttons/Rectangular/Large/Button_RL_Background.png")
    save(plate.resize((plate.width // 2, plate.height // 2), Image.LANCZOS), "button")

    # The open tab: the glow, a bright rule at its foot
    glow = img("Windows/Window/Tabs/Window_Tabs_Active_Gradient.png").resize((256, 56), Image.LANCZOS)
    line = img("Windows/Window/Tabs/Window_Tabs_Active_Border.png").resize((256, 4), Image.LANCZOS)
    glow.alpha_composite(line, (0, glow.height - line.height))
    save(glow, "tab_active")

    # Close button: the square plate with its cross; hover brighter, pressed darker
    sq = img("Controls/Buttons/Square/Button_S1_Background.png")
    cross = img("Controls/Buttons/Square/Icons/Button_S1_Icon_Close.png")
    close = sq.copy()
    close.alpha_composite(cross, ((sq.width - cross.width) // 2, (sq.height - cross.height) // 2))
    save(close, "close")
    save(ImageEnhance.Brightness(close).enhance(1.35), "close_hover")
    save(ImageEnhance.Brightness(close).enhance(0.7), "close_pressed")

    for slot, name in SLOT_ICONS.items():
        save(img("Windows/Character/Equip Slot/Icons/%s.png" % name), "slot_icons/" + slot)

    # The HUD: orbs, skill and flask buttons, joystick, experience bar (HudArt draws them, placed by
    # the round opening inside each frame, measured in HudArt.HOLES)
    for src, name in HUD.items():
        im = img(src)
        im.save(os.path.join(HUD_OUT, name + ".png"))
    # The curl at the foot of each globe, between it and the bar (the pack's is the left globe's)
    curl = img("HUD/Action Bar/ActionBar_Tribals.png")
    curl.save(os.path.join(HUD_OUT, "bar_curl_left.png"))
    ImageOps.mirror(curl).save(os.path.join(HUD_OUT, "bar_curl_right.png"))
    print("wrote the MMO UI art to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
