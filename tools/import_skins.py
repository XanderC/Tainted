"""Copies whole characters from the CraftPix chibi packs into assets/skins/<id>/ for town NPCs and
monsters. Every pack uses the same 12-part rig, so a skin is just that character's part images on
the game's rig (RigSprite.skin). Archers hold a Bow and Arrow instead of a Sword and SlashFX; the
game draws them on the archer rig (assets/rigs/archer, baked from an archer pack's Animations.scml
with tools/spriter_to_json.py). Pick characters in SKINS below: id -> (part of the zip's name,
character folder in it); several packs reuse folder names such as Magician_1, hence the zip part.

Usage:  python tools/import_skins.py <folder with the CraftPix zips>
"""
import os
import sys
import zipfile

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "skins")
BODY_PARTS = ["Head", "Face 01", "Face 02", "Face 03", "Body", "Left Arm", "Right Arm", "Left Hand",
              "Right Hand", "Left Leg", "Right Leg"]
WEAPON_PARTS = (["Sword", "SlashFX"], ["Bow", "Arrow"])  # a sword fighter or an archer

SKINS = {
    # Town NPCs
    "blacksmith": ("891150-4-chibi", "Blacksmith Guy"),
    "merchant": ("desert-nomad", "Desert_Nomad_2"),
    "stash_keeper": ("medieval-king", "Medieval Sergeant"),
    "battlemaster": ("medieval-warrior-chibi", "Medieval Commander"),
    "jeweler": ("gnome", "Gnome_2"),
    "sage": ("seer", "Seer_1"),
    "caravan_master": ("persian", "Persian_and_Arab_Warriors_2"),
    "caravan_guard": ("mercenaries", "Mercenaries_1"),
    # Undead
    "zombie_villager_1": ("zombie-villager", "Zombie_Villager_1"),
    "zombie_villager_2": ("zombie-villager", "Zombie_Villager_2"),
    "zombie_villager_3": ("zombie-villager", "Zombie_Villager_3"),
    "skeleton_1": ("789911-skeleton", "Skeleton_1"),
    "skeleton_2": ("789911-skeleton", "Skeleton_2"),
    "skeleton_3": ("789911-skeleton", "Skeleton_3"),
    "skeleton_warrior_1": ("skeleton-warrior", "Skeleton_Warrior_1"),
    "skeleton_warrior_2": ("skeleton-warrior", "Skeleton_Warrior_2"),
    "ghoul": ("ghoul-lich-mummy", "Ghoul"),
    "mummy": ("ghoul-lich-mummy", "Mummy"),
    # Greenskins and beasts
    "goblin": ("orc-ogre-and-goblin", "Goblin"),
    "goblin_1": ("172129-goblin", "Goblin_1"),
    "goblin_2": ("172129-goblin", "Goblin_2"),
    "goblin_3": ("172129-goblin", "Goblin_3"),
    "orc": ("orc-ogre-and-goblin", "Orc"),
    "orc_shaman_1": ("orc-shaman", "Shamans_1"),
    "orc_shaman_2": ("orc-shaman", "Shamans_2"),
    "gnoll": ("gnoll", "Gnoll"),
    # Darker things, deeper in
    "dark_elf_1": ("dark-elves", "Dark_Elves_1"),
    "dark_elf_2": ("dark-elves", "Dark_Elves_2"),
    "skeleton_viking_1": ("skeleton-viking", "Skeleton_Viking_1"),
    "skeleton_viking_2": ("skeleton-viking", "Skeleton_Viking_2"),
    "skeleton_crusader_1": ("skeleton-crusader", "Skeleton_Crusader_1"),
    "skeleton_crusader_2": ("skeleton-crusader", "Skeleton_Crusader_2"),
    "devil": ("devil-hell-knight", "Devil"),
    "ghost_knight": ("316278-ghost-knight", "Ghost_Knight_1"),
    # Bosses
    "minotaur": ("minotaur", "Minotaur_1"),
    "golem": ("golems", "Golem_1"),
    "ogre": ("orc-ogre-and-goblin", "Ogre"),
    "lich": ("ghoul-lich-mummy", "Lich"),
    "death_knight": ("097812-death-knight", "Death_Knight"),
    "demon": ("demon-of-darkness", "Demons_of_Darkness_1"),
    "hell_knight": ("devil-hell-knight", "Hell_Knight"),
    "blood_demon": ("blood-demon", "Blood_Demon_1"),
    # Archers (archer rig)
    "archer_1": ("341176-archer", "Archer_1"),
    "archer_2": ("341176-archer", "Archer_2"),
    "archer_3": ("341176-archer", "Archer_3"),
    "elf_archer_1": ("elf-archer", "Archer_1"),
    "elf_archer_2": ("elf-archer", "Archer_2"),
    "elf_archer_3": ("elf-archer", "Archer_3"),
    "undead_archer_1": ("undead-archer", "Archer_1"),
    "undead_archer_2": ("undead-archer", "Archer_2"),
    "undead_archer_3": ("undead-archer", "Archer_3"),
    "skeleton_archer_1": ("skeleton-archer", "Archer_1"),
    "skeleton_archer_2": ("skeleton-archer", "Archer_2"),
    "skeleton_archer_3": ("skeleton-archer", "Archer_3"),
    "skeleton_hunter_1": ("skeleton-hunter", "Skeleton_Hunter_1"),
    "skeleton_hunter_2": ("skeleton-hunter", "Skeleton_Hunter_2"),
    "skeleton_hunter_3": ("skeleton-hunter", "Skeleton_Hunter_3"),
    "forest_ranger_1": ("forest-ranger", "Forest_Ranger_1"),
    "forest_ranger_2": ("forest-ranger", "Forest_Ranger_2"),
    "forest_ranger_3": ("forest-ranger", "Forest_Ranger_3"),
    "archer_guy": ("archer-barbarian-mage", "Archer Guy"),
}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    zips = [z for z in sorted(os.listdir(src)) if z.endswith(".zip") and " (1)" not in z]
    for sid, (zip_part, char) in SKINS.items():
        matches = [z for z in zips if zip_part in z]
        if len(matches) != 1:
            sys.exit("%s: %d zips match %r" % (sid, len(matches), zip_part))
        zf = zipfile.ZipFile(os.path.join(src, matches[0]))
        found = {}
        for n in zf.namelist():
            if n.startswith(char + "/") and "/Vector Parts/" in n and n.endswith(".png") \
                    and not n.split("/")[-1].startswith("._"):
                found[n.split("/")[-1][:-4]] = n
        weapon = next((w for w in WEAPON_PARTS if all(p in found for p in w)), None)
        if weapon is None:
            sys.exit("%s (%s): no sword or bow" % (sid, char))
        parts = BODY_PARTS + weapon
        # A closed helmet has no face: it gets a blank one, so the rig's own face doesn't show
        missing = [p for p in parts if p not in found and not p.startswith("Face")]
        if missing:
            sys.exit("%s (%s): missing %s" % (sid, char, missing))
        d = os.path.join(OUT, sid)
        os.makedirs(d, exist_ok=True)
        for p in parts:
            if p not in found:
                Image.new("RGBA", (320, 240)).save(os.path.join(d, p + ".png"))
                continue
            with open(os.path.join(d, p + ".png"), "wb") as f:
                f.write(zf.read(found[p]))
    print("wrote %d skins to %s" % (len(SKINS), os.path.abspath(OUT)))


if __name__ == "__main__":
    main()
