extends Node
## Autoload "LootGenerator". Holds the item/affix database and rolls drops.
## To add content, add a line in _build_bases() or _build_affixes().
## (Later you can move these to .tres files or JSON.)

var bases: Array[ItemBase] = []
var affixes: Array[AffixDef] = []

const RARITY_WEIGHTS := {
	ItemInstance.Rarity.NORMAL: 60,
	ItemInstance.Rarity.MAGIC: 30,
	ItemInstance.Rarity.RARE: 10,
}
const NAME_PREFIXES := ["Grim", "Blighted", "Ashen", "Cursed", "Vile", "Hollow", "Wretched", "Sundered"]
const NAME_SUFFIXES := ["of Woe", "of the Pit", "of Ruin", "of Dusk", "of Torment", "of Rot"]


func _ready() -> void:
	randomize()
	_build_bases()
	_build_affixes()


# ---------- database ----------

func _base(id: String, name: String, slot: String, col: Color, imp_stat := "", imp_val := 0.0) -> void:
	var b := ItemBase.new()
	b.id = id
	b.display_name = name
	b.slot = slot
	b.color = col
	b.implicit_stat = imp_stat
	b.implicit_value = imp_val
	# Inventory / ground icon, if art exists for this base (assets/gear/<slot>/<id>/icon.png)
	var icon_path := "res://assets/gear/%s/%s/icon.png" % [slot, id]
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
	bases.append(b)


func _affix(id: String, text: String, stat: String, type: int, lo: float, hi: float,
		pct := false, min_ilvl := 1, weight := 100) -> void:
	var a := AffixDef.new()
	a.id = id
	a.display = text
	a.stat = stat
	a.mod_type = type
	a.min_value = lo
	a.max_value = hi
	a.is_percent = pct
	a.min_ilvl = min_ilvl
	a.weight = weight
	affixes.append(a)


func _build_bases() -> void:
	_base("rusty_sword", "Rusty Sword", "weapon", Color(0.7, 0.7, 0.75), "damage", 5)
	_base("battle_axe", "Battle Axe", "weapon", Color(0.6, 0.55, 0.5), "damage", 8)
	_base("leather_cap", "Leather Cap", "helmet", Color(0.55, 0.4, 0.25), "armor", 5)
	_base("iron_helm", "Iron Helm", "helmet", Color(0.6, 0.6, 0.65), "armor", 10)
	_base("padded_vest", "Padded Vest", "chest", Color(0.5, 0.4, 0.3), "armor", 10)
	_base("chain_mail", "Chain Mail", "chest", Color(0.65, 0.65, 0.7), "armor", 20)
	_base("leather_gloves", "Leather Gloves", "gloves", Color(0.5, 0.35, 0.2), "armor", 3)
	_base("worn_boots", "Worn Boots", "boots", Color(0.4, 0.3, 0.2), "armor", 3)
	_base("bone_ring", "Bone Ring", "ring", Color(0.9, 0.9, 0.8))
	_base("old_amulet", "Old Amulet", "amulet", Color(0.8, 0.7, 0.3))


func _build_affixes() -> void:
	var F := StatBlock.ModType.FLAT
	var I := StatBlock.ModType.INCREASED
	var M := StatBlock.ModType.MORE
	_affix("life_flat", "+{v} Max Life", "max_life", F, 10, 40)
	_affix("life_inc", "{v}% Increased Max Life", "max_life", I, 0.05, 0.15, true)
	_affix("dmg_flat", "+{v} Damage", "damage", F, 3, 12)
	_affix("dmg_inc", "{v}% Increased Damage", "damage", I, 0.08, 0.25, true)
	_affix("dmg_more", "{v}% More Damage", "damage", M, 0.05, 0.10, true, 5, 40)
	_affix("atk_speed", "{v}% Increased Attack Speed", "attack_speed", I, 0.04, 0.12, true)
	_affix("move_speed", "{v}% Increased Move Speed", "move_speed", I, 0.05, 0.15, true)
	_affix("armor_flat", "+{v} Armor", "armor", F, 5, 30)
	_affix("crit", "+{v}% Critical Chance", "crit_chance", F, 0.02, 0.08, true)


# ---------- rolling ----------

func roll_item(ilvl: int = 1, forced_rarity: int = -1, slot: String = "") -> ItemInstance:
	var item := ItemInstance.new()
	if slot != "":
		item.base = bases.filter(func(b): return b.slot == slot).pick_random()
	else:
		item.base = bases.pick_random()
	item.ilvl = ilvl
	item.rarity = forced_rarity if forced_rarity >= 0 else _roll_rarity()

	var count := 0
	match item.rarity:
		ItemInstance.Rarity.MAGIC:
			count = randi_range(1, 2)
		ItemInstance.Rarity.RARE:
			count = randi_range(3, 5)

	roll_affixes(item, count)
	item.display_name = _make_name(item)
	return item


# ---------- crafting helpers ----------

func base_by_id(id: String) -> ItemBase:
	for b in bases:
		if b.id == id:
			return b
	return null


func find_affix(id: String) -> AffixDef:
	for a in affixes:
		if a.id == id:
			return a
	return null


## Adds one random affix the item doesn't already have. Returns false if none are available.
func add_random_affix(item: ItemInstance) -> bool:
	var taken := item.affix_ids()
	var candidates: Array = affixes.filter(func(a): return a.min_ilvl <= item.ilvl and not taken.has(a.id))
	var picked: AffixDef = _pick_weighted(candidates)
	if picked == null:
		return false
	item.affixes.append(_roll_affix(picked))
	return true


func roll_affixes(item: ItemInstance, count: int) -> void:
	for i in count:
		if not add_random_affix(item):
			break


## Re-rolls each existing affix's value inside its range, keeping which affixes it has.
func reroll_values(item: ItemInstance) -> void:
	for i in item.affixes.size():
		var def := find_affix(item.affixes[i].id)
		if def != null:
			item.affixes[i] = _roll_affix(def)


func rename(item: ItemInstance) -> void:
	item.display_name = _make_name(item)


func _roll_rarity() -> int:
	var total := 0
	for k in RARITY_WEIGHTS:
		total += RARITY_WEIGHTS[k]
	var r := randi_range(1, total)
	for k in RARITY_WEIGHTS:
		r -= RARITY_WEIGHTS[k]
		if r <= 0:
			return k
	return ItemInstance.Rarity.NORMAL


func _pick_weighted(pool: Array) -> AffixDef:
	if pool.is_empty():
		return null
	var total := 0
	for a in pool:
		total += a.weight
	var r := randi_range(1, total)
	for a in pool:
		r -= a.weight
		if r <= 0:
			return a
	return pool.back()


func _roll_affix(a: AffixDef) -> Dictionary:
	var v := randf_range(a.min_value, a.max_value)
	v = snappedf(v, 0.01) if a.is_percent else roundf(v)
	return make_entry(a, v)


func make_entry(a: AffixDef, v: float) -> Dictionary:
	var shown := str(int(round(v * 100.0))) if a.is_percent else str(int(v))
	return {
		"id": a.id,
		"stat": a.stat,
		"mod_type": a.mod_type,
		"value": v,
		"text": a.display.replace("{v}", shown),
	}


func _make_name(item: ItemInstance) -> String:
	if item.rarity == ItemInstance.Rarity.RARE:
		return "%s %s %s" % [NAME_PREFIXES.pick_random(), item.base.display_name, NAME_SUFFIXES.pick_random()]
	return item.base.display_name
