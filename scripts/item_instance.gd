class_name ItemInstance
extends Resource
## A single rolled item: a base + rarity + rolled affixes. Serializable for saves.

enum Rarity { NORMAL, MAGIC, RARE }

const RARITY_COLORS := {
	Rarity.NORMAL: Color(0.9, 0.9, 0.9),
	Rarity.MAGIC: Color(0.45, 0.55, 1.0),
	Rarity.RARE: Color(1.0, 0.85, 0.3),
}

@export var base: ItemBase
@export var display_name: String = ""
@export var rarity: Rarity = Rarity.NORMAL
@export var ilvl: int = 1
## Each: {id, stat, mod_type, value, text}
@export var affixes: Array[Dictionary] = []


func apply_to(stats: StatBlock) -> void:
	if base.implicit_stat != "":
		stats.add_mod(base.implicit_stat, StatBlock.ModType.FLAT, base.implicit_value, self)
	for a in affixes:
		stats.add_mod(a.stat, a.mod_type, a.value, self)


func remove_from(stats: StatBlock) -> void:
	stats.remove_source(self)


func get_tooltip() -> String:
	var lines: Array[String] = []
	lines.append("%s  (%s, ilvl %d)" % [display_name, Rarity.keys()[rarity].capitalize(), ilvl])
	if base.implicit_stat != "":
		lines.append("Implicit: +%d %s" % [int(base.implicit_value), base.implicit_stat.replace("_", " ")])
	for a in affixes:
		lines.append(a.text)
	return "\n".join(PackedStringArray(lines))


const MAX_AFFIXES := {Rarity.NORMAL: 0, Rarity.MAGIC: 2, Rarity.RARE: 6}


func affix_ids() -> Array:
	return affixes.map(func(a): return a.id)


func to_dict() -> Dictionary:
	return {
		"base": base.id,
		"name": display_name,
		"rarity": int(rarity),
		"ilvl": ilvl,
		"affixes": affixes.map(func(a): return {"id": a.id, "value": a.value}),
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
	for a in d.get("affixes", []):
		var def := LootGenerator.find_affix(String(a.get("id", "")))
		if def != null:
			it.affixes.append(LootGenerator.make_entry(def, float(a.get("value", def.min_value))))
	return it
