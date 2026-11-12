class_name AffixDB
extends RefCounted
## Item modifiers the way Path of Exile 2 has them: every modifier belongs to a family (one per item), is a
## prefix or a suffix, and has tiers, each needing a minimum item level and rolling inside its own range.
## The tier tables are PoE2's own (AffixData, made by tools/import_poe2_mods.py from poe2db.tw); this file says
## what each family does in Tainted, and how far PoE2's numbers are scaled to Tainted's smaller life and damage.
##
## A family is {prefix, stat, mod, text, scale, pct}. The scales were calibrated (scratch/measure_power.gd, measure_sums.gd) so that
## a full Rare set gives about what the old modifiers did at the item levels Act I drops at (3 to 14): damage and effective life within
## a few percent at item levels 10 to 14, so the pacing tuned for it still holds. Percentage modifiers show PoE2's own numbers
## (x1 to x2); flat ones are bigger than PoE2's because Tainted's characters are smaller than its.
##   text    "{v}" is the rolled value;
##   scale   PoE2's numbers x this (Tainted's characters have about 140 Life, not 1500);
##   pct     the numbers are percentages and the stat is a fraction (the stat's value is the roll / 100).

const F := StatBlock.ModType.FLAT
const I := StatBlock.ModType.INCREASED

const FAMILIES := {
	# Prefixes
	"life": {"prefix": true, "stat": "max_life", "mod": F, "text": "+{v} to maximum Life", "scale": 3.9},
	"mana": {"prefix": true, "stat": "mana_max", "mod": F, "text": "+{v} to maximum Mana", "scale": 2.1},
	"life_pct": {"prefix": true, "stat": "max_life", "mod": I, "text": "{v}% increased maximum Life", "scale": 1.0, "pct": true},
	"mana_pct": {"prefix": true, "stat": "mana_max", "mod": I, "text": "{v}% increased maximum Mana", "scale": 1.0, "pct": true},
	"armour": {"prefix": true, "stat": "armor", "mod": F, "text": "+{v} to Armour", "scale": 0.7},
	"armour_pct": {"prefix": true, "stat": "armor", "mod": I, "text": "{v}% increased Armour", "scale": 1.0, "pct": true},
	"phys_add": {"prefix": true, "grow": true, "stat": "damage", "mod": F, "text": "Adds {v} Physical Damage", "scale": 39.0},
	"fire_add": {"prefix": true, "grow": true, "stat": "dmg_fire", "mod": F, "text": "Adds {v} Fire Damage", "scale": 19.2},
	"cold_add": {"prefix": true, "grow": true, "stat": "dmg_cold", "mod": F, "text": "Adds {v} Cold Damage", "scale": 19.2},
	"lightning_add": {"prefix": true, "grow": true, "stat": "dmg_lightning", "mod": F, "text": "Adds {v} Lightning Damage", "scale": 19.2},
	"phys_pct": {"prefix": true, "grow": true, "stat": "damage", "mod": I, "text": "{v}% increased Damage", "scale": 2.0, "pct": true},
	"elem_pct": {"prefix": true, "grow": true, "stat": "ele_inc", "mod": F, "text": "{v}% increased Elemental Damage", "scale": 1.9, "pct": true},
	"fire_pct": {"prefix": true, "grow": true, "stat": "fire_inc", "mod": F, "text": "{v}% increased Fire Damage", "scale": 1.6, "pct": true},
	"cold_pct": {"prefix": true, "grow": true, "stat": "cold_inc", "mod": F, "text": "{v}% increased Cold Damage", "scale": 1.6, "pct": true},
	"lightning_pct": {"prefix": true, "grow": true, "stat": "lightning_inc", "mod": F, "text": "{v}% increased Lightning Damage", "scale": 1.6, "pct": true},
	"chaos_pct": {"prefix": true, "grow": true, "stat": "chaos_inc", "mod": F, "text": "{v}% increased Chaos Damage", "scale": 1.6, "pct": true},
	"spell_dmg": {"prefix": true, "grow": true, "stat": "spell_inc", "mod": F, "text": "{v}% increased Spell Damage", "scale": 1.9, "pct": true},
	"move_speed": {"prefix": true, "stat": "move_speed", "mod": I, "text": "{v}% increased Movement Speed", "scale": 1.5, "pct": true},
	# Suffixes
	"str": {"prefix": false, "stat": "str", "mod": F, "text": "+{v} to Strength", "scale": 4.9},
	"dex": {"prefix": false, "stat": "dex", "mod": F, "text": "+{v} to Dexterity", "scale": 4.9},
	"vit": {"prefix": false, "stat": "vit", "mod": F, "text": "+{v} to Vitality", "scale": 3.4},
	"ene": {"prefix": false, "stat": "ene", "mod": F, "text": "+{v} to Energy", "scale": 3.8},
	"all_attr": {"prefix": false, "stat": "all_attr", "mod": F, "text": "+{v} to all Attributes", "scale": 4.2},
	"res_fire": {"prefix": false, "stat": "res_fire", "mod": F, "text": "+{v}% to Fire Resistance", "scale": 1.7, "pct": true},
	"res_cold": {"prefix": false, "stat": "res_cold", "mod": F, "text": "+{v}% to Cold Resistance", "scale": 1.7, "pct": true},
	"res_lightning": {"prefix": false, "stat": "res_lightning", "mod": F, "text": "+{v}% to Lightning Resistance", "scale": 1.7, "pct": true},
	"res_chaos": {"prefix": false, "stat": "res_chaos", "mod": F, "text": "+{v}% to Chaos Resistance", "scale": 1.7, "pct": true},
	"res_all": {"prefix": false, "stat": "res_all", "mod": F, "text": "+{v}% to all Elemental Resistances", "scale": 1.7, "pct": true},
	"attack_speed": {"prefix": false, "stat": "attack_speed", "mod": I, "text": "{v}% increased Attack Speed", "scale": 2.55, "pct": true},
	"cast_speed": {"prefix": false, "stat": "attack_speed", "mod": I, "text": "{v}% increased Cast Speed", "scale": 2.55, "pct": true},
	"crit_chance": {"prefix": false, "stat": "crit_chance", "mod": F, "text": "+{v}% to Critical Hit Chance", "scale": 8.8, "pct": true},
	"crit_chance_inc": {"prefix": false, "stat": "crit_chance", "mod": I, "text": "{v}% increased Critical Hit Chance", "scale": 3.2, "pct": true},
	"crit_damage": {"prefix": false, "stat": "crit_damage", "mod": F, "text": "+{v}% to Critical Damage Bonus", "scale": 2.0, "pct": true},
	"life_regen": {"prefix": false, "stat": "life_regen", "mod": F, "text": "{v} Life Regeneration per second", "scale": 0.12, "dec": 1},
	"mana_regen": {"prefix": false, "stat": "mana_regen_inc", "mod": F, "text": "{v}% increased Mana Regeneration Rate", "scale": 1.0, "pct": true},
	"life_kill": {"prefix": false, "stat": "life_on_kill", "mod": F, "text": "Gain {v} Life per enemy killed", "scale": 0.5},
	"mana_kill": {"prefix": false, "stat": "mana_on_kill", "mod": F, "text": "Gain {v} Mana per enemy killed", "scale": 0.5},
	"life_leech": {"prefix": false, "stat": "leech", "mod": F, "text": "Leech {v}% of Damage as Life", "scale": 0.4, "pct": true, "dec": 1},
	# Defences and the rest of what Path of Exile 2 gives gear (Player reads these stats)
	"evasion": {"prefix": true, "stat": "evasion", "mod": F, "text": "+{v} to Evasion Rating", "scale": 0.7},
	"evasion_pct": {"prefix": true, "stat": "evasion", "mod": I, "text": "{v}% increased Evasion Rating", "scale": 1.0, "pct": true},
	"es": {"prefix": true, "stat": "energy_shield", "mod": F, "text": "+{v} to maximum Energy Shield", "scale": 2.8},
	"es_pct": {"prefix": true, "stat": "energy_shield", "mod": I, "text": "{v}% increased maximum Energy Shield", "scale": 1.0, "pct": true},
	"thorns": {"prefix": true, "stat": "thorns", "mod": F, "text": "{v} Physical Thorns damage", "scale": 0.4},
	"rarity_prefix": {"prefix": true, "stat": "item_rarity", "mod": F, "text": "{v}% increased Rarity of Items found", "scale": 1.0, "pct": true},
	"block": {"prefix": true, "stat": "block", "mod": F, "text": "+{v}% Block chance", "scale": 0.8, "pct": true},
	"rarity": {"prefix": false, "stat": "item_rarity", "mod": F, "text": "{v}% increased Rarity of Items found", "scale": 1.0, "pct": true},
	"stun_threshold": {"prefix": false, "stat": "stun_threshold", "mod": F, "text": "+{v} to Stun Threshold", "scale": 0.3},
	"max_fire": {"prefix": false, "stat": "max_res_fire", "mod": F, "text": "+{v}% to Maximum Fire Resistance", "scale": 1.0, "pct": true},
	"max_cold": {"prefix": false, "stat": "max_res_cold", "mod": F, "text": "+{v}% to Maximum Cold Resistance", "scale": 1.0, "pct": true},
	"max_lightning": {"prefix": false, "stat": "max_res_lightning", "mod": F, "text": "+{v}% to Maximum Lightning Resistance", "scale": 1.0, "pct": true},
	"max_chaos": {"prefix": false, "stat": "max_res_chaos", "mod": F, "text": "+{v}% to Maximum Chaos Resistance", "scale": 1.0, "pct": true},
	"max_res": {"prefix": false, "stat": "max_res_all", "mod": F, "text": "+{v}% to all Maximum Elemental Resistances", "scale": 1.0, "pct": true},
	"life_hit": {"prefix": false, "stat": "life_on_hit", "mod": F, "text": "Gain {v} Life per Enemy Hit", "scale": 0.5},
	"mana_leech": {"prefix": false, "stat": "mana_leech", "mod": F, "text": "Leech {v}% of Damage as Mana", "scale": 0.4, "pct": true, "dec": 1},
	"recoup_life": {"prefix": false, "stat": "recoup_life", "mod": F, "text": "{v}% of Damage taken Recouped as Life", "scale": 1.0, "pct": true},
	"recoup_mana": {"prefix": false, "stat": "recoup_mana", "mod": F, "text": "{v}% of Damage taken Recouped as Mana", "scale": 1.0, "pct": true},
	"ail_bleed": {"prefix": false, "stat": "ail_bleed", "mod": F, "text": "{v}% reduced Duration of Bleeding on You", "scale": 1.0, "pct": true},
	"ail_poison": {"prefix": false, "stat": "ail_poison", "mod": F, "text": "{v}% reduced Poison Duration on you", "scale": 1.0, "pct": true},
	"ail_ignite": {"prefix": false, "stat": "ail_ignite", "mod": F, "text": "{v}% reduced Ignite Duration on you", "scale": 1.0, "pct": true},
	"ail_shock": {"prefix": false, "stat": "ail_shock", "mod": F, "text": "{v}% reduced Shock duration on you", "scale": 1.0, "pct": true},
	"ail_freeze": {"prefix": false, "stat": "ail_freeze", "mod": F, "text": "{v}% reduced Freeze Duration on you", "scale": 1.0, "pct": true},
	# Accuracy, Spirit, skill levels and the hybrid modifiers (two stats in one)
	"accuracy": {"prefix": true, "stat": "accuracy", "mod": F, "text": "+{v} to Accuracy Rating", "scale": 0.5},
	"spirit": {"prefix": true, "stat": "spirit", "mod": F, "text": "+{v} to Spirit", "scale": 1.0},
	"lvl_melee": {"prefix": false, "stat": "lvl_melee", "mod": F, "text": "+{v} to Level of all Melee Skills", "scale": 1.0},
	"lvl_projectile": {"prefix": false, "stat": "lvl_projectile", "mod": F, "text": "+{v} to Level of all Projectile Skills", "scale": 1.0},
	"lvl_spell": {"prefix": false, "stat": "lvl_spell", "mod": F, "text": "+{v} to Level of all Spell Skills", "scale": 1.0},
	"lvl_fire": {"prefix": false, "stat": "lvl_fire", "mod": F, "text": "+{v} to Level of all Fire Spell Skills", "scale": 1.0},
	"lvl_cold": {"prefix": false, "stat": "lvl_cold", "mod": F, "text": "+{v} to Level of all Cold Spell Skills", "scale": 1.0},
	"lvl_lightning": {"prefix": false, "stat": "lvl_lightning", "mod": F, "text": "+{v} to Level of all Lightning Spell Skills", "scale": 1.0},
	"lvl_chaos": {"prefix": false, "stat": "lvl_chaos", "mod": F, "text": "+{v} to Level of all Chaos Spell Skills", "scale": 1.0},
	"lvl_phys_spell": {"prefix": false, "stat": "lvl_phys_spell", "mod": F, "text": "+{v} to Level of all Physical Spell Skills", "scale": 1.0},
	"armour_pct_life": {"prefix": true, "stat": "armor", "mod": I, "text": "{v}% increased Armour", "scale": 1.0, "pct": true, "second": {"stat": "max_life", "mod": F, "text": "+{v2} to maximum Life", "scale": 3.9}},
	"armour_pct_mana": {"prefix": true, "stat": "armor", "mod": I, "text": "{v}% increased Armour", "scale": 1.0, "pct": true, "second": {"stat": "mana_max", "mod": F, "text": "+{v2} to maximum Mana", "scale": 2.1}},
	"armour_pct_stun": {"prefix": true, "stat": "armor", "mod": I, "text": "{v}% increased Armour", "scale": 1.0, "pct": true, "second": {"stat": "stun_threshold", "mod": F, "text": "+{v2} to Stun Threshold", "scale": 0.3}},
	"armour_flat_pct": {"prefix": true, "stat": "armor", "mod": F, "text": "+{v} to Armour", "scale": 0.7, "second": {"stat": "armor", "mod": I, "text": "{v2}% increased Armour", "scale": 1.0, "pct": true}},
	"evasion_pct_life": {"prefix": true, "stat": "evasion", "mod": I, "text": "{v}% increased Evasion Rating", "scale": 1.0, "pct": true, "second": {"stat": "max_life", "mod": F, "text": "+{v2} to maximum Life", "scale": 3.9}},
	"evasion_pct_mana": {"prefix": true, "stat": "evasion", "mod": I, "text": "{v}% increased Evasion Rating", "scale": 1.0, "pct": true, "second": {"stat": "mana_max", "mod": F, "text": "+{v2} to maximum Mana", "scale": 2.1}},
	"evasion_pct_stun": {"prefix": true, "stat": "evasion", "mod": I, "text": "{v}% increased Evasion Rating", "scale": 1.0, "pct": true, "second": {"stat": "stun_threshold", "mod": F, "text": "+{v2} to Stun Threshold", "scale": 0.3}},
	"evasion_flat_pct": {"prefix": true, "stat": "evasion", "mod": F, "text": "+{v} to Evasion Rating", "scale": 0.7, "second": {"stat": "evasion", "mod": I, "text": "{v2}% increased Evasion Rating", "scale": 1.0, "pct": true}},
	"es_pct_life": {"prefix": true, "stat": "energy_shield", "mod": I, "text": "{v}% increased maximum Energy Shield", "scale": 1.0, "pct": true, "second": {"stat": "max_life", "mod": F, "text": "+{v2} to maximum Life", "scale": 3.9}},
	"es_pct_mana": {"prefix": true, "stat": "energy_shield", "mod": I, "text": "{v}% increased maximum Energy Shield", "scale": 1.0, "pct": true, "second": {"stat": "mana_max", "mod": F, "text": "+{v2} to maximum Mana", "scale": 2.1}},
	"es_pct_stun": {"prefix": true, "stat": "energy_shield", "mod": I, "text": "{v}% increased maximum Energy Shield", "scale": 1.0, "pct": true, "second": {"stat": "stun_threshold", "mod": F, "text": "+{v2} to Stun Threshold", "scale": 0.3}},
	"es_flat_pct": {"prefix": true, "stat": "energy_shield", "mod": F, "text": "+{v} to maximum Energy Shield", "scale": 2.8, "second": {"stat": "energy_shield", "mod": I, "text": "{v2}% increased maximum Energy Shield", "scale": 1.0, "pct": true}},
	"spell_mana": {"prefix": true, "grow": true, "stat": "spell_inc", "mod": F, "text": "{v}% increased Spell Damage", "scale": 1.7, "pct": true, "second": {"stat": "mana_max", "mod": F, "text": "+{v2} to maximum Mana", "scale": 2.1}},
	"phys_acc": {"prefix": true, "grow": true, "stat": "damage", "mod": I, "text": "{v}% increased Damage", "scale": 1.7, "pct": true, "second": {"stat": "accuracy", "mod": F, "text": "+{v2} to Accuracy Rating", "scale": 0.5}},
	# Flasks (the stats are read by ItemInstance.flask_effect, not worn)
	"flask_amount": {"prefix": true, "stat": "flask_amount", "mod": F, "text": "{v}% increased Amount Recovered", "scale": 1.0, "pct": true},
	"flask_speed": {"prefix": true, "stat": "flask_speed", "mod": F, "text": "{v}% increased Recovery rate", "scale": 1.0, "pct": true},
	"flask_instant_part": {"prefix": true, "stat": "flask_instant_part", "mod": F, "text": "{v}% of Recovery applied Instantly", "scale": 1.0, "pct": true},
	"flask_used": {"prefix": false, "stat": "flask_used", "mod": F, "text": "{v}% reduced Charges per use", "scale": 1.0, "pct": true},
	"flask_charges": {"prefix": false, "stat": "flask_charges", "mod": F, "text": "{v}% increased Charges", "scale": 1.0, "pct": true},
	"flask_gained": {"prefix": false, "stat": "flask_gained", "mod": F, "text": "{v}% increased Charges gained", "scale": 1.0, "pct": true},
	# Charms and the belt's charm and flask modifiers
	"charm_life": {"prefix": true, "stat": "charm_life", "mod": F, "text": "Recover {v} Life when Used", "scale": 0.5},
	"charm_mana": {"prefix": true, "stat": "charm_mana", "mod": F, "text": "Recover {v} Mana when Used", "scale": 0.5},
	"charm_duration": {"prefix": true, "stat": "charm_duration", "mod": F, "text": "{v}% increased Duration", "scale": 1.0, "pct": true},
	"belt_flask_recovery": {"prefix": true, "stat": "belt_flask_recovery", "mod": F, "text": "{v}% increased Flask Life Recovery rate", "scale": 1.0, "pct": true},
	"belt_charm_duration": {"prefix": true, "stat": "belt_charm_duration", "mod": F, "text": "{v}% increased Charm Effect Duration", "scale": 1.0, "pct": true},
	"belt_charm_gained": {"prefix": false, "stat": "belt_charm_gained", "mod": F, "text": "{v}% increased Charm Charges gained", "scale": 1.0, "pct": true},
	"belt_charm_used": {"prefix": false, "stat": "belt_charm_used", "mod": F, "text": "{v}% reduced Charm Charges used", "scale": 1.0, "pct": true},
	"belt_flask_gained": {"prefix": false, "stat": "belt_flask_gained", "mod": F, "text": "{v}% increased Flask Charges gained", "scale": 1.0, "pct": true},
	"belt_flask_used": {"prefix": false, "stat": "belt_flask_used", "mod": F, "text": "{v}% reduced Flask Charges used", "scale": 1.0, "pct": true},
	"flask_per_second": {"prefix": false, "stat": "flask_per_second", "mod": F, "text": "Gains {v} Charges per Second", "scale": 1.0, "dec": 2},
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
		"charm":
			return "charm"
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
static func roll_value(family: String, t: Array, u: float, ilvl := -1) -> float:
	var raw := lerpf(float(t[1]), float(t[2]), u)
	return round_value(family, raw, ilvl)


## Damage modifiers grow a little with the item's level on top of their tier (the old gear's damage grew with item level, and
## the pacing was tuned for that): x0.6 at item level 1 to x2.2 at 33 and up. `ilvl` -1: no growth (a family's plain scale).
static func growth(family: String, ilvl: int) -> float:
	if ilvl < 0 or not bool(FAMILIES[family].get("grow", false)):
		return 1.0
	return clampf(0.40 + 0.055 * float(ilvl), 0.6, 2.2)


## Whether a family gives two stats (a hybrid modifier: "% increased Armour" and "+ to maximum Life").
static func is_hybrid(family: String) -> bool:
	return FAMILIES[family].has("second")


## A hybrid's second value, rolled in its tier's second range.
static func roll_value2(family: String, t: Array, u: float) -> float:
	return round_value2(family, lerpf(float(t[3]), float(t[4]), u))


static func round_value2(family: String, raw: float) -> float:
	var part: Dictionary = FAMILIES[family].second
	var v := raw * float(part.scale)
	if bool(part.get("pct", false)):
		return snappedf(v / 100.0, 0.0001)
	return maxf(roundf(v), 1.0)


## Tooling only: AFFIX_SCALES="life=2,armour=1.5" multiplies those families' scales (scratch/measure_*.gd, to calibrate them).
static var _override := {}
static var _override_read := false


## A family's scale: its own, times the calibration override if one is set.
static func scale_of(family: String) -> float:
	if not _override_read:
		_override_read = true
		for kv in OS.get_environment("AFFIX_SCALES").split(",", false):
			var parts := kv.split("=")
			if parts.size() == 2:
				_override[parts[0]] = float(parts[1])
	return float(FAMILIES[family].scale) * float(_override.get(family, 1.0))


## A raw PoE2 number as the stat's value.
static func round_value(family: String, raw: float, ilvl := -1) -> float:
	var def: Dictionary = FAMILIES[family]
	var v := raw * scale_of(family) * growth(family, ilvl)
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
static func entry_text(family: String, value: float, value2 := 0.0) -> String:
	var def: Dictionary = FAMILIES[family]
	var shown: String
	if bool(def.get("pct", false)):
		var pv := value * 100.0
		shown = ("%.1f" % pv) if int(def.get("dec", 0)) > 0 else str(int(round(pv)))
	else:
		var dec: int = int(def.get("dec", 0))
		shown = ("%.*f" % [dec, value]) if dec > 0 else str(int(round(value)))
	var text := String(def.text).replace("{v}", shown)
	if def.has("second"):  # a hybrid: its second line
		var part: Dictionary = def.second
		var shown2 := str(int(round(value2 * 100.0))) if bool(part.get("pct", false)) else str(int(round(value2)))
		text += "\n" + String(part.text).replace("{v2}", shown2)
	return text


## Old modifier ids (before the PoE2 rework) and the family each became.
const LEGACY := {
	"life_flat": "life", "life_inc": "life", "dmg_flat": "phys_add", "dmg_inc": "phys_pct", "dmg_more": "phys_pct",
	"atk_speed": "attack_speed", "move_speed": "move_speed", "armor_flat": "armour", "crit": "crit_chance",
	"attr_str": "str", "attr_dex": "dex", "attr_vit": "vit", "attr_ene": "ene",
	"spell_inc": "spell_dmg", "mana_flat": "mana", "mana_regen": "mana_regen", "bow_inc": "phys_pct",
	"res_fire": "res_fire", "res_cold": "res_cold", "res_lightning": "res_lightning", "res_chaos": "res_chaos",
	"res_all": "res_all", "attack_inc": "phys_pct",
	# Flask modifiers from before the flask rework
	"fl_ample": "flask_amount", "fl_seething": "flask_instant_part", "fl_chemist": "flask_gained", "fl_enduring": "flask_speed",
}
