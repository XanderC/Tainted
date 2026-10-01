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
| `scripts/inventory_ui.gd` | Inventory screen: equipment, 24-slot bag, item compare, equip / unequip / drop |

### Inventory
Tap **Bag** (top right) or press **I**. The game pauses while it's open.
- Tap a bag item to inspect it. You get its stats, a green/red list of what changes if you equip it, and the item you're currently wearing in that slot.
- **Equip** swaps it in place (the old item takes its bag slot). **Drop** puts it on the ground; you can't re-pick it for 1.5s.
- Tap an equipped item to **Unequip** it (needs a free bag slot).
- Items for an empty slot are worn immediately. A full bag leaves loot on the ground.
- When you have real icons, set `icon` on an `ItemBase` and the bag shows the sprite instead of text.

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

Crafting happens in town (see below). The Blacksmith offers Orbs, Salvage and Recipes; the Merchant offers Buy and Sell.

- **Orbs** (Path of Exile style), used on any item in your bag or worn: Transmutation (Normal to Magic),
  Alteration (reroll Magic), Augmentation (add to Magic), Regal (Magic to Rare), Alchemy (Normal to Rare),
  Chaos (reroll Rare), Exalted (add to Rare, max 6), Divine (reroll values), Scouring (back to Normal).
  Orbs drop from monsters and bosses.
- **Salvage** (Diablo 3 style): break bag items into Iron Scrap (Normal), Arcane Dust (Magic) and
  Wraith Essence (Rare). Monsters drop materials too; Tainted Cores drop only from bosses.
- **Recipes**: craft with materials. Some are known from the start, some are found as recipe pages
  on monsters and bosses, some are bought from the Trader.
- **Merchant**: Buy recipes, orbs and materials with gold, or Sell bag items for gold.

Content is data: add orbs, materials and recipes in `crafting_db.gd`; orb rules live in `crafting.gd`.

**Saving:** gold, orbs, materials, recipes, bag and worn gear are saved to `user://tainted_save.json`
(on every change), so they carry between dungeon runs and app restarts. To wipe it, call
`GameState.reset_save()` or delete that file (on desktop: Godot's user data folder for "Tainted").


## Town: Ashfall Outpost (scenes/town.tscn, scripts/town.gd, town_map.gd)

The game starts here, and you return here after a dungeon (leaving, or dying). Walk up to an NPC
and tap the Talk button at the bottom (or press E):

- **Blacksmith** (west): orbs, salvage, recipes.
- **Merchant** (east): buy and sell.
- **Stash Keeper** (north): shared storage, 60 slots, saved with the account so every future character sees it.
- **Dungeon Gate** (east, by the pyramid): starts a dungeon instance.

You can't fight in town (`player.can_fight = false`). To add an NPC, add a `_add_npc(...)` line in `town.gd`
with a position, the gear it wears, and what it opens. To change the layout, edit `_layout()` in `town_map.gd`.
Crafting and stash screens are only reachable from these NPCs.
