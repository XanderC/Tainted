class_name UniqueItems
extends RefCounted
## Legendary and Set items (Diablo style). Each has a fixed name and base item; it still rolls
## random affixes like a Rare, plus:
##   Legendary - a legendary power (values rolled inside a range, better at higher item level)
##   Set       - membership of a set; wearing several pieces of one set grants its bonuses
## Powers and set bonuses use the passive stat keys (see PassiveTree.stat_text), summed into
## GameState.passive_value through Player.item_powers, plus per-skill keys:
##   "skill_dmg:<skill id>"  more damage with that skill (0.5 = +50%)
##   "skill_cdr:<skill id>"  shorter cooldown (0.3 = -30%)
##   "skill_dur:<skill id>"  longer duration (0.5 = +50%)

## id -> {name, base, power: {key: [min, max]}, flavor}
const LEGENDARIES := {
	"maelstrom_edge": {"name": "Maelstrom Edge", "base": "greatsword",
		"power": {"skill_dmg:whirlwind": [0.6, 1.0]}, "flavor": "The storm never stops turning."},
	"skybreaker": {"name": "Skybreaker", "base": "war_maul",
		"power": {"skill_dmg:leap_slam": [0.4, 0.7], "skill_cdr:leap_slam": [0.25, 0.4]}, "flavor": "What falls from the sky does not get up."},
	"bloodthirst_cleaver": {"name": "Bloodthirst Cleaver", "base": "hand_axe",
		"power": {"leech": [0.03, 0.05]}, "flavor": "It drinks first."},
	"executioners_due": {"name": "Executioner's Due", "base": "battle_axe",
		"power": {"execute": [0.4, 0.7]}, "flavor": "Every debt is collected."},
	"fury_of_the_ancients": {"name": "Fury of the Ancients", "base": "rusty_sword",
		"power": {"skill_dmg:ancients": [0.5, 0.8], "skill_dur:ancients": [0.4, 0.7]}, "flavor": "The old ones answer louder."},
	"earthshaker": {"name": "Earthshaker", "base": "iron_mace",
		"power": {"skill_dmg:earthquake": [0.6, 1.0], "skill_dmg:ground_stomp": [0.6, 1.0]}, "flavor": "The ground remembers every blow."},
	"crown_of_wrath": {"name": "Crown of Wrath", "base": "iron_helm",
		"power": {"power_max": [20.0, 35.0], "damage_inc": [0.06, 0.10]}, "flavor": "Rage, worn like a halo."},
	"martyrs_thornmail": {"name": "Martyr's Thornmail", "base": "chain_mail",
		"power": {"thorns": [40.0, 80.0], "armor_inc": [0.10, 0.20]}, "flavor": "Every wound is returned."},
	"hasteful_grips": {"name": "Hasteful Grips", "base": "leather_gloves",
		"power": {"attack_speed_inc": [0.10, 0.18]}, "flavor": "Faster than the eye, faster than fear."},
	"windstriders": {"name": "Windstriders", "base": "worn_boots",
		"power": {"move_inc": [0.15, 0.25]}, "flavor": "Never caught, never cornered."},
	"bulwark_of_the_unbroken": {"name": "Bulwark of the Unbroken", "base": "tower_shield",
		"power": {"armor_inc": [0.30, 0.50], "regen": [2.0, 4.0]}, "flavor": "It has never been breached."},
	"band_of_echoes": {"name": "Band of Echoes", "base": "bone_ring",
		"power": {"gem_level": [1.0, 1.0]}, "flavor": "Every skill rings twice as true."},
	"frugal_signet": {"name": "Frugal Signet", "base": "bone_ring",
		"power": {"cost_red": [0.15, 0.25]}, "flavor": "Waste nothing, not even fury."},
	"eye_of_carnage": {"name": "Eye of Carnage", "base": "old_amulet",
		"power": {"rampage": [0.20, 0.40]}, "flavor": "It sees only what is about to burst."},
}

## set id -> {name, pieces: [item ids], bonuses: {pieces needed: {key: value}}}
const SETS := {
	"ashen_warlord": {"name": "Ashen Warlord's Regalia",
		"pieces": ["warlord_visage", "warlord_hauberk", "warlord_grips", "warlord_treads", "warlord_maul"],
		"bonuses": {
			2: {"armor_inc": 0.20, "life_flat": 40.0},
			3: {"damage_inc": 0.20, "attack_speed_inc": 0.08},
			5: {"skill_dmg:leap_slam": 1.5, "skill_dmg:earthquake": 1.5, "skill_cdr:leap_slam": 0.4},
		}},
	"bloodsworn": {"name": "Bloodsworn Battlegear",
		"pieces": ["bloodsworn_mask", "bloodsworn_vest", "bloodsworn_band", "bloodsworn_hatchet"],
		"bonuses": {
			2: {"leech": 0.03, "attack_speed_inc": 0.12},
			3: {"power_max": 25.0, "no_decay": 1.0},
			4: {"skill_dmg:whirlwind": 1.5, "skill_dmg:frenzy": 1.0, "cost_red": 0.15},
		}},
	"ancestors_oath": {"name": "Ancestors' Oath",
		"pieces": ["oath_of_elders", "ancestral_shield", "ancestral_boots"],
		"bonuses": {
			2: {"gem_level": 1.0, "life_inc": 0.08},
			3: {"skill_dmg:ancients": 1.0, "skill_dur:ancients": 0.5},
		}},
}

## set piece id -> {name, base, set}
const SET_ITEMS := {
	"warlord_visage": {"name": "Warlord's Visage", "base": "iron_helm", "set": "ashen_warlord"},
	"warlord_hauberk": {"name": "Warlord's Hauberk", "base": "chain_mail", "set": "ashen_warlord"},
	"warlord_grips": {"name": "Warlord's Grips", "base": "leather_gloves", "set": "ashen_warlord"},
	"warlord_treads": {"name": "Warlord's Treads", "base": "worn_boots", "set": "ashen_warlord"},
	"warlord_maul": {"name": "Warlord's Maul", "base": "war_maul", "set": "ashen_warlord"},
	"bloodsworn_mask": {"name": "Bloodsworn Mask", "base": "leather_cap", "set": "bloodsworn"},
	"bloodsworn_vest": {"name": "Bloodsworn Vest", "base": "padded_vest", "set": "bloodsworn"},
	"bloodsworn_band": {"name": "Bloodsworn Band", "base": "bone_ring", "set": "bloodsworn"},
	"bloodsworn_hatchet": {"name": "Bloodsworn Hatchet", "base": "hand_axe", "set": "bloodsworn"},
	"oath_of_elders": {"name": "Oath of the Elders", "base": "old_amulet", "set": "ancestors_oath"},
	"ancestral_shield": {"name": "Shield of the Forefathers", "base": "wooden_shield", "set": "ancestors_oath"},
	"ancestral_boots": {"name": "Treads of the Forefathers", "base": "worn_boots", "set": "ancestors_oath"},
}

const LEGENDARY_AFFIXES := [3, 4]
const SET_AFFIXES := [2, 3]


## A random Legendary (or Set item when `set_item`), preferring ones the class can use.
## Returns null if nothing fits.
static func roll(ilvl: int, set_item: bool, cls: ClassDef = null) -> ItemInstance:
	var table: Dictionary = SET_ITEMS if set_item else LEGENDARIES
	var ids: Array = table.keys()
	if cls != null:
		var usable := ids.filter(func(id): return _usable(String(table[id].base), cls))
		if not usable.is_empty():
			ids = usable
	return make(String(ids.pick_random()), ilvl) if not ids.is_empty() else null


static func _usable(base_id: String, cls: ClassDef) -> bool:
	var b := LootGenerator.base_by_id(base_id)
	return b != null and (b.weapon_type == "" or cls.weapon_types.has(b.weapon_type))


## A freshly rolled copy of one Legendary / Set item.
static func make(uid: String, ilvl: int) -> ItemInstance:
	var info := info_of(uid)
	if info.is_empty():
		return null
	var b := LootGenerator.base_by_id(String(info.base))
	if b == null:
		return null
	var it := ItemInstance.new()
	it.base = b
	it.ilvl = ilvl
	it.unique_id = uid
	it.display_name = String(info.name)
	var legendary := LEGENDARIES.has(uid)
	it.rarity = ItemInstance.Rarity.LEGENDARY if legendary else ItemInstance.Rarity.SET
	var n: Array = LEGENDARY_AFFIXES if legendary else SET_AFFIXES
	LootGenerator.roll_affixes(it, randi_range(int(n[0]), int(n[1])))
	it.implicit_roll = ItemInstance.roll_implicit()
	if legendary:
		reroll_powers(it)
	it.sockets = ItemInstance.roll_sockets(b.slot, it.rarity)
	return it


## Rolls a Legendary's power values inside their ranges (on drop, and by a Divine Orb).
static func reroll_powers(it: ItemInstance) -> void:
	var info: Dictionary = LEGENDARIES.get(it.unique_id, {})
	for k in info.get("power", {}):
		var r: Array = info.power[k]
		var v := lerpf(float(r[0]), float(r[1]), ItemInstance.ilvl_roll(it.ilvl))
		it.powers[k] = roundf(v) if absf(float(r[1])) >= 2.0 else snappedf(v, 0.01)


## A Legendary / Set item of this base, or "" if there is none.
static func unique_for_base(base_id: String, set_item: bool) -> String:
	var table: Dictionary = SET_ITEMS if set_item else LEGENDARIES
	var ids := table.keys().filter(func(id): return String(table[id].base) == base_id)
	return String(ids.pick_random()) if not ids.is_empty() else ""


static func info_of(uid: String) -> Dictionary:
	if LEGENDARIES.has(uid):
		return LEGENDARIES[uid]
	return SET_ITEMS.get(uid, {})


static func set_of(uid: String) -> String:
	return String(SET_ITEMS.get(uid, {}).get("set", ""))


## How many different pieces of each set are in `items` (set id -> count).
static func set_counts(items: Array) -> Dictionary:
	var seen := {}
	var out := {}
	for it in items:
		if it == null or it.unique_id == "" or seen.has(it.unique_id):
			continue
		var s := set_of(it.unique_id)
		if s != "":
			seen[it.unique_id] = true
			out[s] = int(out.get(s, 0)) + 1
	return out


## Power totals from worn items: legendary powers + every set bonus reached.
static func powers_of(items: Array) -> Dictionary:
	var out := {}
	for it in items:
		if it != null:
			for k in it.powers:
				out[k] = float(out.get(k, 0.0)) + float(it.powers[k])
	var counts := set_counts(items)
	for s in counts:
		var bonuses: Dictionary = SETS[s].bonuses
		for need in bonuses:
			if int(counts[s]) >= int(need):
				for k in bonuses[need]:
					out[k] = float(out.get(k, 0.0)) + float(bonuses[need][k])
	return out


## BBCode for an item card: the legendary power, or the set's pieces and bonuses
## (`worn` = items the player wears, to show which pieces / bonuses are active).
static func card_bbcode(item: ItemInstance, worn: Array) -> String:
	if item.unique_id == "":
		return ""
	var t := ""
	var info := info_of(item.unique_id)
	if item.rarity == ItemInstance.Rarity.LEGENDARY:
		t += "[color=#ff9a3c]✦ %s[/color]\n" % PassiveTree.stat_text(item.powers)
		if info.has("flavor"):
			t += "[color=#a8865c][i]%s[/i][/color]\n" % info.flavor
		return t
	var sid := set_of(item.unique_id)
	if sid == "":
		return ""
	var sdef: Dictionary = SETS[sid]
	var have := int(set_counts(worn).get(sid, 0))
	var worn_ids := worn.filter(func(x): return x != null).map(func(x): return x.unique_id)
	t += "[color=#4ade80]%s  (%d / %d)[/color]\n" % [sdef.name, have, sdef.pieces.size()]
	for p in sdef.pieces:
		var on: bool = worn_ids.has(p)
		t += "[color=#%s]  %s %s[/color]\n" % ["4ade80" if on else "667066", "●" if on else "○", SET_ITEMS[p].name]
	for need in sdef.bonuses:
		var active: bool = int(have) >= int(need)
		t += "[color=#%s](%d) %s[/color]\n" % ["4ade80" if active else "6b7280", int(need), PassiveTree.stat_text(sdef.bonuses[need])]
	return t
