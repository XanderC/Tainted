class_name CraftingDB
extends RefCounted
## Crafting content: orbs, recipes, drop tables, vendor prices. Orbs are the only crafting currency:
## recipes cost orbs too.
## Add content by adding entries to the dictionaries below.

const R := ItemInstance.Rarity

# Orbs: Path of Exile style currency. They modify items (or gems / the passive tree), and they
# are the money too (see Currency): vendors price everything in orbs.
#   value - worth in Orbs of Transmutation (old gold conversion)
#   drop  - relative drop weight
const ORBS := {
	"identify": {"name": "Scroll of Identify", "short": "Identify", "tag": "ID", "color": Color(0.93, 0.86, 0.66),
		"desc": "Reveal an unidentified item's modifiers. Use it anywhere: tap the item in your bag", "value": 1, "drop": 400},
	"transmute": {"name": "Orb of Transmutation", "short": "Transmute", "tag": "Trans", "color": Color(0.6, 0.7, 1.0),
		"desc": "Normal item to Magic with 1-2 affixes", "value": 1, "drop": 300},
	"alteration": {"name": "Orb of Alteration", "short": "Alteration", "tag": "Alt", "color": Color(0.5, 0.9, 0.9),
		"desc": "Reroll a Magic item's affixes", "value": 2, "drop": 300},
	"augment": {"name": "Orb of Augmentation", "short": "Augment", "tag": "Aug", "color": Color(0.7, 0.6, 1.0),
		"desc": "Add an affix to a Magic item with room", "value": 2, "drop": 180},
	"chance": {"name": "Orb of Chance", "short": "Chance", "tag": "Chance", "color": Color(0.85, 0.85, 0.55),
		"desc": "Normal item to a random rarity - small chance of a Legendary or Set item of that base", "value": 3, "drop": 140},
	"jeweller": {"name": "Jeweller's Orb", "short": "Jeweller's", "tag": "Jwl", "color": Color(0.55, 0.85, 0.55),
		"desc": "Reroll how many gem sockets an item has", "value": 3, "drop": 120},
	"armourer": {"name": "Armourer's Scrap", "short": "Armourer's", "tag": "Scrap", "color": Color(0.7, 0.7, 0.75),
		"desc": "+Quality on armour or a shield (+5 Normal, +2 Magic, +1 other; max 20%): more Armor", "value": 1, "drop": 200},
	"whetstone": {"name": "Blacksmith's Whetstone", "short": "Whetstone", "tag": "Whet", "color": Color(0.8, 0.75, 0.6),
		"desc": "+Quality on a weapon (+5 Normal, +2 Magic, +1 other; max 20%): more Damage", "value": 2, "drop": 160},
	"blessed": {"name": "Blessed Orb", "short": "Blessed", "tag": "Bless", "color": Color(0.95, 0.95, 0.75),
		"desc": "Reroll the value of an item's implicit stat", "value": 6, "drop": 80},
	"scour": {"name": "Orb of Scouring", "short": "Scour", "tag": "Scour", "color": Color(0.85, 0.85, 0.85),
		"desc": "Strip all affixes, back to Normal", "value": 6, "drop": 80},
	"regret": {"name": "Orb of Regret", "short": "Regret", "tag": "Regret", "color": Color(0.55, 0.65, 0.95),
		"desc": "Refund one allocated passive tree node (spent from the passive tree)", "value": 8, "drop": 60},
	"alchemy": {"name": "Orb of Alchemy", "short": "Alchemy", "tag": "Alch", "color": Color(1.0, 0.75, 0.3),
		"desc": "Normal item to Rare with 4 affixes", "value": 8, "drop": 100},
	"regal": {"name": "Regal Orb", "short": "Regal", "tag": "Regal", "color": Color(0.95, 0.8, 0.4),
		"desc": "Magic item to Rare, adds an affix", "value": 12, "drop": 80},
	"chaos": {"name": "Chaos Orb", "short": "Chaos", "tag": "Chaos", "color": Color(0.9, 0.5, 0.2),
		"desc": "Reroll all affixes of a Rare item", "value": 20, "drop": 60},
	"gemcutter": {"name": "Gemcutter's Prism", "short": "Gemcutter's", "tag": "GCP", "color": Color(0.6, 0.95, 0.95),
		"desc": "Give a skill or support gem a level's worth of experience (used from the Skills panel)", "value": 20, "drop": 30},
	"vaal": {"name": "Vaal Orb", "short": "Vaal", "tag": "Vaal", "color": Color(0.85, 0.2, 0.25),
		"desc": "Corrupt an item: nothing, a stronger implicit, an extra socket, or a full reroll. It can never be changed again", "value": 20, "drop": 30},
	"annul": {"name": "Orb of Annulment", "short": "Annulment", "tag": "Annul", "color": Color(0.95, 0.95, 1.0),
		"desc": "Remove a random affix from an item", "value": 60, "drop": 15},
	"exalt": {"name": "Exalted Orb", "short": "Exalt", "tag": "Ex", "color": Color(1.0, 0.95, 0.6),
		"desc": "Add an affix to a Rare item (max 6)", "value": 150, "drop": 20},
	"divine": {"name": "Divine Orb", "short": "Divine", "tag": "Div", "color": Color(1.0, 1.0, 1.0),
		"desc": "Reroll the values of an item's affixes (and a Legendary's power)", "value": 250, "drop": 10},
	"mirror": {"name": "Mirror of Kalandra", "short": "Mirror", "tag": "Mirror", "color": Color(0.75, 0.95, 1.0),
		"desc": "Create a mirrored copy of an item (the copy can't be changed)", "value": 5000, "drop": 1},
}
## Display order of orbs (cheapest first).
const ORB_ORDER := ["identify", "transmute", "alteration", "augment", "chance", "jeweller", "armourer", "whetstone",
	"blessed", "scour", "regret", "alchemy", "regal", "chaos", "gemcutter", "vaal", "annul", "exalt", "divine", "mirror"]


static func orb_icon(id: String) -> Texture2D:
	var path := "res://assets/icons/orbs/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return IconFactory.material_icon(id, ORBS[id].color)


## Older saves held crafting materials (now gone): each converts into shards of the orb it was
## worth: id -> [orb, shards per material]. 20 shards make an orb (Currency.SHARDS_PER_ORB).
const OLD_MATERIAL_SHARDS := {
	"scrap": ["transmute", 4],     # 5 Iron Scrap sold for 1 Transmutation
	"dust": ["alteration", 7],     # 3 Arcane Dust for 1 Alteration
	"essence": ["alteration", 60], # 1 Wraith Essence for 3 Alterations
	"core": ["chaos", 10],         # boss only
	"soul": ["chaos", 10],         # boss only
}

# source: "start" (known from the beginning), "drop" (found on monsters/bosses), "vendor" (bought with orbs),
# "plan" (a Legendary / Set item plan, dropped by rift bosses; added by _static_init from UniqueItems)
static var RECIPES := {
# "cost" is in orbs, like every other price. (Swapping orbs for orbs is the Merchant's exchange.)
	"forge_weapon": {"name": "Forge Weapon", "desc": "A fresh Normal weapon.", "source": "start",
		"cost": {"transmute": 3}, "result": {"type": "item", "slot": "weapon", "rarity": R.NORMAL}},
	"forge_helmet": {"name": "Forge Helmet", "desc": "A fresh Normal helmet.", "source": "start",
		"cost": {"transmute": 2}, "result": {"type": "item", "slot": "helmet", "rarity": R.NORMAL}},
	"forge_chest": {"name": "Forge Armour", "desc": "A fresh Normal chest piece.", "source": "start",
		"cost": {"transmute": 3}, "result": {"type": "item", "slot": "chest", "rarity": R.NORMAL}},
	"arcane_forging": {"name": "Arcane Forging", "desc": "A Magic item of any kind.", "source": "vendor", "price": {"alteration": 6},
		"cost": {"alteration": 3}, "result": {"type": "item", "slot": "", "rarity": R.MAGIC}},
	"masterwork": {"name": "Masterwork", "desc": "A Rare item of any kind, +2 item level.", "source": "vendor", "price": {"chaos": 2},
		"cost": {"alchemy": 3}, "result": {"type": "item", "slot": "", "rarity": R.RARE, "ilvl_bonus": 2}},
	# Exalted Orbs are never sold: finding this recipe is the one way to make them
	"exalted_rite": {"name": "Exalted Rite", "desc": "1 Exalted Orb.", "source": "drop",
		"cost": {"chaos": 3}, "result": {"type": "orb", "id": "exalt", "n": 1}},
	"tainted_weapon": {"name": "Tainted Weapon", "desc": "A Rare weapon, +5 item level.", "source": "drop",
		"cost": {"chaos": 2}, "result": {"type": "item", "slot": "weapon", "rarity": R.RARE, "ilvl_bonus": 5}},
	"tainted_armour": {"name": "Tainted Armour", "desc": "A Rare chest piece, +5 item level.", "source": "drop",
		"cost": {"chaos": 2}, "result": {"type": "item", "slot": "chest", "rarity": R.RARE, "ilvl_bonus": 5}},
}

## What forging a Legendary / Set plan costs.
const LEGENDARY_PLAN_COST := {"chaos": 4}
const SET_PLAN_COST := {"chaos": 3}
const PLAN_ILVL_BONUS := 5


## One plan recipe per Legendary and Set item ("plan_<item id>").
static func _static_init() -> void:
	for uid in UniqueItems.LEGENDARIES:
		var info: Dictionary = UniqueItems.LEGENDARIES[uid]
		RECIPES["plan_" + uid] = {"name": info.name, "source": "plan", "cost": LEGENDARY_PLAN_COST,
			"desc": "Legendary: up to " + PassiveTree.stat_text(_max_power(info.power)),
			"result": {"type": "unique", "id": uid, "ilvl_bonus": PLAN_ILVL_BONUS}}
	for uid in UniqueItems.SET_ITEMS:
		var info: Dictionary = UniqueItems.SET_ITEMS[uid]
		RECIPES["plan_" + uid] = {"name": info.name, "source": "plan", "cost": SET_PLAN_COST,
			"desc": "Set: " + String(UniqueItems.SETS[info.set].name),
			"result": {"type": "unique", "id": uid, "ilvl_bonus": PLAN_ILVL_BONUS}}


static func _max_power(power: Dictionary) -> Dictionary:
	var out := {}
	for k in power:
		out[k] = float(power[k][1])
	return out


## Plan recipe ids for Legendary (or Set) items, in database order.
static func plan_ids(set_items: bool) -> Array[String]:
	var out: Array[String] = []
	for uid in (UniqueItems.SET_ITEMS if set_items else UniqueItems.LEGENDARIES):
		out.append("plan_" + String(uid))
	return out


static func is_plan(recipe_id: String) -> bool:
	return RECIPES.has(recipe_id) and RECIPES[recipe_id].source == "plan"


## Name colour for a recipe: orange for Legendary plans, green for Set plans.
static func recipe_color(recipe_id: String) -> Color:
	if is_plan(recipe_id):
		var uid: String = RECIPES[recipe_id].result.id
		return ItemInstance.RARITY_COLORS[R.LEGENDARY if UniqueItems.LEGENDARIES.has(uid) else R.SET]
	return Color(0.9, 0.75, 0.5)


const STARTING_CURRENCY := {"identify": 5, "transmute": 8, "alteration": 6, "augment": 3, "chance": 1, "armourer": 2, "whetstone": 1}


## Drops from one normal monster kill. Returns {"shards": {...}, "orbs": {...}}.
static func monster_drops(ilvl: int) -> Dictionary:
	var out := {"shards": {}, "orbs": {}}
	if randf() < 0.25:
		out.shards["transmute"] = randi_range(1, 2) + int(ilvl / 15.0)
	elif randf() < 0.10:
		out.shards["alteration"] = 1
	# What used to drop as crafting materials, as the shards it was worth
	var r := randf()
	if r < 0.18:
		_add(out.shards, "transmute", randi_range(3, 5))
	elif r < 0.25:
		_add(out.shards, "alteration", 4)
	elif r < 0.27:
		_add(out.orbs, "alteration", 2)
	if randf() < 0.12:
		out.orbs[_weighted_orb()] = 1
	if randf() < 0.06:
		_add(out.orbs, "identify", 1)
	return out


static func _weighted_orb() -> String:
	var total := 0
	for k in ORBS:
		total += int(ORBS[k].drop)
	var r := randi_range(1, total)
	for k in ORBS:
		r -= int(ORBS[k].drop)
		if r <= 0:
			return k
	return "transmute"


## Guaranteed boss loot (besides the item rewards). Better when cleared under the time limit.
static func boss_drops(fast: bool) -> Dictionary:
	var m := 2 if fast else 1
	var out := {"shards": {"alchemy": randi_range(3, 5) * m, "chaos": randi_range(1, 3) * m}, "orbs": {}}
	# What used to drop as crafting materials (cores, souls, essence, dust), as the orbs it was worth
	_add(out.shards, "chaos", 6 * ((randi_range(1, 2) if fast else 1) + (randi_range(1, 2) if fast else 1)))
	_add(out.orbs, "alteration", 2 * (randi_range(2, 3) if fast else randi_range(1, 2)))
	_add(out.shards, "alteration", 5 * randi_range(2, 4))
	_add(out.orbs, "identify", randi_range(1, 3) * m)
	var n := 4 if fast else 2
	for i in n:
		var id := _weighted_orb()
		out.orbs[id] = int(out.orbs.get(id, 0)) + 1
	return out


static func _add(into: Dictionary, id: String, n: int) -> void:
	into[id] = int(into.get(id, 0)) + n
