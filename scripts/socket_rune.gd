class_name SocketRune
extends RefCounted
## Runes, Diablo II style: socketed into gear like socket gems, each giving one stat -- one on a
## weapon, another on armour (helmets, body armour, gloves, boots, shields, jewellery). Fill a
## Normal item's sockets with the right runes in the right order and it becomes a runeword
## (Runewords).
##
## Ids are "srune_<key>" ("srune_tal"): the support gems already use "rune_" (RuneDef). Owned runes
## share the socket gems' pool (GameState.gems) and their sockets (ItemInstance.gems), so GemDef
## hands rune ids here (GemDef.info, GemDef.icon).
##
## The ladder runs El to Zod. Higher runes are stronger, drop rarer and only from harder rifts
## (random_drop), and are made at the Jeweler from lower ones (COMBINE_COUNT of a rune -> 1 of the
## next).

const PREFIX := "srune_"

const F := StatBlock.ModType.FLAT
const I := StatBlock.ModType.INCREASED

## [key, name, weapon stat, armour stat]; a stat is [stat, mod, value]. Ladder order, El first.
const LADDER := [
	["el", "El", ["damage", F, 3.0], ["armor", F, 10.0]],
	["eld", "Eld", ["crit_chance", F, 0.01], ["move_speed", I, 0.03]],
	["tir", "Tir", ["max_life", F, 10.0], ["max_life", F, 10.0]],
	["nef", "Nef", ["attack_speed", I, 0.04], ["armor", F, 15.0]],
	["eth", "Eth", ["damage", F, 5.0], ["armor", I, 0.08]],
	["ith", "Ith", ["damage", I, 0.06], ["max_life", F, 15.0]],
	["tal", "Tal", ["damage", F, 7.0], ["armor", F, 22.0]],
	["ral", "Ral", ["crit_chance", F, 0.015], ["max_life", I, 0.04]],
	["ort", "Ort", ["attack_speed", I, 0.06], ["armor", F, 28.0]],
	["thul", "Thul", ["damage", F, 9.0], ["max_life", F, 22.0]],
	["amn", "Amn", ["max_life", F, 25.0], ["move_speed", I, 0.05]],
	["sol", "Sol", ["damage", F, 12.0], ["armor", F, 40.0]],
	["shael", "Shael", ["attack_speed", I, 0.08], ["attack_speed", I, 0.05]],
	["dol", "Dol", ["crit_chance", F, 0.02], ["max_life", F, 30.0]],
	["hel", "Hel", ["attack_speed", I, 0.09], ["move_speed", I, 0.05]],
	["io", "Io", ["damage", I, 0.10], ["armor", I, 0.12]],
	["lum", "Lum", ["max_life", F, 35.0], ["max_life", I, 0.06]],
	["ko", "Ko", ["attack_speed", I, 0.10], ["move_speed", I, 0.06]],
	["fal", "Fal", ["damage", F, 16.0], ["armor", F, 60.0]],
	["lem", "Lem", ["crit_chance", F, 0.025], ["max_life", F, 40.0]],
	["pul", "Pul", ["damage", I, 0.14], ["armor", I, 0.16]],
	["um", "Um", ["damage", F, 20.0], ["max_life", F, 50.0]],
	["mal", "Mal", ["attack_speed", I, 0.12], ["armor", F, 80.0]],
	["ist", "Ist", ["crit_chance", F, 0.03], ["move_speed", I, 0.08]],
	["gul", "Gul", ["damage", I, 0.18], ["max_life", I, 0.08]],
	["vex", "Vex", ["max_life", F, 60.0], ["armor", F, 100.0]],
	["ohm", "Ohm", ["damage", F, 28.0], ["max_life", F, 65.0]],
	["lo", "Lo", ["crit_chance", F, 0.04], ["armor", I, 0.20]],
	["sur", "Sur", ["attack_speed", I, 0.15], ["max_life", I, 0.10]],
	["ber", "Ber", ["damage", I, 0.24], ["max_life", F, 85.0]],
	["jah", "Jah", ["damage", F, 36.0], ["max_life", I, 0.12]],
	["cham", "Cham", ["crit_chance", F, 0.05], ["armor", F, 140.0]],
	["zod", "Zod", ["damage", I, 0.30], ["max_life", F, 110.0]],
]

const LABELS := {
	"damage": "Damage", "armor": "Armor", "max_life": "Max Life", "attack_speed": "Attack Speed",
	"crit_chance": "Critical Chance", "move_speed": "Move Speed",
}
const PCT_STATS := ["attack_speed", "crit_chance", "move_speed"]

## Runes of this rank and below combine 3 into 1 of the next; higher ones 2 into 1.
const CHEAP_COMBINE_UPTO := 20

## Highest rank a rift of level 1 drops; each level above opens RANKS_PER_LEVEL more.
const BASE_DROP_RANK := 8
const RANKS_PER_LEVEL := 2
## Each rank up is this much rarer than the one below it.
const RANK_FALLOFF := 0.78


static func is_rune(id: String) -> bool:
	return id.begins_with(PREFIX)


static func id_of(key: String) -> String:
	return PREFIX + key


static func key_of(id: String) -> String:
	return id.substr(PREFIX.length())


## 1 (El) .. 33 (Zod); 0 for an unknown id.
static func rank_of(id: String) -> int:
	var key := key_of(id)
	for i in LADDER.size():
		if LADDER[i][0] == key:
			return i + 1
	return 0


static func id_at(rank: int) -> String:
	return id_of(LADDER[clampi(rank, 1, LADDER.size()) - 1][0]) if rank >= 1 and rank <= LADDER.size() else ""


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for r in LADDER:
		ids.append(id_of(r[0]))
	return ids


## Whether a socket in an item of this slot takes a rune's weapon stat (otherwise its armour stat).
static func weapon_slot(slot: String) -> bool:
	return slot == "weapon"


## Low runes tan, middle ones orange, high ones deep red-gold.
static func color_of(rank: int) -> Color:
	if rank <= 11:
		return Color(0.82, 0.72, 0.55)
	if rank <= 22:
		return Color(1.0, 0.62, 0.22)
	return Color(1.0, 0.35, 0.25)


static func stat_text(s: Array) -> String:
	var label: String = LABELS.get(String(s[0]), String(s[0]).capitalize())
	var v := float(s[2])
	if PCT_STATS.has(String(s[0])) or int(s[1]) == I:
		var pre := "+" if int(s[1]) == F else ""
		var inc := " Increased" if int(s[1]) == I else ""
		return "%s%s%%%s %s" % [pre, _pct(v), inc, label]
	return "+%d %s" % [int(v), label]


static func _pct(v: float) -> String:
	var p := v * 100.0
	return str(int(round(p))) if is_equal_approx(p, round(p)) else "%.1f" % p


## A rune as a socket gem (GemDef.info's shape), for the socket it is in: `slot` picks the
## weapon or armour stat; "" describes both. {} for an unknown id.
static func info(id: String, slot: String = "") -> Dictionary:
	var rank := rank_of(id)
	if rank == 0:
		return {}
	var r: Array = LADDER[rank - 1]
	var weapon: Array = r[2]
	var armour: Array = r[3]
	var s: Array = weapon if weapon_slot(slot) else armour
	var text := stat_text(s) if slot != "" else "Weapon: %s  •  Armour: %s" % [stat_text(weapon), stat_text(armour)]
	return {
		"id": id, "type": "rune", "tier": rank, "rune": true, "key": r[0],
		"name": "%s Rune" % r[1], "short": String(r[1]),
		"stat": s[0], "mod": s[1], "value": s[2], "color": color_of(rank), "text": text,
		"weapon_text": stat_text(weapon), "armour_text": stat_text(armour),
	}


## Its painted stone (assets/icons/runes/<rank>.png, tools/import_gems_runes.py), or a drawn one.
static func icon(id: String) -> Texture2D:
	var rank := rank_of(id)
	if rank <= 0:
		return null
	var path := "res://assets/icons/runes/%d.png" % rank
	return load(path) if ResourceLoader.exists(path) else IconFactory.socket_rune_icon(id, color_of(rank))


# ---------- combining (Jeweler) ----------

## Runes needed to make one of the next rank.
static func combine_count(id: String) -> int:
	return 3 if rank_of(id) <= CHEAP_COMBINE_UPTO else 2


## The rune one rank up, or "" at Zod.
static func next_id(id: String) -> String:
	var rank := rank_of(id)
	return id_at(rank + 1) if rank > 0 and rank < LADDER.size() else ""


## Orbs the Jeweler charges for one combine of this rune.
static func combine_cost(id: String) -> Dictionary:
	var rank := rank_of(id)
	if rank <= 6:
		return {"transmute": 1}
	if rank <= 11:
		return {"alteration": 1}
	if rank <= 16:
		return {"alteration": 3}
	if rank <= 21:
		return {"alchemy": 1}
	if rank <= 26:
		return {"chaos": 1}
	return {"chaos": 3}


# ---------- drops ----------

## Highest rank a rift of this level can drop.
static func max_drop_rank(rift_level: int) -> int:
	return clampi(BASE_DROP_RANK + RANKS_PER_LEVEL * (rift_level - 1), BASE_DROP_RANK, LADDER.size())


## A random rune for a rift of this level: low runes common, each rank up RANK_FALLOFF as likely.
## `boost` shifts the roll up that many ranks (bosses), still within what the level can drop.
static func random_drop(rift_level: int = 1, boost: int = 0) -> String:
	var top := max_drop_rank(rift_level)
	var total := 0.0
	for r in top:
		total += pow(RANK_FALLOFF, r)
	var roll := randf() * total
	var rank := 1
	for r in top:
		roll -= pow(RANK_FALLOFF, r)
		if roll <= 0.0:
			rank = r + 1
			break
	return id_at(mini(rank + boost, top))
