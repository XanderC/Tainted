class_name Attributes
extends RefCounted
## Diablo II style attributes: Strength, Dexterity, Vitality and Energy. A character has a base in
## each from its class and gets POINTS_PER_LEVEL to add every level. What a point adds is BONUS;
## the base itself adds nothing (it is what gear requirements are measured against from level 1).
## Gear needs enough of some (requirements(), from its kind and drop level): worn gear whose
## requirements aren't met gives none of its stats until they are.

const KEYS := ["str", "dex", "vit", "ene"]
const NAMES := {"str": "Strength", "dex": "Dexterity", "vit": "Vitality", "ene": "Energy"}
const SHORT := {"str": "Str", "dex": "Dex", "vit": "Vit", "ene": "Ene"}
const COLORS := {
	"str": Color(0.95, 0.45, 0.35), "dex": Color(0.45, 0.90, 0.50),
	"vit": Color(1.00, 0.55, 0.60), "ene": Color(0.50, 0.70, 1.00),
}
const POINTS_PER_LEVEL := 5

## Where each class starts. Hirelings have their own (HirelingDB).
const CLASS_BASE := {
	"warrior": {"str": 25, "dex": 15, "vit": 20, "ene": 10},
}

## What each added point gives: [stat, StatBlock.ModType, value]. Energy's resource is read by
## Player.max_resource() (the class resource isn't a StatBlock stat).
const BONUS := {
	"str": [["damage", StatBlock.ModType.INCREASED, 0.01]],
	"dex": [["attack_speed", StatBlock.ModType.INCREASED, 0.005], ["crit_chance", StatBlock.ModType.FLAT, 0.001]],
	"vit": [["max_life", StatBlock.ModType.FLAT, 4.0]],
	"ene": [],
}
const ENERGY_RESOURCE := 1.0  ## max Adrenaline / Mana per point of Energy


static func base_for(class_id: String) -> Dictionary:
	return CLASS_BASE.get(class_id, CLASS_BASE["warrior"])


## One line per attribute for the stats screen: what a point of it adds.
static func bonus_text(key: String, power_name := "Adrenaline") -> String:
	match key:
		"str": return "+1% Damage per point"
		"dex": return "+0.5% Attack Speed and +0.1% Critical Chance per point"
		"vit": return "+4 Maximum Life per point"
		"ene": return "+%d Maximum %s per point" % [int(ENERGY_RESOURCE), power_name]
	return ""


## Adds what `added` points ({key: n}) give to `stats`, as modifiers from `source`.
static func apply(stats: StatBlock, added: Dictionary, source: Variant) -> void:
	stats.remove_source(source)
	for k in KEYS:
		var n := int(added.get(k, 0))
		if n <= 0:
			continue
		for b in BONUS[k]:
			stats.add_mod(String(b[0]), int(b[1]), float(b[2]) * n, source)


# ---------- gear requirements ----------

## [str per item, str per drop level, dex..., dex..., ene..., ene...] by weapon type, two-handers
## apart: heavy weapons want Strength, light ones Dexterity, staves Energy.
const WEAPON_REQ := {
	"sword": [10, 1.0, 8, 0.7, 0, 0.0],
	"sword_2h": [18, 1.4, 8, 0.6, 0, 0.0],
	"axe": [12, 1.1, 5, 0.4, 0, 0.0],
	"axe_2h": [20, 1.5, 0, 0.0, 0, 0.0],
	"mace": [14, 1.2, 0, 0.0, 0, 0.0],
	"mace_2h": [24, 1.6, 0, 0.0, 0, 0.0],
	"spear_2h": [14, 1.0, 12, 0.9, 0, 0.0],
	"dagger": [0, 0.0, 12, 1.1, 0, 0.0],
	"staff_2h": [10, 0.6, 0, 0.0, 10, 1.0],
	"bow_2h": [6, 0.5, 14, 1.2, 0, 0.0],
	"shield": [12, 1.1, 0, 0.0, 0, 0.0],
}
## Armour wants Strength by how much armour its base gives: this many points per point of armour,
## for pieces with at least ARMOUR_REQ_FROM (light caps, vests, gloves and boots need nothing).
const ARMOUR_REQ_PER := 1.3
const ARMOUR_REQ_FROM := 8.0

static var _req_cache := {}


## What a base needs ({key: n}, only the attributes it needs at all). Jewellery, belts and flasks
## need nothing.
static func requirements(base: ItemBase) -> Dictionary:
	if base == null:
		return {}
	if _req_cache.has(base.id):
		return _req_cache[base.id]
	var out := {}
	if base.weapon_type != "":
		var key := base.weapon_type + ("_2h" if base.two_handed and base.weapon_type != "shield" else "")
		var r: Array = WEAPON_REQ.get(key, WEAPON_REQ.get(base.weapon_type, []))
		if not r.is_empty():
			var dl := float(maxi(base.drop_level, 1))
			for i in 3:
				var v := int(round(float(r[i * 2]) + float(r[i * 2 + 1]) * dl))
				if v > 0:
					out[["str", "dex", "ene"][i]] = v
	elif base.slot in ["helmet", "chest", "gloves", "boots"] and base.implicit_stat == "armor" \
			and base.implicit_value >= ARMOUR_REQ_FROM:
		out["str"] = int(round(base.implicit_value * ARMOUR_REQ_PER))
	_req_cache[base.id] = out
	return out


## The requirements `have` ({key: total}) falls short of: {key: [needed, have]}.
static func unmet(base: ItemBase, have: Dictionary) -> Dictionary:
	var out := {}
	var req := requirements(base)
	for k in req:
		if int(have.get(k, 0)) < int(req[k]):
			out[k] = [int(req[k]), int(have.get(k, 0))]
	return out


static func meets(base: ItemBase, have: Dictionary) -> bool:
	return unmet(base, have).is_empty()


## "Requires 40 Strength (you have 30)" for the first requirement not met, or "".
static func block_reason(base: ItemBase, have: Dictionary, who := "you have") -> String:
	var u := unmet(base, have)
	for k in KEYS:
		if u.has(k):
			return "Requires %d %s (%s %d)" % [u[k][0], NAMES[k], who, u[k][1]]
	return ""


## BBCode for an item card: "Requires 40 Str, 22 Dex", each red when `have` falls short.
## "" when it needs nothing. `have` empty: shown without judging.
static func requirement_bbcode(base: ItemBase, have: Dictionary) -> String:
	var req := requirements(base)
	if req.is_empty():
		return ""
	var parts: Array[String] = []
	for k in KEYS:
		if not req.has(k):
			continue
		var short_of := not have.is_empty() and int(have.get(k, 0)) < int(req[k])
		parts.append("[color=#%s]%d %s[/color]" % ["f87171" if short_of else "d8cdb8", int(req[k]), NAMES[k]])
	return "[color=#9a8f7e]Requires[/color] " + ", ".join(PackedStringArray(parts))
