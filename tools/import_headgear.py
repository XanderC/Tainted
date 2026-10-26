"""Cuts every kind of headgear (helmets, hoods, hats, crowns, circlets, turbans, masks...) out of the
CraftPix chibi character packs, from their vector sources, for items to wear.

Each character in the packs (on the NAS, Tainted > assets > sprites) has an Illustrator file whose
first artboard is its head, drawn as separate vector objects, back to front: the bare head (its skin
shape, then its outline ring; sometimes hair at the back comes first), then ears, hair, beard and
stubble, and the headgear with its own fills, outlines and shading (usually last). So a piece of
headgear is taken as exactly its own objects (no colour guessing, no cropped edges), drawn alone:

  assets/gear/helmet/<id>/Head.png  - worn: on the sword rig's 480 x 480 Head canvas, fitted to the
                                      player's bare head (assets/appearance/base_male.png) by
                                      lining the source's head outline up with it (top, bottom and
                                      face side: the packs draw heads a little differently, and the
                                      archer packs on a 600 px canvas)
  assets/gear/helmet/<id>/icon.png  - in the bag, fitted into its 2 x 2 cells
  assets/gear/helmet/catalog.json   - every piece: name, kind, whether it hides the hair, source

HEADGEAR maps an id to its source character ("<words from the pack's zip name>/<character folder>")
and how to cut it:
  objects - which objects are the headgear, as numbers and ranges ("16-48", [6, 7, "9-12"]); by
            default every object but the bare head. --objects <id> shows them numbered.
  skip    - objects in those that aren't headgear (a beard drawn among them)
  keep    - objects to keep although they look like skin (a skin-coloured face plate)
  whole   - the source has no bare head: its head shape is the headgear's own shell (a great helm,
            a hood, a pumpkin), so that is kept too; skin showing through it (a hood's face
            opening) is still left out
Skin-coloured objects (ears) and the details drawn on them are left out, and so are specks that
don't touch the headgear's bigger pieces (stubble, a wrinkle drawn last).

Usage:  python tools/import_headgear.py [--src <folder with the zips>] [id ...]
        python tools/import_headgear.py --objects <id> ...  (a sheet of their sources' objects, to
                                                             pick objects / skip; --out <folder>)
"""
import argparse
import io
import json
import multiprocessing
import os
import traceback
import zipfile

import numpy as np
import pikepdf
import pymupdf
from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "assets", "gear", "helmet")
BASE_HEAD = os.path.join(HERE, "..", "assets", "appearance", "base_male.png")
SRC = "Y:/Tainted/assets/sprites"  # the NAS share (\\OPENMEDIAVAULT\Storage)
CANVAS = 480
CELL = 96  # icon pixels per bag cell (as tools/import_weapons.py)
SUPER = 2  # render at this many times the canvas, then fit down
LOOK = 0.5  # objects are told apart at this fraction of the canvas

# id: name, kind, source ("<pack>/<character folder>"), and cut options. kind is one of
# helmet, great_helm, hood, hat, crown, circlet, headband, turban, mask, wrap, novelty.
# Crowns, circlets, headbands and masks leave the hair showing; the rest hide it.
HEADGEAR = {
    "death_visage": {"name": "Death Visage", "kind": "great_helm", "source": "death-knight-skeleton/Death_Knight"},
    "ranger_hood": {"name": "Ranger's Hood", "kind": "hood", "source": "archer-chibi-2d/Archer_2"},
    "shrouded_hood": {"name": "Shrouded Hood", "kind": "hood", "source": "archer-chibi-2d/Archer_3"},
    "bandit_mask": {"name": "Bandit Mask", "kind": "mask", "source": "archer-barbarian/Archer Guy", "objects": "6-8"},
    "wizard_hat": {"name": "Wizard Hat", "kind": "hat", "source": "archer-barbarian/Medieval Mage", "objects": "9-99"},
    "pumpkin_head": {"name": "Pumpkin Head", "kind": "novelty", "source": "halloween/Pumpkin Head Guy", "whole": True},
    "corinthian_helm": {"name": "Corinthian Helm", "kind": "great_helm", "source": "spartan/Greek Warrior"},
    "legionary_helm": {"name": "Legionary Helm", "kind": "helmet", "source": "spartan/Spartan Knight with Spear"},
    "elven_hood": {"name": "Elven Hood", "kind": "hood", "source": "elf-archer/Archer_1"},
    "leaf_circlet": {"name": "Leaf Circlet", "kind": "circlet", "source": "elf-archer/Archer_2", "objects": [38]},
    "dusk_hood": {"name": "Dusk Hood", "kind": "hood", "source": "elf-archer/Archer_3"},
    "frost_cowl": {"name": "Frost Cowl", "kind": "hood", "source": "magician-chibi-2d/Magician_1"},
    "emerald_cowl": {"name": "Emerald Cowl", "kind": "hood", "source": "magician-chibi-2d/Magician_2"},
    "rune_cowl": {"name": "Rune Cowl", "kind": "hood", "source": "magician-chibi-2d/Magician_3"},
    "lich_crown": {"name": "Lich Crown", "kind": "hood", "source": "ghoul-lich/Lich", "objects": [1, 7, 8, "37-43", "60-99"]},
    "mummy_wraps": {"name": "Mummy Wraps", "kind": "wrap", "source": "ghoul-lich/Mummy", "whole": True},
    "pointed_hood": {"name": "Pointed Hood", "kind": "hood", "source": "fantasy/Black Wizard"},
    "oni_mask": {"name": "Oni Mask", "kind": "mask", "source": "fantasy/Devil Masked Guy"},
    "crimson_hood": {"name": "Crimson Hood", "kind": "hood", "source": "fantasy/Medieval Hooded Girl", "objects": [4, 5, "12-99"]},
    "grave_hood": {"name": "Grave Hood", "kind": "hood", "source": "undead-archer/Archer_1"},
    "kettle_helm": {"name": "Kettle Helm", "kind": "helmet", "source": "undead-archer/Archer_3"},
    "sentinel_helm": {"name": "Sentinel Helm", "kind": "helmet", "source": "armored/Medieval Knight"},
    "silver_visor": {"name": "Silver Visor", "kind": "helmet", "source": "armored/White Armored Knight"},
    "rag_bandana": {"name": "Rag Bandana", "kind": "headband", "source": "skeleton-chibi/Skeleton_2", "objects": [2, 36, 37]},
    "infernal_crown": {"name": "Infernal Crown", "kind": "crown", "source": "devil/Hell_Knight"},
    "assassins_hood": {"name": "Assassin's Hood", "kind": "hood", "source": "ninja/Assassin Guy"},
    "shinobi_hood": {"name": "Shinobi Hood", "kind": "hood", "source": "ninja/Black Ninja", "whole": True},
    "shinobi_wrap": {"name": "Shinobi Wrap", "kind": "wrap", "source": "ninja/White Ninja"},
    "rope_headband": {"name": "Rope Headband", "kind": "headband", "source": "4-chibi-character/Blacksmith Guy", "objects": "12-22"},
    "thug_mask": {"name": "Thug's Mask", "kind": "mask", "source": "4-chibi-character/Medieval Thug", "objects": "4-5"},
    "horned_cowl": {"name": "Horned Cowl", "kind": "hood", "source": "magician-undead/Magician_1"},
    "veiled_cowl": {"name": "Veiled Cowl", "kind": "hood", "source": "magician-undead/Magician_2"},
    "jeweled_cowl": {"name": "Jeweled Cowl", "kind": "hood", "source": "magician-undead/Magician_3"},
    "night_cowl": {"name": "Night Cowl", "kind": "hood", "source": "magician-demon/Magician_2"},
    "gnoll_hood": {"name": "Hide Hood", "kind": "hood", "source": "gnoll/Gnoll/Gnoll_2", "objects": [0, 1, "48-99"]},
    "reapers_hood": {"name": "Reaper's Hood", "kind": "hood", "source": "free-reaper/Reaper_Man_1"},
    "deathshroud": {"name": "Deathshroud", "kind": "hood", "source": "free-reaper/Reaper_Man_2"},
    "fur_cowl": {"name": "Fur Cowl", "kind": "hood", "source": "free-reaper/Reaper_Man_3"},
    "demon_helm": {"name": "Demon Helm", "kind": "great_helm", "source": "demon-of/Demons_of_Darkness_2"},
    "royal_crown": {"name": "Royal Crown", "kind": "crown", "source": "medieval-king/Medieval King", "objects": "16-99"},
    "iron_helm": {"name": "Iron Helm", "kind": "helmet", "source": "medieval-king/Medieval Sergeant", "objects": "29-99"},
    "plumed_greathelm": {"name": "Plumed Great Helm", "kind": "great_helm", "source": "medieval-king/Very Heavy Armored Frontier Defender"},
    "shadow_helm": {"name": "Shadow Helm", "kind": "helmet", "source": "dark-elves/Dark_Elves_1", "objects": "3-22"},
    "elven_helm": {"name": "Elven Helm", "kind": "helmet", "source": "dark-elves/Dark_Elves_2"},
    "drow_helm": {"name": "Drow Helm", "kind": "helmet", "source": "dark-elves/Dark_Elves_3"},
    "seraph_crown": {"name": "Seraph Crown", "kind": "crown", "source": "free-fallen/Fallen_Angels_3"},
    "studded_cap": {"name": "Studded Cap", "kind": "hat", "source": "chibi-shaman/Shaman_of_Thunder_1"},
    "knights_helm": {"name": "Knight's Helm", "kind": "helmet", "source": "free-chibi-skeleton-warrior/Skeleton_Warrior_2"},
    "coif_helm": {"name": "Coif Helm", "kind": "helmet", "source": "free-chibi-skeleton-warrior/Skeleton_Warrior_3"},
    "crusader_helm": {"name": "Crusader Helm", "kind": "helmet", "source": "free-chibi-skeleton-crusader/Skeleton_Crusader_1"},
    "goblin_horned_helm": {"name": "Horned Helm", "kind": "helmet", "source": "goblin-chibi-character/Goblin_1", "objects": "14-99"},
    "viking_helm": {"name": "Viking Helm", "kind": "helmet", "source": "chibi-skeleton-viking/Skeleton_Viking_1"},
    "horned_cap": {"name": "Horned Cap", "kind": "helmet", "source": "chibi-skeleton-viking/Skeleton_Viking_2"},
    "travelers_hat": {"name": "Traveller's Hat", "kind": "hat", "source": "human/Human Magician_1", "objects": "37-99"},
    "buckled_hat": {"name": "Buckled Hat", "kind": "hat", "source": "human/Human Magician_2", "objects": "43-99"},
    "gilded_hood": {"name": "Gilded Hood", "kind": "hood", "source": "human/Human Magician_3"},
    "fur_hood": {"name": "Fur Hood", "kind": "hood", "source": "viking-chibi/Viking_1"},
    "raider_helm": {"name": "Raider Helm", "kind": "helmet", "source": "viking-chibi/Viking_2", "objects": "12-99"},
    "violet_hood": {"name": "Violet Hood", "kind": "hood", "source": "chibi-skeleton-necromancer/Skeleton_Necromancer_1"},
    "mossy_hood": {"name": "Mossy Hood", "kind": "hood", "source": "chibi-skeleton-necromancer/Skeleton_Necromancer_2"},
    "ebon_hood": {"name": "Ebon Hood", "kind": "hood", "source": "chibi-skeleton-necromancer/Skeleton_Necromancer_3"},
    "frost_crown": {"name": "Frost Crown", "kind": "crown", "source": "chibi-winter/Winter_Witch_1", "objects": "33-99"},
    "silvered_hood": {"name": "Silvered Hood", "kind": "hood", "source": "chibi-winter/Winter_Witch_3"},
    "grey_hood": {"name": "Grey Hood", "kind": "hood", "source": "gnome/Gnome_1"},
    "leather_cap": {"name": "Leather Cap", "kind": "hat", "source": "gnome/Gnome_2", "objects": "43-99"},
    "gnome_hood": {"name": "Gnome Hood", "kind": "hood", "source": "gnome/Gnome_3", "objects": [1, 2, "41-99"]},
    "striped_helm": {"name": "Striped Helm", "kind": "helmet", "source": "girl-knight/Girl_Knight_3"},
    "dread_helm": {"name": "Dread Helm", "kind": "helmet", "source": "chibi-skeleton-death/Skeleton_Death_Knight_1", "objects": [2, 3, "35-99"]},
    "verdant_dread_helm": {"name": "Verdant Dread Helm", "kind": "helmet", "source": "chibi-skeleton-death/Skeleton_Death_Knight_2"},
    "dread_hood": {"name": "Dread Hood", "kind": "hood", "source": "chibi-skeleton-death/Skeleton_Death_Knight_3"},
    "tattered_hood": {"name": "Tattered Hood", "kind": "hood", "source": "chibi-skeleton-archer/Archer_1"},
    "hunters_hood": {"name": "Hunter's Hood", "kind": "hood", "source": "chibi-skeleton-archer/Archer_2"},
    "dark_hood": {"name": "Dark Hood", "kind": "hood", "source": "chibi-skeleton-archer/Archer_3"},
    "sapphire_turban": {"name": "Sapphire Turban", "kind": "turban", "source": "persian/Persian_and_Arab_Warriors_1", "objects": "33-70"},
    "white_turban": {"name": "White Turban", "kind": "turban", "source": "persian/Persian_and_Arab_Warriors_2", "objects": [1, 2, "33-99"]},
    "crimson_turban": {"name": "Crimson Turban", "kind": "turban", "source": "persian/Persian_and_Arab_Warriors_3", "objects": "57-110"},
    "druids_hood": {"name": "Druid's Hood", "kind": "hood", "source": "forest-guardian/Forest_Guardian_3"},
    "fang_band": {"name": "Fang Band", "kind": "headband", "source": "chibi-skeleton-shaman/Skeleton_Shaman_1", "objects": "37-99"},
    "bone_diadem": {"name": "Bone Diadem", "kind": "crown", "source": "chibi-skeleton-shaman/Skeleton_Shaman_2"},
    "rime_band": {"name": "Rime Band", "kind": "crown", "source": "chibi-skeleton-shaman/Skeleton_Shaman_3"},
    "rune_hood": {"name": "Rune Hood", "kind": "hood", "source": "chibi-cursed/Cursed_Alchemist_1"},
    "alchemists_hood": {"name": "Alchemist's Hood", "kind": "hood", "source": "chibi-cursed/Cursed_Alchemist_2"},
    "plague_hood": {"name": "Plague Hood", "kind": "hood", "source": "chibi-cursed/Cursed_Alchemist_3", "objects": "39-99"},
    "frost_greathelm": {"name": "Frost Great Helm", "kind": "great_helm", "source": "ghost-knight-chibi/Ghost_Knight_1", "whole": True},
    "moonlit_hood": {"name": "Moonlit Hood", "kind": "hood", "source": "ghost-knight-chibi/Ghost_Knight_2"},
    "tidal_hood": {"name": "Tidal Hood", "kind": "hood", "source": "ghost-knight-chibi/Ghost_Knight_3"},
    "crossed_hat": {"name": "Hunter's Hat", "kind": "hat", "source": "chibi-vampire/Vampire_Hunter_2", "objects": "50-99"},
    "plumed_hat": {"name": "Plumed Hat", "kind": "hat", "source": "chibi-vampire/Vampire_Hunter_3", "objects": "33-99"},
    "ram_skull": {"name": "Ram Skull", "kind": "hat", "source": "shaman-chibi-character/Shaman_2"},
    "winged_helm": {"name": "Winged Helm", "kind": "helmet", "source": "free-chibi-valkyrie/Valkyrie_1"},
    "valkyrie_helm": {"name": "Valkyrie Helm", "kind": "helmet", "source": "free-chibi-valkyrie/Valkyrie_2"},
    "eared_helm": {"name": "Eared Helm", "kind": "helmet", "source": "free-chibi-valkyrie/Valkyrie_3"},
    "flower_hat": {"name": "Flower Hat", "kind": "hat", "source": "women/Citizen-Women_3", "objects": "33-99"},
    "amethyst_circlet": {"name": "Amethyst Circlet", "kind": "circlet", "source": "vampire-chibi/Vampire_2", "objects": "42-50"},
    "silver_circlet": {"name": "Silver Circlet", "kind": "circlet", "source": "magician-girl/Magician_Girl_2"},
    "ember_mask": {"name": "Ember Mask", "kind": "mask", "source": "pyromancer/Pyromancer_1", "objects": "28-35"},
    "golden_hood": {"name": "Golden Hood", "kind": "hood", "source": "pyromancer/Pyromancer_2"},
    "sand_wrap": {"name": "Sand Wrap", "kind": "turban", "source": "desert/Desert_Nomad_1", "objects": [1, 2, "30-99"]},
    "linen_wrap": {"name": "Linen Wrap", "kind": "turban", "source": "desert/Desert_Nomad_2"},
    "nomad_hood": {"name": "Nomad Hood", "kind": "hood", "source": "desert/Desert_Nomad_3"},
    "frost_helm": {"name": "Frost Helm", "kind": "helmet", "source": "frost/Frost_Knight_1"},
    "frost_hood": {"name": "Frost Hood", "kind": "helmet", "source": "frost/Frost_Knight_2"},
    "frost_visor": {"name": "Frost Visor", "kind": "helmet", "source": "frost/Frost_Knight_3"},
    "golden_circlet": {"name": "Golden Circlet", "kind": "circlet", "source": "amazon/Amazon_Warrior_3", "objects": "34-99"},
    "forest_hood": {"name": "Forest Hood", "kind": "hood", "source": "free-forest/Forest_Ranger_1", "objects": "36-99"},
    "leaf_wreath": {"name": "Leaf Wreath", "kind": "circlet", "source": "free-forest/Forest_Ranger_2"},
    "antler_helm": {"name": "Antler Helm", "kind": "helmet", "source": "free-forest/Forest_Ranger_3", "objects": [4, 5, "56-99"]},
    "bone_hood": {"name": "Bone Hood", "kind": "hood", "source": "chibi-skeleton-sorcerer/Skeleton_Sorcerer_3"},
    "horned_leaf_hood": {"name": "Thorn Hood", "kind": "hood", "source": "elemental-spirits/Elemental_Spirits_3", "objects": "16-120"},
    "holy_greathelm": {"name": "Holy Great Helm", "kind": "great_helm", "source": "paladin/Paladin_1", "whole": True},
    "gilded_black_helm": {"name": "Gilded Black Helm", "kind": "great_helm", "source": "paladin/Paladin_2", "whole": True},
    "golden_greathelm": {"name": "Golden Great Helm", "kind": "great_helm", "source": "paladin/Paladin_3", "whole": True, "keep": [0]},
    "heraldic_helm": {"name": "Heraldic Helm", "kind": "great_helm", "source": "655241-knight-chibi-character-sprites/Knight_1", "whole": True},
    "steel_helm": {"name": "Steel Helm", "kind": "helmet", "source": "655241-knight-chibi-character-sprites/Knight_2"},
    "barbute": {"name": "Barbute", "kind": "helmet", "source": "655241-knight-chibi-character-sprites/Knight_3"},
    "captains_hat": {"name": "Captain's Hat", "kind": "hat", "source": "chibi-skeleton-pirate/Skeleton_Pirate_Captain_1"},
    "corsair_hat": {"name": "Corsair Hat", "kind": "hat", "source": "chibi-skeleton-pirate/Skeleton_Pirate_Captain_2"},
    "tricorn": {"name": "Tricorn", "kind": "hat", "source": "chibi-skeleton-pirate/Skeleton_Pirate_Captain_3", "objects": "25-99"},
    "witch_hat": {"name": "Witch Hat", "kind": "hat", "source": "witch-chibi/Witch_1", "objects": "32-99"},
    "witchs_hood": {"name": "Witch's Hood", "kind": "hood", "source": "witch-chibi/Witch_2"},
    "hags_hood": {"name": "Hag's Hood", "kind": "hood", "source": "witch-chibi/Witch_3"},
    "kabuto": {"name": "Kabuto", "kind": "helmet", "source": "samurai/Samurai_1"},
    "straw_hat": {"name": "Straw Hat", "kind": "hat", "source": "samurai/Samurai_2"},
    "gilded_turban": {"name": "Gilded Turban", "kind": "turban", "source": "free-seer/Seer_1"},
    "seers_hood": {"name": "Seer's Hood", "kind": "hood", "source": "free-seer/Seer_2"},
    "golden_mask": {"name": "Golden Mask", "kind": "mask", "source": "free-seer/Seer_3", "objects": "57-99"},
    "spectral_helm": {"name": "Spectral Helm", "kind": "great_helm", "source": "chibi-ghost/Ghost_Knight_1"},
    "wraith_helm": {"name": "Wraith Helm", "kind": "helmet", "source": "chibi-ghost/Ghost_Knight_2", "objects": [29, "53-56"]},
    "black_greathelm": {"name": "Black Great Helm", "kind": "great_helm", "source": "chibi-ghost/Ghost_Knight_3", "whole": True},
    "blindfold": {"name": "Blindfold", "kind": "mask", "source": "chibi-spiritual/Spiritual_Monk_1"},
    "monks_hood": {"name": "Monk's Hood", "kind": "hood", "source": "chibi-spiritual/Spiritual_Monk_3"},
    "wide_brim_hat": {"name": "Wide-brim Hat", "kind": "hat", "source": "chibi-skeleton-hunter/Skeleton_Hunter_1"},
    "feathered_cap": {"name": "Feathered Cap", "kind": "hat", "source": "chibi-skeleton-hunter/Skeleton_Hunter_2", "objects": "29-99"},
    "bowler_hat": {"name": "Bowler Hat", "kind": "hat", "source": "chibi-skeleton-hunter/Skeleton_Hunter_3", "objects": "51-99"},
    "oracle_hood": {"name": "Oracle Hood", "kind": "hood", "source": "free-chibi-dark/Dark_Oracle_1"},
    "lantern_hood": {"name": "Lantern Hood", "kind": "hood", "source": "free-chibi-dark/Dark_Oracle_2"},
    "veiled_hood": {"name": "Veiled Hood", "kind": "hood", "source": "free-chibi-dark/Dark_Oracle_3"},
    "shadow_cowl": {"name": "Shadow Cowl", "kind": "hood", "source": "free-chibi-necromancer/Necromancer_of_the_Shadow_1", "objects": "8-99"},
    "dusk_cowl": {"name": "Dusk Cowl", "kind": "hood", "source": "free-chibi-necromancer/Necromancer_of_the_Shadow_2"},
    "umbral_cowl": {"name": "Umbral Cowl", "kind": "hood", "source": "free-chibi-necromancer/Necromancer_of_the_Shadow_3", "objects": [0, 1, "14-99"]},
    "mercenary_helm": {"name": "Mercenary Helm", "kind": "helmet", "source": "chibi-mercenaries/Mercenaries_2"},
    "barrel_helm": {"name": "Barrel Helm", "kind": "novelty", "source": "mimic/Mimic_3"},
    "blood_helm": {"name": "Blood Helm", "kind": "helmet", "source": "chibi-blood/Blood_Demon_1"},
    "stalkers_hood": {"name": "Stalker's Hood", "kind": "hood", "source": "ghoul-hunter/Ghoul_Hunter_1"},
    "skull_hood": {"name": "Skull Hood", "kind": "hood", "source": "ghoul-hunter/Ghoul_Hunter_2"},
    "brown_hood": {"name": "Brown Hood", "kind": "hood", "source": "ghoul-hunter/Ghoul_Hunter_3", "objects": "30-99"},
}

HAIR_SHOWS = {"crown", "circlet", "headband", "mask"}
## Skin in the packs, for headgear with no bare head to take it from (0..1 RGB)
SKIN_TONES = [(0.93, 0.78, 0.63), (0.88, 0.71, 0.55), (0.85, 0.66, 0.49), (0.74, 0.55, 0.40), (0.98, 0.86, 0.74)]
EAR_AREA = 0.03  # skin-coloured objects bigger than this share of the canvas aren't ears


# ---------------------------------------------------------------- reading the vector heads

class Head:
    """A character's head artboard: its drawing operators, split into objects (the q..Q blocks at
    the level most of them sit at), which can be drawn in any selection."""

    def __init__(self, data):
        self.data = data
        self._pdf = pikepdf.open(io.BytesIO(data))
        page = self._pdf.pages[0]
        self.size = float(page.MediaBox[2]) - float(page.MediaBox[0])
        self.ops = list(pikepdf.parse_content_stream(page))
        depth, starts, blocks = 0, [], {}
        for i, (_, op) in enumerate(self.ops):
            o = str(op)
            if o == "q":
                starts.append(i)
                depth += 1
            elif o == "Q":
                depth -= 1
                blocks.setdefault(depth, []).append((starts.pop(), i + 1))
        level = max(blocks, key=lambda d: len(blocks[d]))
        self.objects = sorted(blocks[level])

    def render(self, keep, scale):
        """The objects in `keep` drawn alone (everything else that isn't an object, like colours
        and clipping, stays), `scale` px per artboard point, as float RGBA 0..1."""
        gone = set()
        for k in range(len(self.objects)):
            if k not in keep:
                gone.update(range(*self.objects[k]))
        pdf = pikepdf.open(io.BytesIO(self.data))
        page = pdf.pages[0]
        page.Contents = pdf.make_stream(pikepdf.unparse_content_stream(
            [x for i, x in enumerate(self.ops) if i not in gone]))
        buf = io.BytesIO()
        pdf.save(buf)
        doc = pymupdf.open(stream=buf.getvalue(), filetype="pdf")
        pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=True)
        a = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, 4).astype(np.float32) / 255.0
        return a


def open_head(src, key):
    """The head artboard of character `key` ("<pack>/<character folder>": the pack is the zip whose
    name has those words in it)."""
    pack, char = key.split("/", 1)
    zips = [z for z in os.listdir(src) if pack in z and z.endswith(".zip") and "(1)" not in z]
    if len(zips) != 1:
        raise SystemExit("%d packs match %r in %s" % (len(zips), pack, src))
    with zipfile.ZipFile(os.path.join(src, zips[0])) as z:
        # The character's own (not a projectile's, such as <char>/Ball/AI/Ball.ai)
        ai = sorted(n for n in z.namelist() if n.lower().endswith(".ai") and n.startswith(char + "/AI/"))
        if not ai:
            raise SystemExit("no .ai for %s in %s" % (char, zips[0]))
        return Head(z.read(ai[0]))


# ---------------------------------------------------------------- cutting

def shrink(mask, r):
    return ~grow(~mask, r)


def grow(mask, r):
    out = mask.copy()
    for _ in range(r):
        o = out.copy()
        o[1:, :] |= out[:-1, :]
        o[:-1, :] |= out[1:, :]
        o[:, 1:] |= out[:, :-1]
        o[:, :-1] |= out[:, 1:]
        out = o
    return out


def numbers(spec):
    """A spec's object numbers: ints and "a-b" ranges, in a list or alone."""
    out = set()
    for part in spec if isinstance(spec, list) else [spec]:
        if isinstance(part, int):
            out.add(part)
        else:
            lo, _, hi = str(part).partition("-")
            out.update(range(int(lo), int(hi or lo) + 1))
    return out


def colour(a):
    w = a[..., 3]
    return (a[..., :3] * w[..., None]).sum((0, 1)) / max(w.sum(), 1e-6)


def bare_head(alone):
    """The bare head's skin shape (the biggest solid object among the first few) and its outline
    ring (the first one after it that goes all round it)."""
    first = range(min(8, len(alone) - 1))
    area = [(alone[i][..., 3] > 0.5).sum() if alone[i][..., 3].max() > 0.95 else 0 for i in first]
    if max(area) == 0:  # nothing solid (a glowing head): the biggest
        area = [(alone[i][..., 3] > 0.5).sum() for i in first]
    skin = int(np.argmax(area))
    ys, xs = np.nonzero(alone[skin][..., 3] > 0.5)
    for i in range(skin + 1, min(skin + 40, len(alone))):
        ry, rx = np.nonzero(alone[i][..., 3] > 0.5)
        if len(ry) and ry.min() <= ys.min() and ry.max() >= ys.max() and rx.min() <= xs.min() and rx.max() >= xs.max():
            return skin, i  # the first one drawn round it
    return skin, skin


def headgear_objects(head, spec, scale):
    """Which objects are the headgear (spec objects, or all but the bare head), without
    skin-coloured ones (ears) and the details drawn on them, spec skip, and specks off the headgear.
    Also the bare head's two objects and every object drawn alone (at `scale`)."""
    n = len(head.objects)
    alone = [head.render({i}, scale) for i in range(n)]
    skin_i, ring_i = bare_head(alone)
    whole = spec.get("whole", False)
    tones = [np.array(t) for t in SKIN_TONES]
    own = colour(alone[skin_i])
    # The head shape's colour is the skin's, unless it's no skin colour (a helmet drawn as the head)
    skins = tones if whole or min(np.abs(own - t).sum() for t in tones) > 0.35 else [own]
    wanted = numbers(spec["objects"]) if "objects" in spec else set(range(n)) - ({skin_i, ring_i} if not whole else set())
    wanted -= numbers(spec.get("skip", []))
    keep_skin = numbers(spec.get("keep", []))
    skin_mask = np.zeros(alone[0].shape[:2], bool)
    keep = []
    for i in sorted(wanted):
        if i >= n:
            break
        a = alone[i]
        m = a[..., 3] > 0.5
        if not m.any():
            continue
        # Skin: an ear, a face drawn over the head, skin through a face opening. A colour only a
        # little like the skin's (a gold turban on a tan head) counts only for something ear-sized.
        off = min(np.abs(colour(a) - t).sum() for t in skins)
        skin_like = off < 0.05 or (off < (0.15 if whole else 0.10) and (whole or m.sum() < EAR_AREA * m.size))
        if a[..., 3].max() > 0.95 and skin_like and i not in keep_skin:
            skin_mask |= m
            continue
        if skin_mask.any() and (m & ~grow(skin_mask, 4)).sum() < 0.05 * m.sum():
            continue  # drawn on an ear
        keep.append(i)
    # The headgear's fills: big solid shapes that aren't lines (an outline is gone when thinned a
    # little). Outlines, shading and details count only where they lie along those: not a skull's
    # jaw line drawn apart from its head, not stubble on the chin.
    big = 0.004 * skin_mask.size
    core = np.zeros_like(skin_mask)
    for i in keep:
        m = alone[i][..., 3] > 0.5
        if alone[i][..., 3].max() > 0.95 and m.sum() > big and shrink(m, 3).sum() > 0.25 * m.sum():
            core |= m
    if not core.any():  # all lines (a circlet's band): every piece counts
        for i in keep:
            core |= alone[i][..., 3] > 0.5
    near = grow(core, 6)
    inside = grow(core, 1)
    final, solids = set(), np.zeros_like(core)
    for i in keep:
        m = alone[i][..., 3] > 0.5
        if (m & near).sum() < 0.6 * m.sum():
            continue
        if m.sum() < big and shrink(m, 2).sum() > 0.25 * m.sum() and (m & inside).sum() < 0.6 * m.sum():
            continue  # a small blob off the headgear (a blush, a drop of blood): rivets and gems sit on it
        final.add(i)
        if alone[i][..., 3].max() > 0.95:
            solids |= m
    return final, solids, alone, (skin_i, ring_i)


def head_box(alpha):
    """Top, bottom and right (face side) of a head outline's opaque pixels."""
    ys, xs = np.nonzero(alpha > 0.5)
    return float(ys.min()), float(ys.max()), float(xs.max())


_base_box = None


def base_box():
    """The player's bare head on the 480 canvas (its ear is at the back, the left, so it's left out)."""
    global _base_box
    if _base_box is None:
        _base_box = head_box(np.asarray(Image.open(BASE_HEAD).convert("RGBA"))[..., 3] / 255.0)
    return _base_box


def cut(head, spec):
    look = LOOK * CANVAS / head.size  # px per point, telling objects apart
    scale = SUPER * CANVAS / head.size  # px per point, drawing the headgear
    keep, solids, alone, (skin_i, ring_i) = headgear_objects(head, spec, look)
    if not keep:
        raise ValueError("no headgear objects")
    a = head.render(keep, scale)
    # Shading and highlights only where the headgear itself is (not cast onto the face)
    solid_px = Image.fromarray(grow(solids, 1).astype(np.uint8) * 255).resize(a.shape[1::-1], Image.NEAREST)
    a[..., 3] *= grow(np.asarray(solid_px) > 127, SUPER)
    # Fit it to the player's head: the source's bare head (skin shape and outline) onto it
    ring = np.maximum(alone[skin_i][..., 3], alone[ring_i][..., 3])
    t, b, r = (v * scale / look for v in head_box(ring))
    bt, bb, br = base_box()
    s = (bb - bt) / (b - t)  # output px per render px
    ox, oy = br - r * s, bt - t * s
    im = Image.fromarray((a * 255).clip(0, 255).astype(np.uint8), "RGBA").convert("RGBa")
    # (premultiplied, so resampling doesn't drag colour in from transparent pixels)
    out = im.transform((CANVAS, CANVAS), Image.AFFINE, (1 / s, 0, -ox / s, 0, 1 / s, -oy / s), Image.BICUBIC)
    return out.convert("RGBA")


def fit(im, w, h):
    """`im` cropped to its picture and centred in a w x h canvas, as big as fits (with a margin)."""
    im = im.crop(im.getbbox())
    s = min((w * 0.9) / im.width, (h * 0.9) / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def object_sheet(heads, path):
    """The bigger objects of each (id, head), numbered, a row of them per head (to pick a spec's
    objects and skip)."""
    T, C = 96, 14
    rows = []
    for hid, head in heads:
        n = len(head.objects)
        full = head.render(set(range(n)), T / head.size)
        tiles = [("all " + hid, full)]
        for i in range(n):
            a = head.render({i}, T / head.size)
            if (a[..., 3] > 0.5).sum() > 0.003 * a[..., 3].size:
                tiles.append((str(i), a))
        rows.append(tiles)
    lines = sum((len(t) + C - 1) // C for t in rows)
    sheet = Image.new("RGB", (C * T, lines * (T + 12)), (70, 70, 80))
    d = ImageDraw.Draw(sheet)
    y = 0
    for tiles in rows:
        for k, (label, a) in enumerate(tiles):
            im = Image.fromarray((a * 255).astype(np.uint8), "RGBA")
            x = (k % C) * T
            yy = y + (k // C) * (T + 12)
            sheet.paste(im, (x, yy + 12), im)
            d.text((x + 2, yy), label, fill=(255, 255, 120))
        y += ((len(tiles) + C - 1) // C) * (T + 12)
        d.line([(0, y - 1), (C * T, y - 1)], fill=(200, 200, 80))
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--objects", action="store_true", help="write a sheet of the ids' source objects")
    ap.add_argument("--out", default=HERE, help="where --objects writes its sheet")
    ap.add_argument("--dest", default=ROOT, help="where the headgear goes (default the game's assets)")
    ap.add_argument("ids", nargs="*")
    args = ap.parse_args()
    if args.objects:
        path = os.path.join(args.out, "headgear_objects.png")
        object_sheet([(hid, open_head(args.src, HEADGEAR[hid]["source"])) for hid in args.ids], path)
        print("wrote", path)
        return
    ids = args.ids or list(HEADGEAR)
    os.makedirs(args.dest, exist_ok=True)
    catalog_path = os.path.join(args.dest, "catalog.json")
    catalog = json.load(open(catalog_path)) if os.path.exists(catalog_path) else {}
    with multiprocessing.Pool() as pool:
        done = pool.starmap(make, [(hid, args.src, args.dest) for hid in ids])
    failed = [(hid, err) for hid, err in done if err]
    for hid, err in done:
        if not err:
            spec = HEADGEAR[hid]
            catalog[hid] = {"name": spec["name"], "kind": spec["kind"], "hides_hair": spec["kind"] not in HAIR_SHOWS,
                            "source": spec["source"]}
    with open(catalog_path, "w") as f:
        json.dump(dict(sorted(catalog.items())), f, indent="\t")
    for hid, err in failed:
        print("FAILED %s: %s" % (hid, err))
    print("wrote %d headgear under %s" % (len(ids) - len(failed), os.path.abspath(args.dest)))


def make(hid, src, dest):
    """Cut one piece into dest/<hid>/; (hid, error text or "")."""
    try:
        im = cut(open_head(src, HEADGEAR[hid]["source"]), HEADGEAR[hid])
        d = os.path.join(dest, hid)
        os.makedirs(d, exist_ok=True)
        im.save(os.path.join(d, "Head.png"))
        fit(im, 2 * CELL, 2 * CELL).save(os.path.join(d, "icon.png"))
        return hid, ""
    except Exception:
        return hid, traceback.format_exc(limit=2).strip().splitlines()[-1]


if __name__ == "__main__":
    main()
