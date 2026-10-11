class_name ItemInstance
extends Resource
## A single rolled item: a base + rarity + rolled affixes. Serializable for saves.
## Legendary and Set items (UniqueItems) also carry a unique id; Legendaries have rolled powers.

enum Rarity { NORMAL, MAGIC, RARE, LEGENDARY, SET }

const RARITY_COLORS := {
	Rarity.NORMAL: Color(0.9, 0.9, 0.9),
	Rarity.MAGIC: Color(0.45, 0.55, 1.0),
	Rarity.RARE: Color(1.0, 0.85, 0.3),
	Rarity.LEGENDARY: Color(1.0, 0.55, 0.15),
	Rarity.SET: Color(0.30, 0.95, 0.40),
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
## Legendary power values: stat key -> value (see UniqueItems).
@export var powers: Dictionary = {}
## Quality 0..MAX_QUALITY % (Whetstone / Armourer's Scrap): raises the implicit stat.
@export var quality: int = 0
## Implicit roll: the implicit is multiplied by this (rolled IMPLICIT_ROLL on drop, Blessed Orb rerolls it).
@export var implicit_roll: float = 1.0
## Vaal Orb used: the item can never be changed again.
@export var corrupted: bool = false
## Made by a Mirror of Kalandra: can't be changed.
@export var mirrored: bool = false

const MAX_QUALITY := 20
const IMPLICIT_ROLL := [0.9, 1.1]


static func roll_implicit() -> float:
	return snappedf(randf_range(IMPLICIT_ROLL[0], IMPLICIT_ROLL[1]), 0.01)


## Weapons take Whetstones; armour, jewellery-free slots and shields take Armourer's Scraps.
func is_weapon() -> bool:
	return base.slot == "weapon" or (base.slot == "offhand" and base.weapon_type != "shield")


func is_unique() -> bool:
	return unique_id != ""


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
	if base.implicit_stat != "":
		stats.add_mod(base.implicit_stat, StatBlock.ModType.FLAT, implicit_value(), self)
	for a in affixes:
		stats.add_mod(a.stat, a.mod_type, a.value, self)
	for gid in gems:
		var g := GemDef.info(gid)
		if not g.is_empty():
			stats.add_mod(g.stat, g.mod, g.value, self)


func remove_from(stats: StatBlock) -> void:
	stats.remove_source(self)


func get_tooltip() -> String:
	var lines: Array[String] = []
	lines.append("%s  (%s, ilvl %d)" % [display_name, Rarity.keys()[rarity].capitalize(), ilvl])
	if quality > 0:
		lines.append("Quality: +%d%%" % quality)
	if base.implicit_stat != "":
		lines.append("Implicit: +%d %s" % [int(implicit_value()), base.implicit_stat.replace("_", " ")])
	for a in affixes:
		lines.append(a.text)
	if not powers.is_empty():
		lines.append("Legendary: " + PassiveTree.stat_text(powers))
	if UniqueItems.set_of(unique_id) != "":
		lines.append("Set: " + String(UniqueItems.SETS[UniqueItems.set_of(unique_id)].name))
	for i in sockets:
		lines.append(("Socket: " + GemDef.info(gems[i]).get("text", "?")) if i < gems.size() else "Empty socket")
	if corrupted:
		lines.append("Corrupted")
	if mirrored:
		lines.append("Mirrored")
	return "\n".join(PackedStringArray(lines))


const MAX_AFFIXES := {Rarity.NORMAL: 0, Rarity.MAGIC: 2, Rarity.RARE: 6, Rarity.LEGENDARY: 6, Rarity.SET: 6}


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
		"quality": quality,
		"implicit_roll": implicit_roll,
		"corrupted": corrupted,
		"mirrored": mirrored,
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
	var pw: Dictionary = d.get("powers", {})
	for k in pw:
		it.powers[String(k)] = float(pw[k])
	for a in d.get("affixes", []):
		var def := LootGenerator.find_affix(String(a.get("id", "")))
		if def != null:
			it.affixes.append(LootGenerator.make_entry(def, float(a.get("value", def.min_value))))
	# Items saved before gems existed get their sockets rolled once on load
	it.sockets = int(d.get("sockets", roll_sockets(b.slot, it.rarity)))
	for gid in d.get("gems", []):
		if not GemDef.info(String(gid)).is_empty() and it.gems.size() < it.sockets:
			it.gems.append(String(gid))
	return it


## Number of gem sockets a new item gets. Weapons and body armour can hold more.
static func roll_sockets(slot: String, r: int) -> int:
	var cap := 3 if slot in ["weapon", "chest"] else (1 if slot in ["ring", "amulet"] else 2)  # shields: 2
	var n := randi_range(0, 1)
	if r == Rarity.MAGIC:
		n = randi_range(1, 2)
	elif r >= Rarity.RARE:
		n = randi_range(1, 3)
	return mini(n, cap)
