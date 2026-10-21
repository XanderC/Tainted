# Tainted

Top-down mobile ARPG prototype (Godot 4.3+, GDScript, GL Compatibility renderer).

## Run it
1. Open Godot 4.3 or newer, click Import, pick `project.godot`.
2. Press F5. Move with the arrow keys or by click-dragging on the left side of the window.
   You auto-attack the nearest enemy. Kill things, pick up loot (walk over it), watch stats change.

## What's here
| File | Purpose |
|---|---|
| `scripts/stat_block.gd` | Flat / Increased / More stat maths (PoE style) |
| `scripts/affix_def.gd`, `item_base.gd`, `item_instance.gd` | Data model for items and rolled affixes |
| `scripts/loot_generator.gd` | Autoload: item + affix database, weighted drop rolls |
| `scripts/class_library.gd`, `class_def.gd`, `skill_def.gd` | Class definitions. The Warrior lives in `ClassLibrary.warrior()`; add classes the same way |
| `scripts/player.gd`, `enemy.gd` | Movement, skills, damage, armor, equip, stun |
| `scripts/skill_button.gd` | Right-thumb skill buttons with cooldown sweep |
| `scripts/item_tip.gd` | Item card tooltip for touch, with the worn item's card beside it to compare |

### Character creation
Create New Character lets you pick a class, then how the character looks, shown live on the figure:
gender, face, hairstyle (or bald) and hair colour, facial hair and its colour (men), skin tone and a
starter outfit, or 🎲 Random. Any hairstyle and beard go with any colour, and the eyebrows follow the
hair colour. The looks are saved with the character and shown on the select screen.
The art (`assets/appearance`) is cut from the CraftPix chibi packs by `tools/build_appearance.py`:
the packs draw hair and beards into each head, so the tool separates them from a bald base head and
turns them grey for tinting. Rerun it with the folder of zips to add styles (the tables at its top).

### Story: acts, zones and quests
Act 1 is being built (Diablo / Path of Exile style). Story zones are open areas (`scripts/zone.gd`,
listed in `scripts/act_db.gd`) built from map files, with every monster pack placed (they return
each visit), an area level, exits to other zones and town, a waypoint, NPCs, quest objects, story
triggers and quest bosses (who stay dead once their quest is past them). The 🌀 TOWN button opens a
town portal: back to Ashfall, and the portal there returns you to the same spot. Dying in a zone
sends you to its waypoint.

Quests (`scripts/quest_db.gd` for the content, `scripts/quests.gd` for the rules) have steps (talk,
reach a spot, enter a zone, touch a waypoint, kill monsters of a kind, kill a boss, use an object)
and rewards (experience, orbs, passive points, items). NPCs with quest business show a gold ! or ?
and talk first (`DialogueUI`); the tracker (top left) shows what to do next and opens the quest log
(also J). Progress is saved per character.
So far: **Into the Wastes** (main, Brom) and **The Lost Caravan** (side, Caravan Master Hesk, with
Vesh the Raider Captain), in **The Dune Wastes**, reached by the west road out of Ashfall.
Zone maps come from `tools/gen_zones.py`; tweak them in the map editor (rerunning the script
overwrites them).

### Monsters and townsfolk
Town NPCs and monsters are whole characters from the CraftPix chibi packs drawn on the game's rig
(`assets/skins`, copied by `tools/import_skins.py`; add a line to its table for more). Each pack of
monsters in a rift is one kind (`scripts/monster_kinds.gd`): zombies, rotting villagers, skeletons
and goblins from rift 1, then ghouls, mummies, orcs, orc shamans, gnolls, dark elves, draugr, fallen
crusaders, devils and ghost knights deeper in, each with its own speed, life and damage. Each rift's
boss is one of eight (a minotaur, a stone golem, an ogre, a lich, a death knight and three demons).
Archers (bandit archers and skeleton archers from rift 2, wild elf archers, outlaw rangers and
skeleton hunters deeper in) keep their distance, back away when you close in, and shoot when they
have a clear line through the maze; their arrows stop at walls. They are drawn on a second rig,
`assets/rigs/archer` (baked from an archer pack's `Animations.scml` with `tools/spriter_to_json.py`),
which any skin with a bow uses automatically; it shoots where the sword rig slashes, so archer
classes can reuse the same animation calls later.

### Weapons
59 weapon and shield bases in tiers (`LootGenerator.WEAPON_BASES`): one- and two-handed swords and
sabres, axes and maces, spears (two-handed, usable by the Warrior), daggers, staves, shields and
bows (for Desert Scout hirelings), each with a drop level so better bases appear in deeper rifts and
later zones. Their art, in the hand and in the bag, comes from the CraftPix weapon packs via
`tools/import_weapons.py` (base id -> pack design and grade); the packs have no bows, so the bows
are the archer skins' own (`tools/import_bows.py`).

Helmets come in 14 tiers, from a Linen Wrap to the Lich Crown (`LootGenerator.HELMET_BASES`), and
are the helmets the character packs draw on their heads, cut out by `tools/import_helmets.py` the way
hair is (everything on the head that isn't skin or outline, with its own outline, small gaps filled):
the worn art and the bag icon are the same helmet, and your own face shows under it (great helms
such as the Frost Great Helm and Death Visage cover it). Better ones need more Strength.

Body armour (13 tiers, Linen Robe to Death Knight Plate), gloves (6) and boots (7) are the character
packs' own clothes: a character's body and arms, hands and legs (`tools/import_armour.py`). They are
worn on your character exactly where its own parts are (gloves and boots show too), and the bag icon
is the piece as it sits in the idle pose (`tools/rig_pose.py`).

Flask icons are the CraftPix potion icons (`tools/import_potions.py`, pack folder on the NAS):
red bottles for life, orange for power, small to large as they get grander, and a grey, blue,
icy and yellow one for the Granite, Quicksilver, Silver and Sulphur flasks.

### Dyes
**Dyer Calla** in Ashfall (west of the plaza, between the Blacksmith and the Sage) dyes helmets, body
armour, gloves and boots: 30 dyes (`scripts/dye_db.gd`; the CraftPix paint icons, `tools/import_paints.py`), ten
colours in bright, deep and muted shades. Tap a piece of gear (worn, in your bag, or your hireling's),
tap a paint, see the character wearing it in the preview, and pay an Orb of Transmutation. Taking a dye
off is free. A dye recolours the art with a shader that keeps its shading and outlines (so chain mail
still looks like chain mail, and dark dyes stay dark), both worn and in the bag, and stays with the
item (`ItemInstance.dye`, saved) through crafting and trading to the stash. Only the gear you can see
worn: not weapons or jewellery.
- Tests: `godot --headless --path . res://scratch/test_dye.tscn`; `res://scratch/capture_dye.tscn`
  for screenshots (needs a window).

### Attributes and gear requirements
Diablo II style (`scripts/attributes.gd`): **Strength**, **Dexterity**, **Vitality** and **Energy**.
Your class gives a base in each (Warrior 25 / 15 / 20 / 10) and every level brings 5 points to add,
on the stats screen (📜 Stats in the inventory says how many are waiting). A point of Strength gives
+1% damage, Dexterity +0.5% attack speed and +0.1% critical chance, Vitality +4 life, Energy +1
maximum Adrenaline. Points can be taken back for free in town.
Gear needs enough of them, from its kind and drop level (`Attributes.requirements`): heavy weapons
and armour Strength, daggers and bows Dexterity, staves Energy; rings, amulets, belts, flasks and
light armour nothing. The item card lists the requirements, red where you fall short, and you can't
put it on until you have them. Gear that stops meeting them (points taken back) stays on, tinted
red, and gives nothing until it does again. Older characters get all their points to add.

### Hirelings
Diablo II's mercenaries (`scripts/hirelings.gd` the rules, `hireling_db.gd` the types,
`hireling.gd` the fighter, `hire_ui.gd` the Captain's window, `hireling_panel.gd` its inventory tab,
`hireling_portrait.gd` its HUD portrait).
**Captain Rourke** in Ashfall (east, by the Rift Gate) has fighters for hire, a few of each type,
near your level: you can have one at a time. It follows you, goes after enemies near you, and
enemies go for whichever of you is nearer. It levels with the experience you earn, never past your
level, and grows stronger: life and damage with each level, and 5 attribute points a level that
you add yourself (Strength, Dexterity, Vitality; its gear's requirements are judged by them).
- **Sellsword** (from the start): sword or axe or mace and a shield; Cleave, Frenzy or Sundering
  Strike, plus two of Shield Slam, Ground Stomp, Battle Cry, War Cry and Iron Skin.
- **Desert Scout** (after *Into the Wastes*): an archer who keeps her distance; Shot, plus two of
  Power Shot (pierces), Multishot and Arrow Rain. Holds the bow you give her.
- **Iron Warden** (after *The Lost Caravan*): two-handed weapons; Cleave, Sundering Strike or Double
  Swing, plus two of Whirlwind, Leap Slam, Earthquake, Demoralizing Taunt (pulls monsters onto
  itself) and War Cry.
Its skill gems are picked at random when it is offered and level with it; you can't change them,
but you link your own support gems to them (at the stash, like yours; links open with its level).
Its Battle Cry and War Cry reach you too. It has two flask slots of its own and drinks them itself,
so yours are left for you: a life flask when below half its life, a utility flask (Granite,
Quicksilver, Silver, Sulphur) as soon as it is fighting (power flasks don't go in: it has no
Adrenaline). Its portrait sits at the top left of the HUD with its life and flasks; tap it to open
its page (also the inventory's **Hireling** tab): its paperdoll laid out like yours, with its skills
where your bag is, fitting one screen. Drag gear and flasks from your bag onto its slots and back;
tap an item for its card, a tooltip that stays until you tap elsewhere. **📜 Stats** swaps to its
level, stats and attributes, where you add its points (taken back free in town). If it falls it stays down (its portrait goes grey) until the Captain revives it
for a few orbs, or you hire someone else: the old one's gear and flasks come back to your bag and its
supports to the stash. More types
open as the story goes on (add one to `HirelingDB.TYPES` with its `unlock` quest).
- Tests: `godot --headless --path . res://scratch/test_attributes.tscn` and `test_hirelings.tscn`;
  `res://scratch/capture_hirelings.tscn` for screenshots (needs a window).

### Inventory
Tap **Bag** (top right) or press **I**. The game pauses while it's open.
- Laid out like Path of Exile's: the equipment paperdoll on top, each slot shaped like what it holds
  (weapon and off hand 2x4, body 2x3, helmet, gloves and boots 2x2, belt 2x1, two rings and an
  amulet 1x1; a ring fits either ring slot; each Legendary or Set item can be worn only once, so
  two of the same unique ring, or the same unique one-hander in both hands, won't go on),
  the five flask slots in a row under the belt, and the 12 x 5 bag grid under that. The weapon-set switch
  (I / II) is in the header.
- The left window has the Skills, Gems and Hireling tabs; there is no item tab. Tap any item (in the bag, worn, in the stash or on the hireling) and its card pops up where you tapped. The card is a tooltip made for touch: it stays until you tap elsewhere, and a tap that closes it still goes through.
- Next to it is the card of what you wear in that slot (EQUIPPED; on the hireling's page, what it wears), with each stat marked green or red. Under the tapped card: 🔺 UPGRADE when it beats what you wear, and the list of what changes "Instead of your ...". Gear you can't use says why not. Unidentified items show the comparison without stat marks and have an **Identify** button (Scroll of Identify).
- Skill and support gems work the same way: tap one (on the Skills tab, at the stash or on the hireling's page) and its card pops up. It shows what the gem does, its level and experience, and the Gemcutter's Prism button. There is no gem info column.
- **Equip** by dragging it onto its equipment slot (the old item takes its bag space). **Drop** by
  dragging it onto the 🗑 Drop box under the boots, beside the flasks (from the bag, the paperdoll
  or a flask slot); it
  lands on the ground and you can't re-pick it for 1.5s. Item cards have no Equip or Drop buttons.
- Tap an equipped item and press **Unequip** on its card (needs a space in the bag its shape fits),
  or drag it back into the bag.
- Equipping is only ever done by dragging: picked-up loot (flasks too) always goes into the bag,
  even when its slot is empty, and an upgrade shows a popup saying so. Loot with no space its
  shape fits stays on the ground.
- When you have real icons, set `icon` on an `ItemBase` and the bag shows the sprite instead of text.

### Bag and stash grids
The bag (12 x 5 cells) and the shared stash (12 x 10) are Diablo / Path of Exile style grids: each
item covers a rectangle of cells, so what fits depends on shape as well as count.
- Sizes come from `ItemBase.bag_size()`: rings and amulets 1x1, dagger 1x2, one-handed swords,
  axes and maces 1x3, staff 1x4, bow and battle axe 2x3, greatsword and war maul 2x4, helmet,
  gloves, boots and wooden shield 2x2, body armour and tower shield 2x3. Set `grid_size` on a
  base to give it its own.
- Drag an item and the cells it would take light up green (fits) or red. Dropping onto exactly one
  other item swaps them, if that item fits back where yours came from; onto two or more is refused.
- `ItemGrid` holds the positions and does the fitting; `ItemGridView` draws one and handles drops.
  Saves store each item's cell. Older saves (a list of slots) are placed automatically, and
  anything that no longer fits goes to the stash, or waits under "Waiting for room" in the stash
  until there is space.
- Tests: `godot --headless --path . res://scratch/test_item_grid.tscn` (logic);
  `res://scratch/capture_item_grid.tscn` (screenshots, needs a window).

### Flasks and belts
Potions are gone; flasks replace them, Path of Exile style. A flask is an item (1x2 in the bag)
that is never used up: drink it from a flask slot and it goes on cooldown.
- **Belts** (new gear slot) open flask slots: Rope 2, Leather 3, Heavy 4, Chain 5; no belt, 1.
  Flasks in slots the belt doesn't open stay put but can't be drunk.
- **Kinds**: Life and Power flasks recover over their duration (Small / Medium / Large); Utility
  flasks give a timed buff: Granite (armour), Quicksilver (movement), Silver (attack speed),
  Sulphur (damage).
- **Modifiers**: Normal, Magic (one prefix + one suffix) and Rare (two of each). Prefixes change the
  flask (Ample: more recovered, Seething: instant, Chemist's: shorter cooldown, Enduring: longer,
  Potent: stronger buff); suffixes work while it is in effect (of Iron Skin, of Haste, of Fury,
  of the Berserker, of Warding: clears and blocks slows). Orbs work on flasks. No sockets.
- HUD: one button per open slot (`FlaskBar`), also Q E R T F. Flask slots stand in a column on the
  left of the bag, under the armour slots and the same size as every equipment slot; drag flasks
  between them and the bag.
- Flasks drop as loot (the boss always leaves one), and the Merchant sells Normal ones.
  Old saves: each potion type owned became a Normal flask, the slotted one equipped.
- Code: `ItemBase.flask` / `flask_slots`, `ItemInstance.flask_effect()`, `Player.use_flask()`,
  flask affixes in `LootGenerator` (`AffixDef.slots`, `prefix`, `word`).
- Test: `godot --headless --path . res://scratch/test_flasks.tscn`;
  `res://scratch/capture_flasks.tscn` for screenshots.

### Shared stash tabs: currency, gems
Orbs and shards, and loose skill, support and socket gems belong to the
account, not a character (`GameState.SHARED_KEYS`, saved in the account file). The stash shows them
in tabs: **Items** (the grid), **Currency** and **Gems**. The inventory keeps only
Equipment and Consumables.
- Gems are changed only at the stash (its Gems tab: skill slots and the tapped item's sockets
  beside the shared gems) or socketed at the Jeweler (`GameState.gem_station`). Elsewhere the
  Skills and Gems panels are view-only. Gem levels and what each character has socketed stay
  that character's.
- Currency is used only in the stash's Currency tab: tap an item (bag, worn or stashed), then tap
  an orb; or drag an orb onto worn gear. The item details and the Blacksmith no longer use orbs.
- A new account gets the starting pools once (`_starter_pools`), not each new character.
  Accounts from before this add every character's pools together the first time they load.
- The tutorial altar sockets the first gem straight into the main attack slot.
- Test: `godot --headless --path . res://scratch/test_shared_pools.tscn` (backs up and restores
  the account file); `res://scratch/capture_stash_tabs.tscn` for screenshots.

### Runes and runewords
Diablo II style. **Runes** (`SocketRune`, ids `srune_<name>`; the support gems already use
`rune_`) go into sockets like socket gems and share their pool and UI: socket them at the stash or
the Jeweler. Each rune gives one stat in a weapon and another in armour or jewellery.
- The ladder runs El to Zod (33 runes). Higher runes are stronger and rarer: a rift drops up to
  rank 8 at level 1 and two more ranks per level; every boss drops one (3 ranks better), and each
  monster killed has a small chance. The Jeweler combines 3 of a rune (2 from rank 21 up) into the
  next, for orbs.
- **Runewords** (`Runewords`): put exactly a runeword's runes, in order, into a **Normal** item of a
  kind it fits with **exactly** that many sockets, and it becomes that runeword (gold name): it
  rolls bonuses (passive keys like a Legendary's power, plus flat damage or armour) on top of the
  runes' own stats. Once formed it is **permanent**: its runes can't be taken out or swapped, and
  orbs can't alter it. Until then runes come out freely, and when an item's runes spell a runeword
  it can't become (not Normal, wrong socket count or kind) the Gems panel says why.
  Tapping a rune in the Gems panel lists the runewords it is part of.
- 28 runewords from 2 to 6 runes (Steel, Stealth, Spirit, Insight, Enigma, Grief, Infinity, Last
  Wish, Breath of the Dying...). Six-rune ones need a 6-socket two-handed weapon or body armour.
- **Sockets**: up to 6 on two-handed weapons (staves and bows too) and body armour, 4 on one-handed
  swords, axes, maces and shields, 3 on daggers and helmets, 2 on gloves and boots, 1 on rings and
  amulets (`ItemBase.max_sockets`). Each socket past the first is rarer on drop; Normal items drop
  with sockets often enough to be runeword bases, and the Jeweller's Orb rerolls up to the limit.
- Selling an item gives its loose runes back (socket gems are still lost); a runeword's runes are
  sold with it.
- Test: `godot --headless --path . res://scratch/test_runewords.tscn`.

### Warrior
Tanky melee: 160 life, 20 armor, life regen. **Cleave** auto-attacks in a wide arc. Skill buttons (or keys 1-3 on desktop):
1. **Whirl**: 360° spin for 180% damage, 4s cooldown
2. **Leap**: jump toward the nearest enemy, slam for 250% and stun for 1.2s, 7s cooldown
3. **Cry**: 6s buff, 25% more damage and +40 armor, 15s cooldown
| `scripts/virtual_joystick.gd` | Floating touch joystick |
| `scripts/loot_pickup.gd` | Ground items with rarity-coloured labels |
| `scripts/main.gd` | Arena, spawning, HUD |

Everything is drawn with shapes for now. Art goes in `assets/` (see `assets/README.md`).

## Android export (do this early)
1. Editor > Manage Export Templates > download for your version.
2. Install JDK 17 and Android Studio (for the SDK), then Editor Settings > Export > Android and set the SDK path and JDK path.
3. Project > Export > Add > Android. Enable Gradle build only if you need plugins; the plain APK export is simpler.
4. Plug in a phone with USB debugging and use the one-click deploy button.

## Next steps
1. Skill upgrades / passive tree for the Warrior
2. Inventory and equipment screen with drag/tap-to-equip
3. Procedural dungeon floors (TileMapLayer)
4. Save/load via `ResourceSaver` to `user://`
5. Replace placeholder shapes with Kenney / itch.io sprites

## Characters and gear art (zombie rig)

The player and the enemies use the CraftPix "Free Zombie Villager Chibi" Spriter rig,
rebuilt in Godot so that equipment shows on the body.

- `tools/spriter_to_json.py <Animations.scml> <out_dir>` bakes a Spriter rig into
  `rig.json` plus `parts/*.png` (already run for the zombie: `assets/rigs/zombie/`).
- `scripts/rig_sprite.gd` plays the baked animations (Idle, Walking, Running, Slashing,
  Hurt, Dying, ...) and layers gear on top of the body parts. `scripts/player.gd`
  calls `rig.set_gear(slot, item.base.id)` whenever you equip or unequip.
- Gear art lives at `assets/gear/<slot>/<base id>/`:
  - `weapon/<id>/Sword.png` replaces the sword. Its grip must sit at about (73, 59).
  - `helmet/<id>/Head.png` overlays the head.
  - `chest/<id>/Body.png`, `Right Arm.png`, `Left Arm.png` overlay the torso and arms.
  - `icon.png` is used in the bag and on the ground.
  Keep the same canvas size and alignment as the matching part in `assets/rigs/zombie/parts/`.
  If art is missing, weapons fall back to the rig's own sword and helmets/armour show nothing.
- `tools/make_gear_art.py` generates the placeholder gear art. To add an item, add a `_base(...)`
  line in `loot_generator.gd` with a new id and drop art in the matching folder.
- Gloves and boots are equippable but have no visuals yet; the layer table in `rig_sprite.gd`
  (`GEAR_LAYERS`) is where you would add them.
- The sprites are side-view, so characters flip left/right rather than turning up/down.

**Licence:** check the CraftPix licence (https://craftpix.net/file-licenses) before releasing.
Don't redistribute the raw art on its own.

**Android export:** add `*.json` to Export > Resources > "Filters to export non-resource files",
as a precaution for `rig.json`.

## Desert map (CraftPix 2D RPG Desert Tileset)

`scripts/desert_map.gd` builds the arena scenery from `assets/tiles/desert/`: a tiled sand
ground, a camp near the start, an oasis, a few buildings and a pyramid, and about 900
scattered palms, cacti and rocks (fixed seed, so the map is the same each run). Trunks and
big rocks block movement; grass and small rocks don't. Props are y-sorted with the
characters. Edit the `PROPS` table (scale, weight, blocker size) to tune it.

Not used yet: the road and plateau/cliff autotile pieces (`land_*`, `road_*`, `stones_10-12`).
They need a TileMap autotile setup, which is the next step for hand-built maps.
Licence: `assets/tiles/desert/LICENSE_craftpix.txt`; check craftpix.net/file-licenses.

## Dungeon instance (scripts/dungeon_run.gd)

1. Kill 30 monsters (progress bar at the top) and the trash is wiped and the boss, The Grave Warden, awakens.
   He is twice the size, can't be stunned, and telegraphs a ground slam every 5 seconds (step out of the red circle).
2. Kill the boss to clear the dungeon. Trash stops spawning and the rewards drop around the boss.
3. Clear it within 4:00 for bonus loot (the timer pauses while the bag is open):
   - Standard: 2 Magic items, plus a 25% chance of a Rare.
   - Under the limit: 1 guaranteed Rare, 2 more items that are 50% Rare / else Magic, and +3 item level.
4. Collect the loot, then tap "Leave dungeon" for a fresh instance.

All numbers (`KILL_TARGET`, `TIME_LIMIT`, `BOSS_HP`, reward chances) are constants at the top of `dungeon_run.gd`.

## Crafting (scripts/crafting_db.gd, crafting.gd, crafting_ui.gd, game_state.gd)

Crafting happens in town (see below). The Blacksmith forges Recipes and Plans; the Merchant buys and sells.
Orbs are used on items from the stash's Currency tab. There are no crafting materials and no
salvaging: orbs are the one currency, and recipes cost orbs.

- **Orbs** (Path of Exile style), used on any item in your bag or worn: Transmutation (Normal to Magic),
  Alteration (reroll Magic), Augmentation (add to Magic), Regal (Magic to Rare), Alchemy (Normal to Rare),
  Chaos (reroll Rare), Exalted (add to Rare, max 6), Divine (reroll values), Scouring (back to Normal).
  Orbs drop from monsters and bosses.
- **Recipes**: craft with orbs (Transmutation for the basic forges, up to Chaos for Tainted and
  Exalted crafts, Legendary and Set plans). Some are known from the start, some are found as recipe pages
  on monsters and bosses, some are bought from the Trader.
- **Merchant**: Buy recipes and orbs, or Sell bag items for orbs.

Content is data: add orbs and recipes in `crafting_db.gd`; orb rules live in `crafting.gd`.

**Saving:** orbs, recipes, bag and worn gear are saved to `user://tainted_save.json`
(on every change), so they carry between dungeon runs and app restarts. To wipe it, call
`GameState.reset_save()` or delete that file (on desktop: Godot's user data folder for "Tainted").


### Identifying
Magic, Rare, Legendary and Set gear from rift loot drops unidentified (`ItemInstance.identified`):
it shows only its base name, its modifiers are hidden, and it can't be worn or crafted on.
A **Scroll of Identify** (a currency in the stash, dropped by monsters and bosses, sold by the
Merchant) identifies one item, anywhere, from the item's details. The **Sage** in town identifies
everything in your bag and stash at once, free. Flasks and Normal items are always identified.

## Town: Ashfall Outpost (scenes/town.tscn, scripts/town.gd, town_map.gd)

The game starts here, and you return here after a dungeon (leaving, or dying). Walk up to an NPC
and tap the Talk button at the bottom (or press E):

- **Blacksmith** (west): recipes and plans.
- **Merchant** (east): buy and sell.
- **Sage** (south-west): identifies every item in your bag and stash, free.
- **Stash Keeper** (north): shared storage, 60 slots, saved with the account so every future character sees it.
- **Dungeon Gate** (east, by the pyramid): starts a dungeon instance.

You can't fight in town (`player.can_fight = false`). To add an NPC, add a `_add_npc(...)` line in `town.gd`
with a position, the gear it wears, and what it opens. To change the layout, edit `_layout()` in `town_map.gd`.
Crafting and stash screens are only reachable from these NPCs.
