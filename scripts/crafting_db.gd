class_name CraftingDB
extends RefCounted
## Crafting content: orbs, materials, recipes, drop tables, vendor prices.
## Add content by adding entries to the dictionaries below.

const R := ItemInstance.Rarity

# Orbs: Path of Exile style currency. They modify items (or gems / the passive tree), and they
# are the money too (see Currency): vendors price everything in orbs.
#   value - worth in Orbs of Transmutation (old gold conversion)
#   drop  - relative drop weight
const ORBS := {
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
const ORB_ORDER := ["transmute", "alteration", "augment", "chance", "jeweller", "armourer", "whetstone",
	"blessed", "scour", "regret", "alchemy", "regal", "chaos", "gemcutter", "vaal", "annul", "exalt", "divine", "mirror"]


static func orb_icon(id: String) -> Texture2D:
	var path := "res://assets/icons/orbs/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return IconFactory.material_icon(id, ORBS[id].color)


# Materials come from monsters and from salvaging gear (Diablo 3 style).
# "bundle": [how many, price] the Merchant sells them in (none for boss-only materials).
const MATERIALS := {
	"scrap": {"name": "Iron Scrap", "color": Color(0.75, 0.75, 0.8), "bundle": [5, {"transmute": 1}]},
	"dust": {"name": "Arcane Dust", "color": Color(0.55, 0.6, 1.0), "bundle": [3, {"alteration": 1}]},
	"essence": {"name": "Wraith Essence", "color": Color(1.0, 0.85, 0.35), "bundle": [1, {"alteration": 3}]},
	"core": {"name": "Tainted Core", "color": Color(0.8, 0.4, 1.0)},  # boss drop only
	# bosses and salvaged Legendary / Set items only; spent on plans
	"soul": {"name": "Forgotten Soul", "color": Color(0.35, 0.95, 0.90)},
}

# source: "start" (known from the beginning), "drop" (found on monsters/bosses), "vendor" (bought with orbs),
# "plan" (a Legendary / Set item plan, dropped by rift bosses; added by _static_init from UniqueItems)
static var RECIPES := {
	"forge_weapon": {"name": "Forge Weapon", "desc": "A fresh Normal weapon.", "source": "start",
		"cost": {"scrap": 12}, "result": {"type": "item", "slot": "weapon", "rarity": R.NORMAL}},
	"forge_helmet": {"name": "Forge Helmet", "desc": "A fresh Normal helmet.", "source": "start",
		"cost": {"scrap": 10}, "result": {"type": "item", "slot": "helmet", "rarity": R.NORMAL}},
	"forge_chest": {"name": "Forge Armour", "desc": "A fresh Normal chest piece.", "source": "start",
		"cost": {"scrap": 14}, "result": {"type": "item", "slot": "chest", "rarity": R.NORMAL}},
	"bundle_transmute": {"name": "Transmutation Bundle", "desc": "4 Orbs of Transmutation.", "source": "start",
		"cost": {"scrap": 8}, "result": {"type": "orb", "id": "transmute", "n": 4}},
	"arcane_forging": {"name": "Arcane Forging", "desc": "A Magic item of any kind.", "source": "vendor", "price": {"alteration": 6},
		"cost": {"scrap": 10, "dust": 6}, "result": {"type": "item", "slot": "", "rarity": R.MAGIC}},
	"bundle_alteration": {"name": "Alteration Bundle", "desc": "3 Orbs of Alteration.", "source": "vendor", "price": {"alchemy": 1},
		"cost": {"dust": 5}, "result": {"type": "orb", "id": "alteration", "n": 3}},
	"distill_chaos": {"name": "Distill Chaos", "desc": "1 Chaos Orb.", "source": "vendor", "price": {"alchemy": 4},
		"cost": {"essence": 3, "dust": 4}, "result": {"type": "orb", "id": "chaos", "n": 1}},
	"masterwork": {"name": "Masterwork", "desc": "A Rare item of any kind, +2 item level.", "source": "vendor", "price": {"chaos": 2},
		"cost": {"scrap": 10, "dust": 8, "essence": 3}, "result": {"type": "item", "slot": "", "rarity": R.RARE, "ilvl_bonus": 2}},
	"exalted_rite": {"name": "Exalted Rite", "desc": "1 Exalted Orb.", "source": "drop",
		"cost": {"core": 1, "essence": 6}, "result": {"type": "orb", "id": "exalt", "n": 1}},
	"tainted_weapon": {"name": "Tainted Weapon", "desc": "A Rare weapon, +5 item level.", "source": "drop",
		"cost": {"core": 2, "essence": 4, "scrap": 20}, "result": {"type": "item", "slot": "weapon", "rarity": R.RARE, "ilvl_bonus": 5}},
	"tainted_armour": {"name": "Tainted Armour", "desc": "A Rare chest piece, +5 item level.", "source": "drop",
		"cost": {"core": 2, "essence": 4, "scrap": 20}, "result": {"type": "item", "slot": "chest", "rarity": R.RARE, "ilvl_bonus": 5}},
}

## Materials a Legendary / Set plan costs to forge.
const LEGENDARY_PLAN_COST := {"soul": 2, "core": 2, "essence": 6}
const SET_PLAN_COST := {"soul": 1, "core": 2, "essence": 5, "dust": 6}
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


const STARTING_CURRENCY := {"transmute": 8, "alteration": 6, "augment": 3, "chance": 1, "armourer": 2, "whetstone": 1}
const STARTING_MATERIALS := {"scrap": 10}


static func cost_text(cost: Dictionary, have_mats: Dictionary = {}) -> String:
	var parts: Array[String] = []
	for k in cost:
		var m: Dictionary = MATERIALS[k]
		var ok: bool = int(have_mats.get(k, 0)) >= int(cost[k])
		var col: String = (Color(0.6, 0.9, 0.6) if ok else Color(0.95, 0.4, 0.4)).to_html(false)
		parts.append("[color=#%s]%d %s[/color]" % [col, cost[k], m.name])
	return ", ".join(PackedStringArray(parts))


## Materials gained by salvaging an item.
static func salvage_yield(item: ItemInstance) -> Dictionary:
	var bonus := int(item.ilvl / 5.0)
	match item.rarity:
		R.MAGIC:
			return {"scrap": randi_range(1, 2) + bonus, "dust": randi_range(1, 3) + bonus}
		R.RARE:
			return {"dust": randi_range(2, 4) + bonus, "essence": randi_range(1, 2)}
		R.LEGENDARY, R.SET:
			return {"essence": randi_range(2, 4) + int(bonus / 2.0), "core": 1, "soul": 1}
		_:
			return {"scrap": randi_range(1, 3) + bonus}


static func salvage_preview(item: ItemInstance) -> String:
	var bonus := int(item.ilvl / 5.0)
	match item.rarity:
		R.MAGIC:
			return "%d-%d Iron Scrap, %d-%d Arcane Dust" % [1 + bonus, 2 + bonus, 1 + bonus, 3 + bonus]
		R.RARE:
			return "%d-%d Arcane Dust, 1-2 Wraith Essence" % [2 + bonus, 4 + bonus]
		R.LEGENDARY, R.SET:
			return "%d-%d Wraith Essence, 1 Tainted Core, 1 Forgotten Soul" % [2 + int(bonus / 2.0), 4 + int(bonus / 2.0)]
		_:
			return "%d-%d Iron Scrap" % [1 + bonus, 3 + bonus]


## Drops from one normal monster kill. Returns {"shards": {...}, "materials": {...}, "orbs": {...}}.
static func monster_drops(ilvl: int) -> Dictionary:
	var out := {"shards": {}, "materials": {}, "orbs": {}}
	if randf() < 0.40:
		out.shards["transmute"] = randi_range(1, 3) + int(ilvl / 10.0)
	elif randf() < 0.15:
		out.shards["alteration"] = randi_range(1, 2)
	var r := randf()
	if r < 0.30:
		out.materials["scrap"] = randi_range(1, 2)
	elif r < 0.40:
		out.materials["dust"] = 1
	elif r < 0.43:
		out.materials["essence"] = 1
	if randf() < 0.22:
		out.orbs[_weighted_orb()] = 1
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
	var out := {"shards": {"alchemy": randi_range(4, 8) * m, "chaos": randi_range(2, 5) * m}, "materials": {}, "orbs": {}}
	out.materials["core"] = randi_range(1, 2) if fast else 1
	out.materials["soul"] = randi_range(1, 2) if fast else 1
	out.materials["essence"] = randi_range(2, 4) if fast else randi_range(1, 2)
	out.materials["dust"] = randi_range(4, 8)
	var n := 6 if fast else 3
	for i in n:
		var id := _weighted_orb()
		out.orbs[id] = int(out.orbs.get(id, 0)) + 1
	return out
