"""Copies skill and support gem icons from the CraftPix skill icon packs into assets/icons/skills/
<id>.png (160 x 160), where SkillIcons finds them. ICONS maps a skill or support id to (part of the
pack zip's name, icon number in its PNG folder). Pick new ones from a pack's contact sheet.

Usage:  python tools/import_skill_icons.py <folder with the skill icon zips>
"""
import io
import os
import re
import sys
import zipfile

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons", "skills")
SIZE = 160

ICONS = {
    # Warrior skills
    "cleave": ("229027-rpg-warrior", 11),
    "frenzy": ("229027-rpg-warrior", 27),
    "sundering_strike": ("berserker", 49),
    "whirlwind": ("berserker", 39),
    "double_swing": ("berserker", 13),
    "rend": ("berserker", 44),
    "blade_vortex": ("229027-rpg-warrior", 39),
    "ground_stomp": ("berserker", 9),
    "iron_skin": ("rpg-buff-skill", 34),
    "threatening_shout": ("229027-rpg-warrior", 43),
    "ignore_pain": ("229027-rpg-warrior", 49),
    "leap": ("berserker", 21),
    "leap_slam": ("earth-magician", 35),
    "shield_slam": ("229027-rpg-warrior", 46),
    "taunt": ("berserker", 41),
    "spear_throw": ("spearman", 37),
    "earthquake": ("earth-magician", 43),
    "battle_cry": ("berserker", 47),
    "war_cry": ("rpg-buff-skill", 41),
    "battle_standard": ("rpg-buff-skill", 12),
    "berserk": ("berserker", 48),
    "colossus": ("earth-magician", 21),
    "ancients": ("229027-rpg-warrior", 34),
    # Ranger, rogue and mage skills, and the hireling Scouts' (packs picked by their CraftPix number)
    "quick_shot": ("194977", 5),
    "power_shot": ("194977", 8),
    "multishot": ("194977", 15),
    "arrow_rain": ("194977", 45),
    "fan_of_knives": ("416397", 16),
    "shadow_step": ("416397", 27),
    "death_blossom": ("416397", 47),
    "viper_strike": ("416397", 42),
    "firebolt": ("815119", 21),
    "meteor": ("815119", 22),
    "frost_nova": ("171551", 40),
    "arc": ("134539", 1),
    "arcane_ward": ("134539", 22),
    "thunderstorm": ("134539", 9),
    "holy_nova": ("390906", 5),
    "smite": ("291633", 31),
    "hl_shot": ("893941", 1),
    "hl_power_shot": ("893941", 5),
    "hl_multishot": ("893941", 12),
    "hl_rain": ("893941", 36),
    # Support gems
    "rune_frost": ("cryomancer", 3),
    "rune_fire": ("pyromancer", 24),
    "rune_lightning": ("lightning-mage", 2),
    "rune_chaos": ("berserker", 15),
    "rune_nova": ("paladin", 12),
    "rune_echo": ("229027-rpg-warrior", 42),
    "rune_reach": ("229027-rpg-warrior", 5),
    "rune_vampiric": ("blood-mage", 1),
    "rune_brutality": ("rpg-buff-skill", 40),
    "rune_alacrity": ("rpg-buff-skill", 24),
    "rune_execute": ("blood-mage", 9),
}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    zips = [z for z in os.listdir(src) if z.endswith(".zip")]
    os.makedirs(OUT, exist_ok=True)
    for sid, (pack, num) in ICONS.items():
        found = [z for z in zips if pack in z]
        if len(found) != 1:
            sys.exit("%s: %d zips match %r" % (sid, len(found), pack))
        zf = zipfile.ZipFile(os.path.join(src, found[0]))
        # (the number is the whole file name, or follows a space: the archer pack's "<word> 5.png")
        name = next((n for n in zf.namelist() if re.search(r"(^|[/ ])%d\.png$" % num, n.lower())
                     and not n.split("/")[-1].startswith("._")), None)
        if name is None:
            sys.exit("%s: no icon %d in %s" % (sid, num, found[0]))
        im = Image.open(io.BytesIO(zf.read(name))).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
        im.save(os.path.join(OUT, sid + ".png"))
    print("wrote %d icons to %s" % (len(ICONS), os.path.abspath(OUT)))


if __name__ == "__main__":
    main()
