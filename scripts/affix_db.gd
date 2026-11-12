class_name AffixDB
extends RefCounted
## Item modifiers the way Path of Exile 2 has them: every modifier belongs to a family (one per item), is a
## prefix or a suffix, and has tiers, each needing a minimum item level and rolling inside its own range.
## The tier tables are PoE2's own (AffixData, made by tools/import_poe2_mods.py from poe2db.tw); this file says
## what each family does in Tainted, and how far PoE2's numbers are scaled to Tainted's smaller life and damage.
##
## A family is {prefix, stat, mod, text, scale, pct}:
##   text    "{v}" is the rolled value;
##   scale   PoE2's numbers x this (Tainted's characters have about 140 Life, not 1500);
##   pct     the numbers are percentages and the stat is a fraction (the stat's value is the roll / 100).

const F := StatBlock.ModType.FLAT
const I := StatBlock.ModType.INCREASED

const FAMILIES := {
	# Prefixes
	"life": {"prefix": true, "stat": "max_life", "mod": F, "text": "+{v} to maximum Life", "scale": 0.7},
	"mana": {"prefix": true, "stat": "mana_max", "mod": F, "text": "+{v} to maximum Mana", "scale": 0.6},
	"life_pct": {"prefix": true, "stat": "max_life", "mod": I, "text": "{v}% increased maximum Life", "scale": 1.0, "pct": true},
	"mana_pct": {"prefix": true, "stat": "mana_max", "mod": I, "text": "{v}% increased maximum Mana", "scale": 1.0, "pct": true},
	"armour": {"prefix": true, "stat": "armor", "mod": F, "text": "+{v} to Armour", "scale": 0.35},
	"armour_pct": {"prefix": true, "stat": "armor", "mod": I, "text": "{v}% increased Armour", "scale": 0.5, "pct": true},
	"phys_add": {"prefix": true, "stat": "damage", "mod": F, "text": "Adds {v} Physical Damage", "scale": 0.8},
	"fire_add": {"prefix": true, "stat": "dmg_fire", "mod": F, "text": "Adds {v} Fire Damage", "scale": 0.6},
	"cold_add": {"prefix": true, "stat": "dmg_cold", "mod": F, "text": "Adds {v} Cold Damage", "scale": 0.6},
	"lightning_add": {"prefix": true, "stat": "dmg_lightning", "mod": F, "text": "Adds {v} Lightning Damage", "scale": 0.6},
	"phys_pct": {"prefix": true, "stat": "damage", "mod": I, "text": "{v}% increased Damage", "scale": 0.35, "pct": true},
	"elem_pct": {"prefix": true, "stat": "ele_inc", "mod": F, "text": "{v}% increased Elemental Damage", "scale": 0.4, "pct": true},
	"fire_pct": {"prefix": true, "stat": "fire_inc", "mod": F, "text": "{v}% increased Fire Damage", "scale": 0.8, "pct": true},
	"cold_pct": {"prefix": true, "stat": "cold_inc", "mod": F, "text": "{v}% increased Cold Damage", "scale": 0.8, "pct": true},
	"lightning_pct": {"prefix": true, "stat": "lightning_inc", "mod": F, "text": "{v}% increased Lightning Damage", "scale": 0.8, "pct": true},
	"chaos_pct": {"prefix": true, "stat": "chaos_inc", "mod": F, "text": "{v}% increased Chaos Damage", "scale": 0.8, "pct": true},
	"spell_dmg": {"prefix": true, "stat": "spell_inc", "mod": F, "text": "{v}% increased Spell Damage", "scale": 0.4, "pct": true},
	"move_speed": {"prefix": true, "stat": "move_speed", "mod": I, "text": "{v}% increased Movement Speed", "scale": 0.6, "pct": true},
	# Suffixes
	"str": {"prefix": false, "stat": "str", "mod": F, "text": "+{v} to Strength", "scale": 0.6},
	"dex": {"prefix": false, "stat": "dex", "mod": F, "text": "+{v} to Dexterity", "scale": 0.6},
	"vit": {"prefix": false, "stat": "vit", "mod": F, "text": "+{v} to Vitality", "scale": 0.6},
	"ene": {"prefix": false, "stat": "ene", "mod": F, "text": "+{v} to Energy", "scale": 0.6},
	"all_attr": {"prefix": false, "stat": "all_attr", "mod": F, "text": "+{v} to all Attributes", "scale": 0.6},
	"res_fire": {"prefix": false, "stat": "res_fire", "mod": F, "text": "+{v}% to Fire Resistance", "scale": 1.0, "pct": true},
	"res_cold": {"prefix": false, "stat": "res_cold", "mod": F, "text": "+{v}% to Cold Resistance", "scale": 1.0, "pct": true},
	"res_lightning": {"prefix": false, "stat": "res_lightning", "mod": F, "text": "+{v}% to Lightning Resistance", "scale": 1.0, "pct": true},
	"res_chaos": {"prefix": false, "stat": "res_chaos", "mod": F, "text": "+{v}% to Chaos Resistance", "scale": 1.0, "pct": true},
	"res_all": {"prefix": false, "stat": "res_all", "mod": F, "text": "+{v}% to all Elemental Resistances", "scale": 1.0, "pct": true},
	"attack_speed": {"prefix": false, "stat": "attack_speed", "mod": I, "text": "{v}% increased Attack Speed", "scale": 0.6, "pct": true},
	"cast_speed": {"prefix": false, "stat": "attack_speed", "mod": I, "text": "{v}% increased Cast Speed", "scale": 0.6, "pct": true},
	"crit_chance": {"prefix": false, "stat": "crit_chance", "mod": F, "text": "+{v}% to Critical Hit Chance", "scale": 1.5, "pct": true},
	"crit_chance_inc": {"prefix": false, "stat": "crit_chance", "mod": I, "text": "{v}% increased Critical Hit Chance", "scale": 0.8, "pct": true},
	"crit_damage": {"prefix": false, "stat": "crit_damage", "mod": F, "text": "+{v}% to Critical Damage Bonus", "scale": 1.0, "pct": true},
	"life_regen": {"prefix": false, "stat": "life_regen", "mod": F, "text": "{v} Life Regeneration per second", "scale": 0.12, "dec": 1},
	"mana_regen": {"prefix": false, "stat": "mana_regen_inc", "mod": F, "text": "{v}% increased Mana Regeneration Rate", "scale": 1.0, "pct": true},
	"life_kill": {"prefix": false, "stat": "life_on_kill", "mod": F, "text": "Gain {v} Life per enemy killed", "scale": 0.5},
	"mana_kill": {"prefix": false, "stat": "mana_on_kill", "mod": F, "text": "Gain {v} Mana per enemy killed", "scale": 0.5},
	"life_leech": {"prefix": false, "stat": "leech", "mod": F, "text": "Leech {v}% of Damage as Life", "scale": 0.4, "pct": true, "dec": 1},
}

## Tier weights: a family's higher tiers are rarer (PoE2: the best tiers carry a fraction of the weight).
const TIER_WEIGHT_FALLOFF := 0.75
## Family weights by how common they are on gear (PoE2 gives each its own; these follow its spread).
const RARE_FAMILIES := {"life_pct": 40, "mana_pct": 40, "crit_damage": 60, "crit_chance": 70, "crit_chance_inc": 70,
	"life_leech": 40, "life_kill": 70, "mana_kill": 70, "res_all": 50, "all_attr": 60, "elem_pct": 70}

## The tier table's class for a base: the PoE2 item class it uses.
static func class_of(b: ItemBase) -> String:
	match b.slot:
		"ring", "amulet", "belt":
			return b.slot
		"helmet", "shoulders":
			return "helmet"
		"chest":
			return "chest"
		"gloves", "wrists":
			return "gloves"
		"boots", "legs":
			return "boots"
		"offhand":
			return "shield" if b.weapon_type == "shield" else "sword1"
		"weapon":
			match b.weapon_type:
				"dagger", "staff", "bow", "crossbow":
					return b.weapon_type
			return "sword2" if b.two_handed else "sword1"
		"flask":
			return "flask_mana" if String(b.flask.get("kind", "")) == "power" else "flask_life"
	return ""


## The families a base can roll, from its class's table.
static func families_for(b: ItemBase) -> Array:
	var cls := class_of(b)
	if cls == "" or not AffixData.MODS.has(cls):
		return []
	return AffixData.MODS[cls].keys().filter(func(f): return FAMILIES.has(f))


## A family's tiers on a base, lowest first: [[item level, low, high], ...] (PoE2's numbers, unscaled).
static func tiers_for(b: ItemBase, family: String) -> Array:
	var cls := class_of(b)
	if cls == "" or not AffixData.MODS.has(cls):
		return []
	return AffixData.MODS[cls].get(family, [])


## Tiers an item of level `ilvl` can roll: the indices into tiers_for.
static func open_tiers(b: ItemBase, family: String, ilvl: int) -> Array:
	var out := []
	var t := tiers_for(b, family)
	for i in t.size():
		if int(t[i][0]) <= ilvl:
			out.append(i)
	return out


static func is_prefix(family: String) -> bool:
	return bool(FAMILIES[family].prefix)


static func weight_of(family: String) -> int:
	return int(RARE_FAMILIES.get(family, 100))


## The value of a roll (`t`: a tier row, `u`: 0..1 position in its range), scaled to Tainted.
static func roll_value(family: String, t: Array, u: float) -> float:
	var def: Dictionary = FAMILIES[family]
	var raw := lerpf(float(t[1]), float(t[2]), u)
	return round_value(family, raw)


## A raw PoE2 number as the stat's value.
static func round_value(family: String, raw: float) -> float:
	var def: Dictionary = FAMILIES[family]
	var v := raw * float(def.scale)
	if bool(def.get("pct", false)):
		return snappedf(v / 100.0, 0.0001)
	var dec: int = int(def.get("dec", 0))
	return snappedf(v, pow(10.0, -dec)) if dec > 0 else maxf(roundf(v), 1.0)


## The tier whose scaled range is nearest to `value` (for the tier the item shows).
static func tier_of_value(b: ItemBase, family: String, value: float) -> int:
	var t := tiers_for(b, family)
	var best := 0
	var gap := INF
	for i in t.size():
		var lo := round_value(family, float(t[i][1]))
		var hi := round_value(family, float(t[i][2]))
		var g := 0.0 if value >= lo and value <= hi else minf(absf(value - lo), absf(value - hi))
		if g < gap:
			gap = g
			best = i
	return best


## The text of an entry: the family's text with its value, and the 1-based tier counted from the best (T1 best).
static func entry_text(family: String, value: float) -> String:
	var def: Dictionary = FAMILIES[family]
	var shown: String
	if bool(def.get("pct", false)):
		var pv := value * 100.0
		shown = ("%.1f" % pv) if int(def.get("dec", 0)) > 0 else str(int(round(pv)))
	else:
		var dec: int = int(def.get("dec", 0))
		shown = ("%.*f" % [dec, value]) if dec > 0 else str(int(round(value)))
	return String(def.text).replace("{v}", shown)


## Old modifier ids (before the PoE2 rework) and the family each became.
const LEGACY := {
	"life_flat": "life", "life_inc": "life", "dmg_flat": "phys_add", "dmg_inc": "phys_pct", "dmg_more": "phys_pct",
	"atk_speed": "attack_speed", "move_speed": "move_speed", "armor_flat": "armour", "crit": "crit_chance",
	"attr_str": "str", "attr_dex": "dex", "attr_vit": "vit", "attr_ene": "ene",
	"spell_inc": "spell_dmg", "mana_flat": "mana", "mana_regen": "mana_regen", "bow_inc": "phys_pct",
	"res_fire": "res_fire", "res_cold": "res_cold", "res_lightning": "res_lightning", "res_chaos": "res_chaos",
	"res_all": "res_all", "attack_inc": "phys_pct",
}
