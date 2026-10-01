class_name CraftingDB
extends RefCounted
## Crafting content: orbs, materials, recipes, drop tables, vendor prices.
## Add content by adding entries to the dictionaries below.

const R := ItemInstance.Rarity

# Orbs modify an existing item (Path of Exile style).
const ORBS := {
	"transmute": {"name": "Orb of Transmutation", "short": "Transmute", "color": Color(0.6, 0.7, 1.0),
		"desc": "Normal to Magic with 1-2 affixes", "price": 15, "drop": 30},
	"alteration": {"name": "Orb of Alteration", "short": "Alteration", "color": Color(0.5, 0.9, 0.9),
		"desc": "Reroll a Magic item's affixes", "price": 20, "drop": 30},
	"augment": {"name": "Orb of Augmentation", "short": "Augment", "color": Color(0.7, 0.6, 1.0),
		"desc": "Add an affix to a Magic item with room", "price": 25, "drop": 18},
	"regal": {"name": "Regal Orb", "short": "Regal", "color": Color(0.95, 0.8, 0.4),
		"desc": "Magic to Rare, adds an affix", "price": 80, "drop": 8},
	"alchemy": {"name": "Orb of Alchemy", "short": "Alchemy", "color": Color(1.0, 0.75, 0.3),
		"desc": "Normal to Rare with 4 affixes", "price": 60, "drop": 10},
	"chaos": {"name": "Chaos Orb", "short": "Chaos", "color": Color(0.9, 0.5, 0.2),
		"desc": "Reroll all affixes of a Rare item", "price": 120, "drop": 6},
	"exalt": {"name": "Exalted Orb", "short": "Exalt", "color": Color(1.0, 0.95, 0.6),
		"desc": "Add an affix to a Rare (max 6)", "price": 500, "drop": 2},
	"divine": {"name": "Divine Orb", "short": "Divine", "color": Color(1.0, 1.0, 1.0),
		"desc": "Reroll the values of all affixes", "price": 900, "drop": 1},
	"scour": {"name": "Orb of Scouring", "short": "Scour", "color": Color(0.85, 0.85, 0.85),
		"desc": "Strip all affixes, back to Normal", "price": 50, "drop": 8},
}

# Materials come from monsters and from salvaging gear (Diablo 3 style).
const MATERIALS := {
	"scrap": {"name": "Iron Scrap", "color": Color(0.75, 0.75, 0.8), "price": 5},
	"dust": {"name": "Arcane Dust", "color": Color(0.55, 0.6, 1.0), "price": 15},
	"essence": {"name": "Wraith Essence", "color": Color(1.0, 0.85, 0.35), "price": 60},
	"core": {"name": "Tainted Core", "color": Color(0.8, 0.4, 1.0), "price": 0},  # boss drop only
}

# source: "start" (known from the beginning), "drop" (found on monsters/bosses), "vendor" (bought with gold)
const RECIPES := {
	"forge_weapon": {"name": "Forge Weapon", "desc": "A fresh Normal weapon.", "source": "start",
		"cost": {"scrap": 12}, "result": {"type": "item", "slot": "weapon", "rarity": R.NORMAL}},
	"forge_helmet": {"name": "Forge Helmet", "desc": "A fresh Normal helmet.", "source": "start",
		"cost": {"scrap": 10}, "result": {"type": "item", "slot": "helmet", "rarity": R.NORMAL}},
	"forge_chest": {"name": "Forge Armour", "desc": "A fresh Normal chest piece.", "source": "start",
		"cost": {"scrap": 14}, "result": {"type": "item", "slot": "chest", "rarity": R.NORMAL}},
	"bundle_transmute": {"name": "Transmutation Bundle", "desc": "4 Orbs of Transmutation.", "source": "start",
		"cost": {"scrap": 8}, "result": {"type": "orb", "id": "transmute", "n": 4}},
	"arcane_forging": {"name": "Arcane Forging", "desc": "A Magic item of any kind.", "source": "vendor", "price": 120,
		"cost": {"scrap": 10, "dust": 6}, "result": {"type": "item", "slot": "", "rarity": R.MAGIC}},
	"bundle_alteration": {"name": "Alteration Bundle", "desc": "3 Orbs of Alteration.", "source": "vendor", "price": 150,
		"cost": {"dust": 5}, "result": {"type": "orb", "id": "alteration", "n": 3}},
	"distill_chaos": {"name": "Distill Chaos", "desc": "1 Chaos Orb.", "source": "vendor", "price": 300,
		"cost": {"essence": 3, "dust": 4}, "result": {"type": "orb", "id": "chaos", "n": 1}},
	"masterwork": {"name": "Masterwork", "desc": "A Rare item of any kind, +2 item level.", "source": "vendor", "price": 400,
		"cost": {"scrap": 10, "dust": 8, "essence": 3}, "result": {"type": "item", "slot": "", "rarity": R.RARE, "ilvl_bonus": 2}},
	"exalted_rite": {"name": "Exalted Rite", "desc": "1 Exalted Orb.", "source": "drop",
		"cost": {"core": 1, "essence": 6}, "result": {"type": "orb", "id": "exalt", "n": 1}},
	"tainted_weapon": {"name": "Tainted Weapon", "desc": "A Rare weapon, +5 item level.", "source": "drop",
		"cost": {"core": 2, "essence": 4, "scrap": 20}, "result": {"type": "item", "slot": "weapon", "rarity": R.RARE, "ilvl_bonus": 5}},
	"tainted_armour": {"name": "Tainted Armour", "desc": "A Rare chest piece, +5 item level.", "source": "drop",
		"cost": {"core": 2, "essence": 4, "scrap": 20}, "result": {"type": "item", "slot": "chest", "rarity": R.RARE, "ilvl_bonus": 5}},
}

const STARTING_CURRENCY := {"transmute": 6, "alteration": 4, "augment": 3}
const STARTING_MATERIALS := {"scrap": 10}
const STARTING_GOLD := 60


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
		_:
			return {"scrap": randi_range(1, 3) + bonus}


static func salvage_preview(item: ItemInstance) -> String:
	var bonus := int(item.ilvl / 5.0)
	match item.rarity:
		R.MAGIC:
			return "%d-%d Iron Scrap, %d-%d Arcane Dust" % [1 + bonus, 2 + bonus, 1 + bonus, 3 + bonus]
		R.RARE:
			return "%d-%d Arcane Dust, 1-2 Wraith Essence" % [2 + bonus, 4 + bonus]
		_:
			return "%d-%d Iron Scrap" % [1 + bonus, 3 + bonus]


## Drops from one normal monster kill. Returns {"gold": n, "materials": {...}, "orbs": {...}}.
static func monster_drops(ilvl: int) -> Dictionary:
	var out := {"gold": 0, "materials": {}, "orbs": {}}
	if randf() < 0.40:
		out.gold = randi_range(1, 4) + ilvl
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
	var out := {"gold": randi_range(60, 100) * (2 if fast else 1), "materials": {}, "orbs": {}}
	out.materials["core"] = randi_range(1, 2) if fast else 1
	out.materials["essence"] = randi_range(2, 4) if fast else randi_range(1, 2)
	out.materials["dust"] = randi_range(4, 8)
	var n := 6 if fast else 3
	for i in n:
		var id := _weighted_orb()
		out.orbs[id] = int(out.orbs.get(id, 0)) + 1
	return out
