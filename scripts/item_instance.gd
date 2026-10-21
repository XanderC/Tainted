class_name ItemInstance
extends Resource
## A single rolled item: a base + rarity + rolled affixes. Serializable for saves.
## Legendary and Set items (UniqueItems) also carry a unique id; Legendaries have rolled powers.

## RUNEWORD: a Normal item whose sockets hold a runeword's runes (Runewords). Last, so saves keep
## their numbers.
enum Rarity { NORMAL, MAGIC, RARE, LEGENDARY, SET, RUNEWORD }

const RARITY_COLORS := {
	Rarity.NORMAL: Color(0.9, 0.9, 0.9),
	Rarity.MAGIC: Color(0.45, 0.55, 1.0),
	Rarity.RARE: Color(1.0, 0.85, 0.3),
	Rarity.LEGENDARY: Color(1.0, 0.55, 0.15),
	Rarity.SET: Color(0.30, 0.95, 0.40),
	Rarity.RUNEWORD: Color(0.78, 0.70, 0.47),  # Diablo II's runeword gold
}

@export var base: ItemBase
@export var display_name: String = ""
@export var rarity: Rarity = Rarity.NORMAL
@export var ilvl: int = 1
## Each: {id, stat, mod_type, value, text}
@export var affixes: Array[Dictionary] = []
## Gem sockets: `sockets` is the count, `gems` holds the socketed gem ids (front-filled).
@export var sockets: int = 0
@export var gems: Array[String] = []
## Legendary / Set item id (UniqueItems), "" for ordinary items.
@export var unique_id: String = ""
## Legendary power values: stat key -> value (see UniqueItems). A runeword's bonuses go here too.
@export var powers: Dictionary = {}
## Runeword id (Runewords), "" if the item isn't one. Its rolled stat bonuses are in rw_mods,
## each {stat, mod_type, value, text}; its other bonuses in powers.
@export var runeword_id: String = ""
@export var rw_mods: Array[Dictionary] = []
## Quality 0..MAX_QUALITY % (Whetstone / Armourer's Scrap): raises the implicit stat.
@export var quality: int = 0
## Implicit roll: the implicit is multiplied by this (rolled IMPLICIT_ROLL on drop, Blessed Orb rerolls it).
@export var implicit_roll: float = 1.0
## Vaal Orb used: the item can never be changed again.
@export var corrupted: bool = false
## Made by a Mirror of Kalandra: can't be changed.
@export var mirrored: bool = false
## Diablo style: Magic and better gear drops unidentified. Its modifiers are hidden, it shows only
## its base name, and it can't be worn or crafted on until a Scroll of Identify (or the Sage in
## town) reveals it. `hidden_name` holds its real name meanwhile.
@export var identified: bool = true
var hidden_name := ""
## Dye (DyeDB id, "" for the item's own colours): helmets and armour can be dyed by the Dyer in town.
## It is only how the item looks, and stays through crafting.
@export var dye: String = ""

const MAX_QUALITY := 20
const IMPLICIT_ROLL := [0.9, 1.1]


## Cells this item takes in the bag and stash (columns x rows).
func grid_size() -> Vector2i:
	return base.bag_size() if base != null else Vector2i.ONE


static func roll_implicit() -> float:
	return snappedf(randf_range(IMPLICIT_ROLL[0], IMPLICIT_ROLL[1]), 0.01)


## Weapons take Whetstones; armour, jewellery-free slots and shields take Armourer's Scraps.
func is_weapon() -> bool:
	return base.slot == "weapon" or (base.slot == "offhand" and base.weapon_type != "shield")


func is_unique() -> bool:
	return unique_id != ""


## Helmets and body armour, the gear you can see worn, can be dyed.
func can_dye() -> bool:
	return base != null and base.slot in DyeDB.SLOTS


func is_runeword() -> bool:
	return runeword_id != ""


## A socketed gem or rune, as it works in this item (a rune's weapon or armour stat).
func socket_info(gid: String) -> Dictionary:
	return GemDef.info(gid, base.slot if base != null else "")


func is_flask() -> bool:
	return base != null and base.slot == "flask"


# ---------- flasks ----------
# A flask is drunk from a flask slot (Player.use_flask), never used up, on a cooldown. Its base
# (ItemBase.flask) says what it does; its modifiers change that (prefixes) or add buffs that last
# while it is in effect (suffixes). Worn flasks give no stats of their own.

const FLASK_MIN_COOLDOWN := 0.4  # cooldown reduction stops at 60%


## What drinking it does, modifiers included:
##   kind, amount, duration, cooldown, instant (bool),
##   buff {stat, mod, value} for a utility flask, during [{stat, mod, value}], warding (bool)
func flask_effect() -> Dictionary:
	var f: Dictionary = base.flask
	var mods := {}
	for a in affixes:
		mods[String(a.stat)] = float(mods.get(String(a.stat), 0.0)) + float(a.value)
	var kind := String(f.get("kind", "life"))
	var amount := float(f.get("amount", 0.0)) * (1.0 + float(mods.get("flask_amount", 0.0)))
	var instant := mods.has("flask_instant")
	if instant:
		amount *= 1.0 - float(mods.flask_instant)
	var duration := float(f.get("duration", 3.0)) * (1.0 + float(mods.get("flask_duration", 0.0)))
	var cooldown := float(f.get("cooldown", 8.0)) * maxf(1.0 - float(mods.get("flask_cooldown", 0.0)), FLASK_MIN_COOLDOWN)
	var out := {"kind": kind, "amount": amount, "duration": duration, "cooldown": cooldown,
		"instant": instant, "during": [], "warding": mods.has("flask_warding")}
	if kind == "utility":
		out.amount = float(f.get("amount", 0.0)) * (1.0 + float(mods.get("flask_effect", 0.0)))
		out["buff"] = {"stat": String(f.get("stat", "")), "mod": int(f.get("mod", StatBlock.ModType.INCREASED)), "value": out.amount}
	var I := StatBlock.ModType.INCREASED
	for pair in [["flask_armor", "armor", StatBlock.ModType.FLAT], ["flask_move", "move_speed", I],
			["flask_atk", "attack_speed", I], ["flask_dmg", "damage", I]]:
		if mods.has(pair[0]):
			out.during.append({"stat": pair[1], "mod": pair[2], "value": float(mods[pair[0]])})
	return out


## The flask's base effect as a line of text, e.g. "Recovers 30% of Life over 3.0s".
func flask_text(power_name := "Power") -> String:
	var e := flask_effect()
	var over := "instantly" if e.instant else "over %.1fs" % e.duration
	match String(e.kind):
		"life":
			return "Recovers %d%% of Life %s" % [int(round(float(e.amount) * 100.0)), over]
		"power":
			return "Recovers %d %s %s" % [int(round(float(e.amount))), power_name, over]
	var t := String(base.flask.get("text", "{v}"))
	var v: float = float(e.amount)
	var shown := str(int(round(v * 100.0))) if int(base.flask.get("mod", 1)) != StatBlock.ModType.FLAT else str(int(round(v)))
	return "%s for %.1fs" % [t.replace("{v}", shown), e.duration]


# ---------- item level ----------
# Higher item level = bigger numbers: the base's implicit grows with ilvl, affix ranges grow
# with ilvl, and rolls lean towards the top of the range (see LootGenerator._roll_affix).
const ILVL_FLAT_GROWTH := 0.06      # flat stats (life, damage, armor): +6% per item level
const ILVL_PERCENT_GROWTH := 0.02   # percentage stats: +2% per item level
const ILVL_PERCENT_CAP := 2.0       # percentage stats grow to at most double
const ILVL_LUCK := 0.05             # how strongly rolls lean high per item level


## Multiplier on stat ranges for an item level (1.0 at ilvl 1).
static func ilvl_scale(item_level: int, percent: bool) -> float:
	var lv := maxi(item_level, 1) - 1
	if percent:
		return minf(1.0 + ILVL_PERCENT_GROWTH * lv, ILVL_PERCENT_CAP)
	return 1.0 + ILVL_FLAT_GROWTH * lv


## A 0..1 position in a stat range; uniform at ilvl 1, leaning towards 1 as item level rises.
static func ilvl_roll(item_level: int) -> float:
	return pow(randf(), 1.0 / (1.0 + ILVL_LUCK * (maxi(item_level, 1) - 1)))


## The base implicit, scaled by item level, its implicit roll and quality.
func implicit_value() -> float:
	return roundf(base.implicit_value * ilvl_scale(ilvl, false) * implicit_roll * (1.0 + quality / 100.0))


func apply_to(stats: StatBlock) -> void:
	if is_flask():
		return  # a flask does its work when drunk (Player.use_flask), not by being worn
	if base.implicit_stat != "":
		stats.add_mod(base.implicit_stat, StatBlock.ModType.FLAT, implicit_value(), self)
	for a in affixes:
		stats.add_mod(a.stat, a.mod_type, a.value, self)
	for gid in gems:
		var g := socket_info(gid)
		if not g.is_empty():
			stats.add_mod(g.stat, g.mod, g.value, self)
	for m in rw_mods:
		stats.add_mod(m.stat, m.mod_type, m.value, self)


func remove_from(stats: StatBlock) -> void:
	stats.remove_source(self)


## Whether this item drops unidentified (Magic and better gear; flasks never).
func can_be_unidentified() -> bool:
	return rarity != Rarity.NORMAL and not is_flask()


## Hide its modifiers and real name until identified.
func unidentify() -> void:
	if identified and can_be_unidentified():
		identified = false
		hidden_name = display_name
		display_name = base.display_name


## Reveal its modifiers and real name. False if it was already identified.
func identify() -> bool:
	if identified:
		return false
	identified = true
	display_name = hidden_name if hidden_name != "" else display_name
	hidden_name = ""
	return true


func get_tooltip() -> String:
	var lines: Array[String] = []
	lines.append("%s  (%s, ilvl %d)" % [display_name, Rarity.keys()[rarity].capitalize(), ilvl])
	if not identified:
		lines.append("Unidentified")
		return "
".join(PackedStringArray(lines))
	if quality > 0:
		lines.append("Quality: +%d%%" % quality)
	if base.implicit_stat != "":
		lines.append("Implicit: +%d %s" % [int(implicit_value()), base.implicit_stat.replace("_", " ")])
	for a in affixes:
		lines.append(a.text)
	if is_runeword():
		lines.append("Runeword: " + Runewords.rune_names(runeword_id))
		for m in rw_mods:
			lines.append(m.text)
		if not powers.is_empty():
			lines.append(PassiveTree.stat_text(powers))
	elif not powers.is_empty():
		lines.append("Legendary: " + PassiveTree.stat_text(powers))
	if UniqueItems.set_of(unique_id) != "":
		lines.append("Set: " + String(UniqueItems.SETS[UniqueItems.set_of(unique_id)].name))
	for i in sockets:
		lines.append(("Socket: " + socket_info(gems[i]).get("text", "?")) if i < gems.size() else "Empty socket")
	if dye != "":
		lines.append("Dyed " + DyeDB.dye_name(dye))
	if corrupted:
		lines.append("Corrupted")
	if mirrored:
		lines.append("Mirrored")
	return "\n".join(PackedStringArray(lines))


const MAX_AFFIXES := {Rarity.NORMAL: 0, Rarity.MAGIC: 2, Rarity.RARE: 6, Rarity.LEGENDARY: 6, Rarity.SET: 6, Rarity.RUNEWORD: 0}


func affix_ids() -> Array:
	return affixes.map(func(a): return a.id)


func to_dict() -> Dictionary:
	return {
		"base": base.id,
		"name": display_name,
		"rarity": int(rarity),
		"ilvl": ilvl,
		"affixes": affixes.map(func(a): return {"id": a.id, "value": a.value}),
		"sockets": sockets,
		"gems": gems,
		"unique": unique_id,
		"powers": powers,
		"runeword": runeword_id,
		"rw_mods": rw_mods.map(func(m): return {"stat": m.stat, "mod_type": int(m.mod_type), "value": m.value, "text": m.text}),
		"quality": quality,
		"implicit_roll": implicit_roll,
		"corrupted": corrupted,
		"mirrored": mirrored,
		"identified": identified,
		"hidden_name": hidden_name,
		"dye": dye,
	}


static func from_dict(d: Dictionary) -> ItemInstance:
	var b := LootGenerator.base_by_id(String(d.get("base", "")))
	if b == null:
		return null
	var it := ItemInstance.new()
	it.base = b
	it.display_name = String(d.get("name", b.display_name))
	it.rarity = int(d.get("rarity", 0)) as Rarity
	it.ilvl = int(d.get("ilvl", 1))
	it.unique_id = String(d.get("unique", ""))
	it.quality = int(d.get("quality", 0))
	it.implicit_roll = float(d.get("implicit_roll", 1.0))
	it.corrupted = bool(d.get("corrupted", false))
	it.mirrored = bool(d.get("mirrored", false))
	it.identified = bool(d.get("identified", true))
	it.hidden_name = String(d.get("hidden_name", ""))
	var dyed := String(d.get("dye", ""))
	it.dye = dyed if DyeDB.has(dyed) and it.can_dye() else ""
	var pw: Dictionary = d.get("powers", {})
	for k in pw:
		it.powers[String(k)] = float(pw[k])
	for a in d.get("affixes", []):
		var def := LootGenerator.find_affix(String(a.get("id", "")))
		if def != null:
			it.affixes.append(LootGenerator.make_entry(def, float(a.get("value", def.min_value))))
	it.runeword_id = String(d.get("runeword", ""))
	for m in d.get("rw_mods", []):
		it.rw_mods.append({"stat": String(m.get("stat", "")), "mod_type": int(m.get("mod_type", 0)),
			"value": float(m.get("value", 0.0)), "text": String(m.get("text", ""))})
	# Items saved before gems existed get their sockets rolled once on load
	it.sockets = int(d.get("sockets", roll_sockets(b, it.rarity)))
	for gid in d.get("gems", []):
		if not GemDef.info(String(gid)).is_empty() and it.gems.size() < it.sockets:
			it.gems.append(String(gid))
	return it


## Number of sockets a new item gets, up to its base's ItemBase.max_sockets(). Each socket past
## the first is less likely than the one before, so a 6-socket item is a find. A Normal item drops
## with sockets often enough to make runeword bases; Magic and better always have at least one.
static func roll_sockets(b: ItemBase, r: int) -> int:
	var cap := b.max_sockets()
	if cap <= 0:
		return 0
	var n := 0
	if r != Rarity.NORMAL or randf() < 0.6:
		n = 1
		while n < cap and randf() < SOCKET_STEP_CHANCE:
			n += 1
	return n


## Chance of each socket past the first when an item drops (so 6 sockets is ~0.55^5, about 5%).
const SOCKET_STEP_CHANCE := 0.55
