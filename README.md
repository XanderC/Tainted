# Tainted

Top-down mobile ARPG prototype (Godot 4.3+, GDScript, GL Compatibility renderer).

## Run it
1. Open Godot 4.3 or newer, click Import, pick `project.godot`.
2. Press F5. The game is **online only**: sign in with your Xandflix account (Autharr) and it joins
   the Tainted World (on the home network for now; see Multiplayer), which keeps your characters.
   Move with the arrow keys or by click-dragging on the left side of the window.

Or without the editor: `Godot_v4.4.1-stable_win64.exe --path <this folder>` (add `--resolution 1600x720`
for the phone's shape).

**Builds** (`export_presets.cfg` is not in git: it holds the Android signing setup):
- Windows: `.\build_windows.ps1` makes `builds\windows\Tainted.exe`, one standalone file you can copy
  anywhere and run (`-Run` starts it). Uses the "Windows Desktop" preset (x86_64, game packed in the exe).
- Android: `.\deploy_android.ps1` builds the APK and installs it on the phone over wireless debugging.
  The APK holds the game as **one pack** (`pack/game.mp4`, exported first with the "Android Data"
  preset), plus only `updater.gd`, `build.json` and the project font: the "Android" preset exports
  just those. Updater loads the pack at startup. Don't put the game in the APK as loose files again:
  the first pack Godot loads at runtime (the game pack, a patch) makes it list every file of the APK
  one at a time through Android's asset manager, which took a phone 90 seconds with the game's
  ~9,500 files. (`.mp4` because the exporter leaves that extension uncompressed, so the pack can be
  read from anywhere in it at once.)
- For players: `.\publish_builds.ps1` is a **full release**: it builds both, puts them on the NAS
  (Tainted > builds, where the server's "update your game" message sends players) and keeps each
  platform's pack in `builds\base` as the base later updates are made against. Deploy the server
  after it (`.\deploy_server.ps1`).
- **Updates** (`.\publish_update.ps1`): players don't reinstall. It stamps a new build number
  (`build.json`), exports a patch per platform of just the files changed since the last full release
  (Godot's `--export-patch`), and deploys the server with them. A game connecting to an older build's
  server asks first (`scripts/updater.gd`, over raw packets rather than RPCs, so it works whatever an
  update changed), downloads the patch in chunks, checks its SHA-256, saves it in `user://update` and
  restarts (a phone reopens itself in a new process, or asks the player to); from then on the patch loads at startup,
  before any other script. An update can change any script, scene or art, new `class_name`s
  included, but not the engine, export settings (icons, permissions), project settings or the
  autoload list: those need a full release, which players install once. Test: start a local server
  with `--update-dir=<folder>` and run `scratch/update_client.tscn -- --update-test`.

## What's here
| File | Purpose |
|---|---|
| `scripts/stat_block.gd` | Flat / Increased / More stat maths (PoE style) |
| `scripts/affix_def.gd`, `item_base.gd`, `item_instance.gd` | Data model for items and rolled affixes |
| `scripts/loot_generator.gd` | Autoload: item + affix database, weighted drop rolls |
| `scripts/class_library.gd`, `class_def.gd`, `skill_def.gd` | The Adventurer everyone starts as (there are no classes: `ClassLibrary.adventurer()`), and skill definitions |
| `scripts/player.gd`, `enemy.gd` | Movement, skills, damage, armor, equip, stun |
| `scripts/skill_button.gd` | Right-thumb skill buttons with cooldown sweep |
| `scripts/item_tip.gd` | Item card tooltip for touch, with the worn item's card beside it to compare |

### Character creation
Create New Character lets you pick how the character looks (there are no classes: everyone starts the
same, see **Builds without classes**), shown live on the figure:
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
triggers and quest bosses (who stay dead once their quest is past them). Dying in a zone sends you to
its waypoint.

### Town portal scrolls
Reading a **Scroll of Town Portal** (the 🌀 button at the top of the screen, or G) in a zone or a
rift opens a portal where you stand (`scripts/town_portals.gd`). Tap its label to go to Ashfall; a
portal back stands by the town square, and going through it you come out where you read the
scroll, with what you left on the ground still lying there. Your own portal closes once you go back
through it. You have one portal open at a time: reading another closes the first. A character starts
with 3 and carries up to 40. The Merchant sells them (an Orb of Transmutation each), zone monsters
sometimes drop them (elites more often), and bosses always leave some.
Going back into a **rift** carries it on: the same maze, monsters (as hurt as they were), kills and
clock (it doesn't run while you're in town). A solo rift is saved going through its portal. A rift's
portals close when it moves on to its next maze, and a solo rift's when you leave it another way
(falling, or the cleared rift's way home).

Quests (`scripts/quest_db.gd` for the content, `scripts/quests.gd` for the rules) have steps (talk,
reach a spot, enter a zone, touch a waypoint, kill monsters of a kind, kill a boss, use an object)
and rewards (experience, orbs, passive points, items). NPCs with quest business show a gold ! or ?
and talk first (`DialogueUI`); the tracker (top left) shows what to do next and opens the quest log
(also J). Progress is saved per character.
So far: **Into the Ashwood** (main, Brom) and **The Lost Caravan** (side, Caravan Master Hesk, with
Vesh the Raider Captain), in **The Ashwood**, autumn woods reached by the west road out of Ashfall.
Act 1 is woodland (the tutorial, Ashfall and the Ashwood: see **Map themes and walls**). The zone's
id is still `dune_wastes` from when it was a desert, so saved waypoints and quests keep working.
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
bows (for Woodland Scout hirelings), each with a drop level so better bases appear in deeper rifts and
later zones. Their art, in the hand and in the bag, comes from the CraftPix weapon packs via
`tools/import_weapons.py` (base id -> pack design and grade); the packs have no bows, so the bows
are the archer skins' own (`tools/import_bows.py`).

Helmets come in 14 tiers, from a Linen Wrap to the Lich Crown (`LootGenerator.HELMET_BASES`). They
come from a library of about 150 pieces of headgear (helmets, great helms, hoods, hats, crowns,
circlets, headbands, turbans, wraps and masks) that `tools/import_headgear.py` cuts out of the
character packs' vector sources (the `.ai` files on the NAS, Tainted > assets > sprites): each head
is drawn as separate shapes, so a helmet is exactly its own shapes, outlines and shading, with
nothing cropped, fitted to the player's bare head. They are all in `assets/gear/helmet/<id>/`
(worn `Head.png` and bag `icon.png`), listed with their name and kind in
`assets/gear/helmet/catalog.json`, ready for new items: give one a `HELMET_BASES` line with its id.
The worn art and the bag icon are the same piece, and your own face shows under it (great helms
and masks cover it). Crowns, circlets, headbands and masks leave your hair showing; the rest hide
it. Better ones need more Strength.

Body armour (13 tiers, Linen Robe to Death Knight Plate), gloves (6) and boots (7) are the character
packs' own clothes: a character's body and arms, hands and legs. They are worn on your character
exactly where its own parts are (gloves and boots show too), and the bag icon is the piece as it sits
in the idle pose (`tools/rig_pose.py`). `tools/import_armour.py` takes them from every character in
the packs on the NAS (Tainted > assets > sprites), leaving out bare skin and bones (a part mostly its
character's skin colour) and creature bodies, and keeping each piece once: a library of 183 suits of
armour, 45 pairs of gloves and 147 pairs of boots in `assets/gear/<slot>/<id>/`, listed in
`assets/gear/<slot>/catalog.json`, ready for new items (a line in `CHEST_BASES`, `GLOVE_BASES` or
`BOOT_BASES` with the id).

**Wrists** (bracers) and **Legs** (shorts, kilts, guards) are slots like Diablo 3's: 8 tiers each
(`LootGenerator.WRIST_BASES`, `LEG_BASES`), in the bag as 2 x 2, with 1 and 2 sockets. They are armour like gloves
and boots (Strength to wear the better ones) but are not drawn on the character, so a piece is just
its bag icon, cut from the concept sheets by `tools/import_wrist_legs.py`. They sit under the shoulders
and the amulet on the paperdoll, level with the gloves and boots. Test: `scratch/test_wrist_legs.gd`.

**Shoulders** are their own slot (beside the helmet on the paperdoll): 12 tiers, Strapped Pauldrons
to Void Spaulders (`LootGenerator.SHOULDER_BASES`), worn over the top of both arms on every rig. A
shoulder piece is pinned to each shoulder at its own size and follows the arm only a little
(`RigSprite.SHOULDER_ART`), so it stays put when an arm stretches to a weapon. They can be dyed and
restyled like other armour. **Hand crossbows** are one-handed crossbows (6 tiers, Hand Crossbow to
Jade Hand Crossbow): they shoot with bow skills, leave the off hand free for a shield or another
weapon, need Dexterity, and are held on their own rig (`assets/rigs/handxbow`, made by
`tools/make_weapon_rigs.py`: aimed forward in one hand, raised and loosed). Scouts can't use them.
Both come from the concept sheets in `tools/art/`, cut out by `tools/import_new_gear.py`.

Flask icons are the CraftPix potion icons (`tools/import_potions.py`, pack folder on the NAS):
red bottles for life, orange for power, small to large as they get grander, and a grey, blue,
icy and yellow one for the Granite, Quicksilver, Silver and Sulphur flasks.

### UI art
Windows, panels, buttons, tabs, tooltips, slots and the HUD are the CraftPix RPG & MMO user interface
pack (`craftpix-net-745192`, on the NAS under `/Tainted/assets/guis`). `tools/import_mmo_ui.py <zip>`
builds them:
- `assets/ui/mmo`: dark charcoal windows with a thin gold edge, the title band (blue scrollwork in its
  corners, a gold rule beneath), the bevel button plate (greyscale, tinted per button), the open-tab glow,
  the tooltip frame, slots, the square close button and the equipment slot silhouettes. `UIKit`
  (`mmo()`, `window_box`, `stone_box`, `tab_box`, `tooltip_box`, `inset_box`) is the one place they are used.
- `assets/ui/hud`: the action bar laid out as the pack's (`HudBars`, `FlaskBar`): the life and power globes
  (red; the right one split, Adrenaline orange on its left and Mana blue on its right) on the bottom edge, the square flask slots between
  them with their keys, the experience line along the top of the row with a tag over its end, and the
  curls at the globes' feet. Also the round skill buttons, the joystick, and `HudArt.HOLES`, where each
  round frame's opening is (the HUD places them by their opening).

The scrollbars are still the old stone art: the pack has none. Its fonts (Constantia, Cambria, Palatino)
are Microsoft's and can't be shipped in the game, so the game uses two free ones in the same spirit, from
Google Fonts (SIL Open Font License, licences beside them in `assets/fonts`):
- **Lora** for all text: the project font (`assets/fonts/body.tres`, Lora Medium, set as
  `gui/theme/custom_font`), and `ThemeDB.fallback_font` for text the HUD and the world draw themselves.
  Its digits are lining, so stats line up.
- **Cinzel** (Roman capitals) for window titles, tabs and the game's title (`UIKit.title_font()`). Its "1"
  looks like an "I", so it isn't used for text with numbers.
Neither has the ▲ / ▼ stat arrows, so those come from the system font (`UIKit.ARROW_FONT`).

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

**Lucky Mott, the Gambler** (by the Captain, east of the plaza; `scripts/gambler.gd`,
`scripts/gamble_panel.gd`) sells 18 pieces of random gear, all unidentified, Diablo II style: about
70% Magic, 25% Rare, 3% Legendary and 2% Set, rolled for your level from every kind of gear (weapons,
shields, armour, shoulders, jewellery, belts; no flasks). On the stall every piece shows as a plain one
of its base, with no rarity colour or sockets, so you only find out what you bought once you identify
it. Prices go by item level (2 then 5 Alterations, 1 Alchemy, then 1 Chaos; jewellery double). The
stall is new every 20 minutes, or as soon as it's sold out, and is saved with the character.
- Test: `godot --headless --path . res://scratch/test_gambler.tscn`

**Appearances** (transmog, the Dyer's second tab): every helmet, body armour, gloves, boots, weapon and
shield you pick up, buy or wear unlocks its look for all your characters (`GameState.wardrobe`, saved in the account,
`scripts/wardrobe.gd`), with a "New look" message over your head. At the Dyer, tap a piece of gear,
then any unlocked look of its kind, and **Change look** (free): the piece looks like that, worn, on
your hireling and to other players, but keeps its own stats; **Its own look** puts it back. The look
stays with the item (`ItemInstance.look`, saved) like a dye, and the two go together. A look is a piece
of the gear library (`assets/gear/<folder>/catalog.json`). Looks keep to their group: each armour
slot; melee weapons (any melee weapon can look like any other: the rig holds them alike); bows and
crossbows (drawn on the archer rig); shields. The weapon library (`tools/import_weapon_library.py`) is
every design in the CraftPix weapon packs on the NAS (Tainted > assets > weapons: 8 designs in 5 grades
of swords, sabres, axes, maces, daggers, spears, staves and shields) and every weapon and bow the
characters in the character packs hold: about 500 melee weapons, 30 bows and 43 shields. Every
Legendary and Set item but jewellery has its own look, `u_<id>` (`UniqueItems.look_of`): a library
piece (for a weapon, a design of its own kind it doesn't otherwise have) recoloured by
`tools/make_unique_looks.py`, a set's pieces in one colour (embers for the Ashen Warlord, wine for
the Bloodsworn, teal for the Windrunner, violet for the Archmage, gold for the Templar), unlocked once
the item is identified.
- Tests: `godot --headless --path . res://scratch/test_wardrobe.tscn` (`-- --shot=<png>` with a
  window for a picture of the tab)
  for screenshots (needs a window).

### Attributes and gear requirements
Diablo II style (`scripts/attributes.gd`): **Strength**, **Dexterity**, **Vitality** and **Energy**.
Everyone starts with 15 in each and every level brings 5 points to add, on the stats screen (📜 Stats
in the inventory says how many are waiting); the passive tree, Legendary powers and gear give more
(gear's own attributes count for gems and damage, but not towards other gear's requirements). A
point of Strength gives +1% damage to red (Strength) attacks, Dexterity +1% to green (Dexterity)
attacks, +0.5% attack speed and +0.1% critical chance, Vitality +4 life and a little regeneration,
Energy +1% spell damage and +2 maximum Mana, Vitality +4 life, +0.05 life a second, +1 armour and
+0.2% to all resistances. Points can be taken back for free in town.

### Resistances
Monsters can hit with an element: Orc Shamans lightning, Devils fire, Ghost Knights and Skeleton
Hunters cold, Mummies and Dark Elves poison (chaos), several bosses too, and the elite affixes
(burning ground and death blasts fire, frost orbs cold, sparks lightning). Armour takes part of any
hit off; your resistance to its element part of an elemental one (`Player.resistance`, at most 75%,
shown on the stats screen). Resistances come from Vitality, gear (each element, and all
resistances), the Vitality side of the passive tree and Legendaries (Aegis of the Elements,
Stoneblood Girdle). In a party the host's monsters' hits reach you by element, so your own
resistances apply.
Gear needs enough of them, from its kind and drop level (`Attributes.requirements`): heavy weapons
and armour Strength, daggers and bows Dexterity, staves Energy; rings, amulets, belts, flasks and
light armour nothing. The item card lists the requirements, red where you fall short, and you can't
put it on until you have them. Gear that stops meeting them (points taken back) stays on, tinted
red, and gives nothing until it does again. Older characters get all their points to add.

### Multiplayer
The game is **online only**: there is no single player and no hosting your own game. Everyone online
meets in Ashfall Outpost; parties of up to 4 play zones and rifts together, each with their own loot.
The **Tainted World** is the server, on the main host (192.168.86.18) in Docker beside the estate. It's
on the home network only for now, and set up so it can be opened to the internet later. What's done
and what's left: MULTIPLAYER.md.

**How it fits together.** `Net` (autoload, `scripts/net.gd`) is the server or a client. They talk
over WebSockets on port 24601: `ws://` on the LAN, and `wss://` through a TLS proxy for the public
(Traefik behind the Cloudflare Tunnel, which carries WebSockets, so no port is forwarded). Each game
runs its own town; the server passes on who is where (`Net.enter(instance)`, states about 15 times
a second) and keeps everyone's characters (Online characters, below). It takes nothing on trust: a
connection must say hello within 10 s, messages are rate-limited, states and looks are cleaned of
anything unexpected, and only plain values are decoded.

**Playing.** The start screen (`CharacterSelect`) signs in (a kept sign-in does it by itself; else email
and password) and joins the Tainted World, trying the addresses in the project setting
`tainted/net/world_addresses` in order (now `ws://192.168.86.18:24601`). Then it shows your online
characters: create, play and delete them there, and Sign out for another account.
- If it can't reach the server, or the server refuses (an old game, banned...), it says so: **Try again**.
- A game that loses the server tries to reconnect for about a minute and a half (a server restart comes
  back by itself), then goes back to the start screen, which says why (`Net._back_to_start`).
- Characters a device saved before the game went online only are left on the device, unused
  (`GameState.forget_account`: the game never plays from the device's saves).

In town (`NetPresence`) everyone else there is a `RemotePlayer`, shown with their looks, gear, dyes,
name and level, walking where they walk. Going back to character select keeps you online.

**Parties** (up to 4; `Net` keeps them on the server, `PartyUI` shows them):
- Walk up to another player in town and tap the Talk button (it shows their name) for their card,
  then **Invite to party**. They get a Join / No thanks pop-up, which lapses after a minute.
- The inviter leads the party. Only the leader invites, removes members or hands over the lead
  (👑 on the cards); anyone can **Leave**. A party of one disbands.
- The party list, top right under the menu buttons, shows each other member's name, level, life
  and whereabouts (town, zone, rift), wherever you each are. Tap a row for their card.
- Notices along the top: who joined, left or now leads. Leaving the game takes you out of your party.

**Party rifts and zones** (`Coop`, with `Enemy.remote` and `DungeonRun.remote`):
- Entering a rift at the Rift Gate while in a party opens it for the party (`Net.open_party_rift`). You
  go in, and the others get "Brom opened a Rift (level 3)" with **Join** / Not now. While it's open
  the party list has a Join button too, for latecomers. Only that party can enter it.
- The first member in **hosts** it: their game runs the mazes, monsters and run as a solo rift does,
  and sends the others what happens (maze, spawns, positions and life about 12 times a second,
  deaths, the run's kills, time and stage, archers' arrows).
- The others' games show **copies** of those monsters. Every hit their player or hireling lands goes
  to the host's game, which applies it. The host's monsters go for every player (the nearest), and
  what hits another player is sent to their game, which takes it with their own armour.
- Stepping into the portal asks the host to take everyone through. Monsters have +60% life per extra
  player.
- **Rewards:** each game gives its own XP for every death, and when the boss dies each player's game
  rolls **their own loot** (and orbs, gems, runes), so nobody can take anyone else's.
- **Handover:** if the host leaves, the next player takes over; their copies become the real monsters
  and the run carries on.
- **Story zones** work the same way, without asking. A party member entering a zone joins the party's
  copy of it (`zone:<party>:<zone>`), and the first in hosts it. A copy's death does what a monster's
  death does in each game: XP, quest kill credit and a quest boss's kill, and **loot rolled in that
  game**, so each player gets their own drops. Exits and waypoints take each player on their own;
  dying sends you back into the party's zone.
- **Town portals** are the party's: everyone sees each member's portal, in the rift or zone and by
  the town square, and can use it both ways (only its owner going back closes it). The server keeps
  them with the party, and refuses one that isn't in the party's own zone or rift. When the last
  player leaves a party rift while a portal still leads into it, their game sends the rift as it is
  to the server, which keeps it (and the party's way in) for whoever goes in next. That player
  carries it on as host. If nobody has a portal into it, an empty party rift closes as before.
- Shared too: players' skill effects (swings, rings, whirlwind, earthquake ground, standards), hirelings
  and summoned Ancients (each fights in its owner's game), and elite affixes hit every player in reach.
- Falling in a party's rift or zone: you stay down, and a member standing beside you for 3 s revives you
  at half life; after 20 s you may get up at the start (`PartyDeath`). A party rift fails only when
  everyone is down. A party rift is the opener's level at most; a clear in time unlocks each member's
  next. Off-screen members get an arrow at the edge, and a member's card has **Go to them**.

**Chat** (`ChatUI`, `Net.say`):
- The 💬 button at the bottom left (or Enter) opens a box; **Local** reaches everyone where you are (your
  copy of the town, your rift or zone), **Party** your party.
- Recent lines show above the button and fade after 12 s. The server cleans each line: printable text,
  at most 200 characters, one every 0.6 s, and a word filter (`Net.CHAT_FILTER`) that stars whole words.
- While you type, the game ignores its keys, and the movement stick leaves the button alone (the
  `touch_exempt` group).

**Inspect** (`InspectUI`): a player's card has 🔍 **Inspect**. The server asks their game for its worn gear
and stats (only for players in the same place or party) and shows them by slot; tapping a piece shows its
card beside what you wear there.

**Friends** (on a server that keeps characters): a player's card has ★ **Add friend**; once they
accept, each account keeps the other, on the server where a game can't edit it (`AccountStore.social`).
**★ Friends n/m**, at the top of the party list, shows them online first, with where they are, **Invite**
to party and Remove. Friends can inspect each other from anywhere.

**Trading** (on a server that keeps characters, `TradeUI`):
- A player's card has 🤝 **Trade**. Once they accept, each picks up to 10 items from their bag, and both
  press **Ready** (any change makes both look again).
- The server checks each offer against the bag it has saved, then swaps them **in the saves**: out of
  each giver's bag, into each receiver's stash. Both games are told, and what you get is in your stash.
- Every item has an id (`ItemInstance.uid`; a Mirror copy gets its own). The server keeps a giver's
  traded-away ids and strips them from that account's later saves, so a game can't keep what it traded.

**Online characters** (`AccountStore`, `GameState.use_online_files`):
- The Tainted World keeps its players' characters. Each account is one JSON file under
  `/appdata/estate/tainted/accounts` on the host, written a moment after a change, with a copy of every
  account each day in `backups/<date>` (the last 7 days). Started with `--data=<dir>`, a server keeps
  characters; its welcome says so (`Net.accounts`).
- The game saves its account and character "files" to the server, never the device
  (`GameState._write_json` by virtual path: `account`, `characters/<id>`). Only tests and the map
  editor's test runs, which never sign in, use the device's files.
- **The server checks every file** before storing it: only those two kinds of path, plain data under
  512 KB, and a sane shape (character list, level 1-100, items). Saves made while reconnecting go once
  the connection is back. One game per account: playing it elsewhere replaces the first.
- **Who an account is:** an **Autharr sign-in** when the server asks for one, else a random key kept on
  the device (`user://device_key.txt`). Tests use their own key (`Net.test_key`).

**Signing in** (Autharr; `Net.sign_in`):
- The online screen's Tainted World entry has Email / Password / **Sign in** (your estate account), then
  "Signed in as ..." with Sign out.
- The game uses Autharr's password grant for the `tainted-game` client (project setting
  `tainted/net/auth_url`, now `http://192.168.86.18:5180`), and keeps the refresh token encrypted with
  the device's key (`user://autharr.dat`), so the next start signs in by itself.
- A server started with `--auth=<Autharr URL>` (the container's `TAINTED_AUTH`) turns away anyone not
  signed in, checks each sign-in against Autharr's `/connect/userinfo`, and keys the account by the
  Autharr user (`a<id>`). Disabling an account in Autharr keeps that player out.
- Autharr has the `tainted-game` client (registered by Autharr itself, `EnsureTaintedAsync`), and the
  Tainted World requires signing in (`TAINTED_AUTH=http://autharr:5180`, over the `arr` network).
- **What it does and doesn't stop.** Players can't edit their characters, since the saves are the
  server's, and trades will be done by the server. A modified game can still cheat, because each game
  rolls its own loot (stopping that means running the game itself on the server).

**Staying connected:**
- A dropped connection reconnects by itself: a try every 4 s for about 40 s, and at once when the app
  comes back to the front on Android. You go back into the town, zone or rift you were in. The line at
  the top says "Reconnecting..." meanwhile.
- The server keeps a dropped party member's place for a minute, shown greyed as "Reconnecting...", and
  their game's session token puts them back in. A rift they hosted passes on at once. A guest who comes
  back takes the host's fight as it is now; a player who comes back to an empty rift runs it themselves.
- A busy town is split into copies of 20 (`Net.TOWN_CAP`, a dedicated server's `--town-cap`), and
  party members are put in the same copy.
- Leaving the game (back to character select) also counts as a drop, so your party place is kept
  for that minute.

**The server.** `.\deploy_server.ps1` deploys it:
1. It exports the game as a pack (`builds\server\tainted.pck`, with a "Linux Server" export preset it
   adds the first time).
2. It copies the pack and the `server\` files (Dockerfile, compose file, start and admin scripts, the
   NAS backup and its timer) to `/opt/projects/Tainted/server` on the host.
3. It rebuilds the `tainted` container (the old one warns its players and saves first), waits until
   it's healthy, and installs the daily backup timer.

The container is Godot's official Linux build (checksum pinned), headless, as an unprivileged user,
capped at 512 MB and one CPU. It's on the `arr` network, and port 24601 is published on the host
(LAN only: the router forwards just 80 and 443). Players sign in with Autharr (`TAINTED_AUTH`).

Clients and the server must be the same build (`Net.PROTOCOL`), so **redeploy the server whenever
the game changes**, and bump `PROTOCOL` when the messages change. A game too old to join is told to
update and where (`TAINTED_UPDATE`: the NAS's Tainted > builds, which `.\publish_builds.ps1` fills
with `Tainted.exe`, `Tainted.apk` and `version.txt`). A local server instead: `.\run_server.ps1` or
`godot --headless --path . -- --server --name=Home --max=32`.

**TestBot**, to try multiplayer on your own: a player always on the Tainted World (the `tainted-bot`
container, `scripts/bots/test_bot.gd`). Walk up to it in Ashfall, or whisper it `help`: it answers
`invite`, `trade`, `friend`, `follow`, `stay`, `rift`, `die` (in a rift: then revive it), `leave` and
`say <text>`; it accepts invites, trades and friend requests, follows its party into rifts and zones and
fights there. It comes in with the server's bot key (`TAINTED_BOT_KEY` in the host's `.env`, made by
the deploy) instead of a sign-in. `scratch/buddy_bot.tscn` checks it against a local server.

**Running it** (on the host):
- `docker exec tainted tainted-admin status`: who is online, where, in which party; the server's state.
- `kick <player> [reason]`, `ban <player> [reason]` / `unban` / `bans`, `mute <player> [minutes]` /
  `unmute` / `mutes`, `say <text>` (a line to everyone), `save`, `shutdown [seconds]`; `help` lists
  them. A player is their name while online, or their account (`a...`, as `status` shows). Bans and
  mutes are by account, kept in `/appdata/estate/tainted/moderation.json` (ServerAdmin, Moderation).
- `docker stop tainted` (and a redeploy) tells everyone it restarts in `TAINTED_STOP_WARNING` (10)
  seconds, writes every account and stops; their games reconnect when it's back.
- Logs: `docker logs -f tainted`, a dated line for each join, leave and refused join (version, full,
  sign-in, banned), party (joins, leaves, disbands, rifts opened), trade, refused save, admin command.
- Backups: the server copies every account daily to `/appdata/estate/tainted/backups` (7 days), and
  `tainted-backup.timer` packs them onto the NAS every night at 04:30
  (`/storage/Tainted/server-backups/tainted-<date>.tar.gz`, 30 days; `server/backup.sh`).

**Opening it to the world (not done yet):** see MULTIPLAYER.md, section 4.
1. Traefik, in `estate/traefik/dynamic.yml`: a router `tainted-public` with entry point
   `[websecure]`, rule ``Host(`tainted.xandflix.uk`)``, middlewares
   `[proxied, public-headers, public-ratelimit]` and the `cloudflare` cert resolver, like
   `retroflix-public`. Its service is `tainted`, load-balancing `http://tainted:24601`.
2. Cloudflare: a public hostname `tainted.xandflix.uk` on the tunnel, and that name added to the
   hostname allowlist rule (`estate/docs/cloudflare-rules.md`).
3. The game: `wss://tainted.xandflix.uk` added to `tainted/net/world_addresses` after the LAN
   address (home games still go direct), then a new build for players and a server redeploy.

What's done and what's left: MULTIPLAYER.md.

Test without a second device: `scratch/net_bot.tscn` (`-- --bot=walker`, `--bot=watcher` checks what
it sees, `--bot=partier` checks parties, `--drop-at=8` and `--bot=keeper` check reconnecting,
`--bot=counter` with a server's `--town-cap=2` checks town copies, `--say=` / `--party-say=` with
`--expect-chat=` / `--no-chat=` check chat, `--bot=inspector` checks inspecting, `--key=` with `--befriend` / `--accept-friend` /
`--expect-friend=` check friends, `--accept` / `--invite`, `--addr=ws://...`) and `scratch/capture_net.tscn` (a screenshot of the town
online; `--world`, `--host`, `--party` for an invite, the party list and a card, `--chat`, `--inspect`), and
`scratch/account_bot.tscn` checks online characters against a server with `--data`
(`--phase=create`, restart it, `--phase=check`; `--addr=ws://...`), `scratch/signin_bot.tscn` checks signing in
against an Autharr (`--auth= --email= --password=`, `--phase=first` then `--phase=again`), `scratch/trade_bot.tscn`
checks a trade and the anti-duplication (`--role=a` and `--role=b`, `--shot`), `scratch/admin_bot.tscn` checks the
admin commands against a server with `--data= --admin=`, `scratch/lost_bot.tscn` checks a game that loses
the server goes back to the start screen (kill the server once it's in town), and `scratch/coop_bot.tscn` plays a whole party rift with
two bots (`--role=leader|follower`; `--zone` for the Ashwood instead; `--shot` for a screenshot,
`--leave-after=6 --takeover` a handover, `--drop-at=6` a reconnect mid-rift, `--affixes` elite affixes on the
guest, `--allies` hirelings and Ancients, `--revive` falling and reviving, `--levels` party rift levels,
`--goto` arrows and "go to"; `--addr= --key= --partner=` for many pairs on one server, as in the load test).

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
- **Woodland Scout** (after *Into the Ashwood*): an archer who keeps her distance; Shot, plus two of
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
- Opened as the inventory (the 🎒 button or I), it is the bag window alone. The left window shows an NPC's panel with its tabs (the stash: Items, Currency, Gems; the Jeweler: Jeweler and Skills; the Merchant and Blacksmith: their own), the hireling's page (its portrait), or your Stats. Tap any item (in the bag, worn, in the stash or on the hireling) and its card pops up where you tapped. The card is a tooltip made for touch: it stays until you tap elsewhere, and a tap that closes it still goes through.
- Next to it is the card of what you wear in that slot (EQUIPPED; on the hireling's page, what it wears), with each stat marked green or red. Under the tapped card: 🔺 UPGRADE when it beats what you wear, and the list of what changes "Instead of your ...". Gear you can't use says why not. Unidentified items show the comparison without stat marks and have an **Identify** button (Scroll of Identify).
- On the Jeweler's Skills tab, tap a skill slot or a support link and a dropdown opens there: the skill gems (or supports) you have that can go in it, each with its level: tap one to see its card beside the dropdown, tap it again to equip it (a gem in another slot swaps the two; a support that clashes with the slot's others is greyed out), and for the gem there now **What it does** and **Take it out**. There are no lists of loose gems. Skill and support gems on the hireling's page work as before: tap one and its card pops up. It shows what the gem does, its level and experience, and the Gemcutter's Prism button. There is no gem info column.
- So do socket gems and runes (in sockets, the shared gems and the Jeweler's combine slots) and orbs (stash Currency tab). A gem's card shows its effect, tier, count, what it adds to the open item and the next tier. A rune's card also lists the runewords it is part of, with their recipes. An orb's card shows what it does, how many you have, shards, and why it can't be used on the item on the bench.
- **Equip** by dragging it onto its equipment slot (the old item takes its bag space). **Drop** by
  dragging it (from the bag, the paperdoll or a flask slot) onto the empty screen around the windows
  (`scripts/drop_zone.gd`); it lands on the ground and you can't re-pick it for 1.5s. Item cards have no Equip or Drop buttons.
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

### Random encounters, currency piles, see-through scenery
- **Random encounters** (`ZoneEncounters`): entering a campaign zone solo has a 45% chance of one,
  somewhere on open floor away from the start, exits and NPCs and reachable from the start
  (`find_spot`). **Cottage**: a cottage whose zombies burst out when you come within 420 px; clear them
  and a captive appears to free, who pays a rare, orbs and a scroll. **Ritual**: cultists round a
  summoning circle start a 45 s countdown when you come within 650 px; each cultist you kill buys
  6 s; kill them all to break it (rare + magic + orbs), or at 0 a boss "Summoned Horror" is called
  (its loot is a boss's). Party zones have none yet (the host runs their monsters). Test:
  `scratch/test_encounters.gd`; new kinds go in `ZoneEncounters.KINDS` with a `_build_`, a state in
  `_process` and a `_reward`.
- **Currency bundles** (`CurrencyPickup` kind "bundle"): one label holding many drops, taken in one tap.
  `CurrencyPickup.add_to_bundle(scene, title, [kind, id, amount], pos)` adds to a bundle of that title
  within 170 px or starts one, so a zone's drops from a fight are one pile; a rift boss's orbs and
  shards are one "Currency" pile and its gems and runes one "Gems & Runes" pile. Drop rates are
  lower than they were (zone shard chance 0.09, `CraftingDB.monster_drops` and `boss_drops`,
  the rift's horde chances).
- **See-through scenery** (`PropFader`): a prop at least 60 x 90 px as drawn fades to 35% while the
  player is behind it (above its base line and inside its picture). `SceneryMap` and `MazeMap`
  register their props; register anything else with `PropFader.attach(parent, sprite)`.

### Socket gems and runes
**Gems** are Diablo 3 style: five kinds (Ruby: Max Life, Topaz: Damage, Emerald: Attack Speed, Amethyst:
Critical Chance, Diamond: Move Speed) in 8 tiers, Chipped, Flawed, Regular, Flawless, Star, Imperial,
Royal and Flawless Royal (`GemDef`). Three of a tier combine into the next at the Jeweler for orbs.
Tiers 1 to 5 keep the strength they always had (Star is the old Perfect), so owned gems are worth the
same; saved Sapphires became Rubies (`GemDef.RENAMED`). The **33 runes** are Diablo 2's, El to Zod
(`SocketRune.LADDER`). Their icons come from one concept sheet, `tools/art/gems_runes.jpg`, cut by
`tools/import_gem_sheet.py`: the sheet has red gems only, so the other colours are the red turned to
green, yellow, purple and a pale blue-white. (`tools/import_gems_runes.py`, from the CraftPix packs, made
the earlier icons.) Test: `scratch/test_gem_tiers.gd`.

### Shared stash tabs: currency, gems
Orbs and shards, and loose skill, support and socket gems belong to the
account, not a character (`GameState.SHARED_KEYS`, saved in the account file). The stash shows them
in tabs: **Items** (the grid), **Currency** and **Gems**. The inventory keeps only
Equipment and Consumables.
- Skill gems are set only at the Jeweler (its Skills tab). Socket gems and runes go into items at
  the stash (its Gems tab) or the Jeweler (`GameState.gem_station`): drag one onto an item, and take
  them out with the button on the item's card. Gem levels and what each character has socketed stay
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

### Builds without classes
There are no classes. Every character starts as the same Adventurer (140 life, 15 of each attribute,
any weapon it meets the requirements of) and becomes what its points, gems and gear make it:
- **Attributes** (above) and the **passive tree** (`scripts/passive_tree.gd`): one tree for everyone,
  four branches from the middle, Strength up (attack damage, Adrenaline), Dexterity right (speed,
  crits, bows), Vitality down (life, armour) and Energy left (spells, Mana). Many small nodes give
  attribute points. Where two branches meet their connectors give both, and out past the ring each
  diagonal has a hybrid cluster with its own keystone: the Assassin's (Strength and Dexterity), the
  Warden's (Dexterity and Vitality), the Druid's (Vitality and Energy) and the Paladin's (Energy and
  Strength). Keystones include Resolute Technique, Endless Rage, Eagle Eye, Blood Magic (Mana
  skills cost life), Eldritch Battery (30% of damage comes off Mana first) and Archmage.
- **Skill gems by colour** (`scripts/skill_tree.gd`): red Strength gems (melee; Adrenaline, built by
  their basic attacks and by being hit), green Dexterity gems (bows, daggers, speed: Quick Shot,
  Power Shot, Multishot, Arrow Rain, Frenzy, Blade Vortex, Fan of Knives, Shadow Step, Death
  Blossom; Mana) and blue Energy gems (spells: Firebolt, Frost Nova, Arc, Arcane Ward, Holy Nova,
  Meteor, Thunderstorm; Mana), and two-colour ones (Viper Strike, Smite). A gem needs its
  attribute (more for deeper clusters, `SkillTree.GEM_ATTR_REQ`); bow skills need a bow and melee
  skills a melee weapon. Basic Mana skills cost nothing. Mana (60, +2 per Energy) regenerates 2 a
  second plus 3% of the most you have. Supports work on the new skills too: Echo looses arrows,
  knives and lightning again at half damage, Nova turns Multishot into a ring of eight.
- **Main attributes** (Diablo III's primary stat, `LootGenerator.fill_attributes`): besides its
  modifiers every Magic item has one of +Strength, +Dexterity, +Vitality or +Energy, and every Rare, Legendary
  and Set item two different ones (a Legendary's own lean first; otherwise more often than not your
  build's strongest). Normal items and flasks have none. The item card shows them first, in their
  colours. Orbs keep it so: Augmentation and Exalted add modifiers, never main attributes (they
  don't take a modifier's place), Annulment never removes one, and rerolls give the right number.
- **Gear for every build**: modifiers for each attribute (any gear), spell damage, Mana and Mana
  regeneration (caster gear), bow damage (bows) and attack damage. Legendaries and Sets for
  Dexterity (Windpiercer, Hail of Thorns, Shadowfang, Viper's Kiss, Hunter's Cowl, Windrunner's
  Garb), Energy (Emberheart, Frostbinder, Stormcaller's Crook, Sage's Circlet, Wellspring Band,
  Archmage's Vestments), Vitality (Heart of the Mountain) and the hybrids (Lightbringer, Warden's
  Grips, Templar's Vow); more than half the Legendaries and Set pieces that drop lean to your
  build's strongest attribute. Weapon drops favour ones you can wield now.
- **The build's title** (`Attributes.build_title`) comes from where the points went: one attribute
  well ahead is a Warrior, Ranger, Guardian or Sorcerer, two together a hybrid (Assassin, Paladin,
  Juggernaut, Spellblade, Warden, Druid). Others see it on your name, in the party list and when
  inspecting you; your characters list shows it.
- A bow in hand draws your character on the archer rig, drawing and loosing arrows.
- Characters from before classes went are retired when the account loads (`GameState.CHAR_VERSION`);
  the stash and the shared pools stay.
- Test: `godot --headless --path . res://scratch/test_classless.tscn`; `res://scratch/capture_classless.tscn`
  for screenshots (needs a window).
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
  - `helmet/<id>/Head.png` overlays the head (`catalog.json` says whether it hides the hair).
  - `chest/<id>/Body.png`, `Right Arm.png`, `Left Arm.png` overlay the torso and arms.
  - `icon.png` is used in the bag and on the ground.
  Keep the same canvas size and alignment as the matching part in `assets/rigs/zombie/parts/`.
  The archer rig (a bow in hand) lays its Head and Face canvases out differently; `RigSprite` moves
  art made for the zombie rig's (the appearance parts, hair, beards and gear) to where it belongs.
- **Weapon rigs**: `tools/make_weapon_rigs.py` makes three from the zombie rig, each keeping its body,
  head and legs and posing the weapon (a guard while idle, walking and running; an attack timed by
  the zombie rig's own slash), the weapon hand at the grip, each arm turned from its shoulder to
  reach its hand. `RigSprite.rig_for_weapon` picks one by the weapon held (`weapon_style`):
  - `twohand`: two-handed swords, axes and maces, in both hands, 1.35 times bigger: a chop from
    the shoulder forward and down
  - `spear`: spears, 1.5 times bigger, the weapon hand a third of the way up the shaft out in
    front (drawn over the shaft) and the near hand back towards the butt: a thrust, no slash trail
  - `dagger`: daggers, in the weapon hand held low and forward: a short stab at the chest
  - `handxbow`: one-handed crossbows, 1.6 times bigger, aimed forward: raised and loosed
  Rerun it after changing the zombie rig; the styles (sizes, poses, grips) are at its top. Others are
  told the style (the second value of the weapon in its looks), since its look can be any melee
  weapon's. `tools/rig_render.py` draws a rig's frames to an image, to check animations without
  the game.
  Test: `godot --headless --path . res://scratch/test_twohand.tscn`.
  If art is missing, weapons fall back to the rig's own sword and helmets/armour show nothing.
- `tools/make_gear_art.py` generates the placeholder gear art. To add an item, add a `_base(...)`
  line in `loot_generator.gd` with a new id and drop art in the matching folder.
- Gloves and boots are equippable but have no visuals yet; the layer table in `rig_sprite.gd`
  (`GEAR_LAYERS`) is where you would add them.
- The sprites are side-view, so characters flip left/right rather than turning up/down.

**Licence:** check the CraftPix licence (https://craftpix.net/file-licenses) before releasing.
Don't redistribute the raw art on its own.

**Android export:** two presets: "Android Data" exports the whole game (all resources, `*.json`
too, for `rig.json`; not `scratch/`, `tools/`, `builds/` or `pack/`) as the game pack; "Android"
exports the APK with only the selected files `scripts/updater.gd` and `assets/fonts/body.tres` (the
font loads before any script) and the non-resource files `build.json, pack/*`.

The app icon (`assets/icon/`, the project icon and the Android launcher and adaptive icons) is made by
`tools/make_app_icon.py`: the Death Visage helm over a glowing purple rift.

## Map themes and walls (CraftPix 2D RPG tilesets)

A map file's `"theme"` sets its look (`scripts/map_theme.gd`): **desert** (the rifts) and **woodland**
(Act 1: the tutorial, Ashfall and the Ashwood, from the autumn pack). Each theme is a folder
`assets/tiles/<theme>/` holding one CraftPix "2D RPG" tileset, plus which of its pictures dress a map
(trees on wall edges, plants on the floor, big trees on wide plateaus) and the town's random scenery.
A prop can borrow another theme's picture as `"<theme>/<name>"`, e.g. the woods' wagons, tents and
campfire are `desert/decor_8`, `desert/decor_2` and `desert/decor_7`.

**Walls** are raised plateaus with a rock cliff facing the floor below them. `scripts/wall_tiles.gd`
picks each quarter of a wall cell from its neighbours (outer corner, edge, inner corner, middle; a
cliff, or a cliff with a thin ledge on top where a wall is one cell thick), so walls of any shape
join up; `MazeMap` draws them as a tile layer. The packs are drawn for single square plateaus (no
inner corners, and each piece's surface a little different), so `tools/import_tilesets.py` remakes
the pieces on one surface and adds the missing ones in `assets/tiles/<theme>/walls/`.

The packs are on the NAS (Tainted > assets > maps). To add a theme, put its zip in `THEMES` in
`tools/import_tilesets.py` and run `python tools/import_tilesets.py <theme>`, then give it an entry in
`MapTheme.THEMES` and the map editor's `THEMES`. All the "2D RPG" packs (desert, autumn, winter,
tropical) share one layout, so they work as they are; the dungeon, cave and city packs are drawn
differently and would need their own wall pieces.

`scripts/town_map.gd` (on `scripts/scenery_map.gd`) lays out Ashfall by hand with the theme's
pictures and scatters scenery round it (fixed seed); trunks and big rocks block movement, grass
doesn't, and props are y-sorted with the characters.
Licence: `assets/tiles/<theme>/LICENSE_craftpix.txt`; check craftpix.net/file-licenses.

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
- **Merchant**: Buy recipes and orbs, or Sell bag items for orbs. Tap a ware for its card with its
  price and **Buy** (the card stays open to buy another). Tap a bag item for its card with what it sells for
  and **Sell**. Dragging works too: wares into the bag, bag items onto the merchant.

Content is data: add orbs and recipes in `crafting_db.gd`; orb rules live in `crafting.gd`.

**Saving:** orbs, recipes, bag and worn gear are saved to `user://tainted_save.json`
(on every change), so they carry between dungeon runs and app restarts. To wipe it, call
`GameState.reset_save()` or delete that file (on desktop: Godot's user data folder for "Tainted").


### Identifying
Magic, Rare, Legendary and Set gear from rift loot drops unidentified (`ItemInstance.identified`):
it shows only its base name, its modifiers are hidden, and it can't be worn or crafted on.
A **Scroll of Identify** (a currency in the stash, dropped by monsters and bosses, sold by the
Merchant) identifies one item, anywhere: tap the item and press Identify on its card. The **Sage** in town identifies
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
