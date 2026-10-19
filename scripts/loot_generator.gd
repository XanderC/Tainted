extends Node
## Autoload "LootGenerator". Holds the item/affix database and rolls drops.
## To add content, add a line in _build_bases() or _build_affixes().
## (Later you can move these to .tres files or JSON.)

var bases: Array[ItemBase] = []
var affixes: Array[AffixDef] = []
## Set by GameState when the player loads: most drops are things this class can use.
var smart_class: ClassDef = null
const SMART_LOOT_CHANCE := 0.85

const RARITY_WEIGHTS := {
	ItemInstance.Rarity.NORMAL: 60,
	ItemInstance.Rarity.MAGIC: 30,
	ItemInstance.Rarity.RARE: 10,
}
## Chance that a random drop (no forced rarity) is a Legendary / Set item instead.
const LEGENDARY_CHANCE := 0.012
const SET_CHANCE := 0.010
const NAME_PREFIXES := ["Grim", "Blighted", "Ashen", "Cursed", "Vile", "Hollow", "Wretched", "Sundered"]
const NAME_SUFFIXES := ["of Woe", "of the Pit", "of Ruin", "of Dusk", "of Torment", "of Rot"]


func _ready() -> void:
	randomize()
	_build_bases()
	_build_affixes()


# ---------- database ----------

func _base(id: String, name: String, slot: String, col: Color, imp_stat := "", imp_val := 0.0,
		wtype := "", two_hand := false) -> void:
	var b := ItemBase.new()
	b.id = id
	b.display_name = name
	b.slot = slot
	b.color = col
	b.implicit_stat = imp_stat
	b.implicit_value = imp_val
	b.weapon_type = wtype
	b.two_handed = two_hand
	# Inventory / ground icon, if art exists for this base (assets/gear/<slot>/<id>/icon.png)
	var icon_path := "res://assets/gear/%s/%s/icon.png" % [slot, id]
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
	else:
		b.icon = IconFactory.item_icon(id, slot, col)
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


## [id, name, weapon type, two-handed, drop level, implicit (damage, or armour for shields), colour]
const WEAPON_BASES := [
	# One-handed swords and sabres
	["rusty_sword", "Rusty Sword", "sword", false, 1, 5, Color(0.7, 0.7, 0.75)],
	["copper_sword", "Copper Sword", "sword", false, 5, 8, Color(0.8, 0.55, 0.35)],
	["sabre", "Sabre", "sword", false, 9, 11, Color(0.8, 0.8, 0.85)],
	["broad_sword", "Broad Sword", "sword", false, 14, 14, Color(0.75, 0.75, 0.8)],
	["cutlass", "Cutlass", "sword", false, 19, 17, Color(0.7, 0.72, 0.8)],
	["war_sword", "War Sword", "sword", false, 25, 21, Color(0.78, 0.78, 0.85)],
	["corsair_sabre", "Corsair Sabre", "sword", false, 32, 25, Color(0.75, 0.7, 0.9)],
	["eternal_sword", "Eternal Sword", "sword", false, 40, 30, Color(0.8, 0.75, 0.95)],
	# Two-handed swords
	["greatsword", "Greatsword", "sword", true, 3, 13, Color(0.78, 0.78, 0.85)],
	["bastard_sword", "Bastard Sword", "sword", true, 12, 22, Color(0.75, 0.8, 0.85)],
	["executioner_blade", "Executioner Blade", "sword", true, 24, 34, Color(0.8, 0.8, 0.85)],
	["reaver_blade", "Reaver Blade", "sword", true, 38, 48, Color(0.7, 0.85, 0.85)],
	# One-handed axes
	["hand_axe", "Hand Axe", "axe", false, 1, 6, Color(0.62, 0.55, 0.48)],
	["tomahawk", "Tomahawk", "axe", false, 7, 10, Color(0.65, 0.6, 0.55)],
	["boarding_axe", "Boarding Axe", "axe", false, 15, 15, Color(0.6, 0.58, 0.55)],
	["jade_hatchet", "Jade Hatchet", "axe", false, 26, 22, Color(0.55, 0.75, 0.6)],
	["runic_hatchet", "Runic Hatchet", "axe", false, 38, 30, Color(0.7, 0.6, 0.85)],
	# Two-handed axes
	["battle_axe", "Battle Axe", "axe", true, 3, 14, Color(0.6, 0.55, 0.5)],
	["double_axe", "Double Axe", "axe", true, 12, 24, Color(0.65, 0.62, 0.6)],
	["poleaxe", "Poleaxe", "axe", true, 22, 34, Color(0.6, 0.7, 0.75)],
	["labrys", "Labrys", "axe", true, 34, 46, Color(0.7, 0.62, 0.85)],
	["despot_axe", "Despot Axe", "axe", true, 46, 58, Color(0.65, 0.6, 0.9)],
	# One-handed maces
	["iron_mace", "Iron Mace", "mace", false, 1, 6, Color(0.55, 0.55, 0.6)],
	["spiked_club", "Spiked Club", "mace", false, 7, 10, Color(0.6, 0.5, 0.4)],
	["flanged_mace", "Flanged Mace", "mace", false, 15, 15, Color(0.6, 0.6, 0.65)],
	["morning_star", "Morning Star", "mace", false, 26, 22, Color(0.6, 0.6, 0.7)],
	["dragon_mace", "Dragon Mace", "mace", false, 38, 30, Color(0.75, 0.55, 0.6)],
	# Two-handed maces
	["war_maul", "War Maul", "mace", true, 3, 15, Color(0.5, 0.48, 0.5)],
	["great_club", "Great Club", "mace", true, 12, 25, Color(0.55, 0.45, 0.4)],
	["spiked_maul", "Spiked Maul", "mace", true, 24, 36, Color(0.6, 0.6, 0.62)],
	["colossus_mallet", "Colossus Mallet", "mace", true, 38, 50, Color(0.75, 0.65, 0.7)],
	# Spears (two-handed)
	["wooden_spear", "Wooden Spear", "spear", true, 2, 12, Color(0.6, 0.45, 0.3)],
	["hunting_spear", "Hunting Spear", "spear", true, 10, 20, Color(0.65, 0.6, 0.55)],
	["harpoon", "Harpoon", "spear", true, 18, 28, Color(0.65, 0.65, 0.7)],
	["war_spear", "War Spear", "spear", true, 28, 38, Color(0.7, 0.68, 0.75)],
	["dragon_spear", "Dragon Spear", "spear", true, 40, 50, Color(0.75, 0.62, 0.85)],
	# Daggers
	["dagger", "Dagger", "dagger", false, 1, 4, Color(0.75, 0.75, 0.8)],
	["kris", "Kris", "dagger", false, 10, 9, Color(0.75, 0.7, 0.65)],
	["stiletto", "Stiletto", "dagger", false, 20, 14, Color(0.8, 0.8, 0.85)],
	["skean", "Skean", "dagger", false, 32, 20, Color(0.75, 0.65, 0.9)],
	# Staves (two-handed)
	["oak_staff", "Oak Staff", "staff", true, 1, 10, Color(0.55, 0.40, 0.25)],
	["quarterstaff", "Quarterstaff", "staff", true, 10, 18, Color(0.6, 0.45, 0.3)],
	["serpent_staff", "Serpent Staff", "staff", true, 20, 27, Color(0.5, 0.65, 0.45)],
	["crystal_staff", "Crystal Staff", "staff", true, 32, 38, Color(0.55, 0.8, 0.9)],
	["void_staff", "Void Staff", "staff", true, 44, 50, Color(0.6, 0.5, 0.85)],
	# Bows (no art or class yet)
	["hunting_bow", "Hunting Bow", "bow", true, 1, 9, Color(0.60, 0.45, 0.30)],
	# Shields
	["wooden_shield", "Wooden Shield", "shield", false, 1, 12, Color(0.55, 0.40, 0.25)],
	["buckler", "Buckler", "shield", false, 6, 16, Color(0.6, 0.5, 0.4)],
	["kite_shield", "Kite Shield", "shield", false, 12, 22, Color(0.65, 0.6, 0.6)],
	["tower_shield", "Tower Shield", "shield", false, 16, 26, Color(0.60, 0.62, 0.68)],
	["heater_shield", "Heater Shield", "shield", false, 22, 34, Color(0.65, 0.6, 0.55)],
	["spiked_shield", "Spiked Round Shield", "shield", false, 30, 42, Color(0.6, 0.62, 0.7)],
	["gilded_aegis", "Gilded Aegis", "shield", false, 40, 52, Color(0.85, 0.75, 0.4)],
]


func _base_index(id: String) -> int:
	for i in bases.size():
		if bases[i].id == id:
			return i
	return -1


func _build_bases() -> void:
	# Weapons and shields: tiers of each type, Path of Exile style. A base starts dropping at its
	# drop level (and a little before), so deeper rifts and later zones bring better ones. Art (in
	# hand and in the bag) comes from the CraftPix weapon packs via tools/import_weapons.py.
	for w in WEAPON_BASES:
		var two: bool = w[3]
		_base(w[0], w[1], "offhand" if w[2] == "shield" else "weapon", w[6], "armor" if w[2] == "shield" else "damage",
			w[5], w[2], two)
		bases[-1].drop_level = w[4]
	bases[_base_index("hunting_bow")].weight = 0  # no bow art or bow class yet
	bases[_base_index("tower_shield")].grid_size = Vector2i(2, 3)  # a tall shield takes a tall space
	_base("leather_cap", "Leather Cap", "helmet", Color(0.55, 0.4, 0.25), "armor", 5)
	_base("iron_helm", "Iron Helm", "helmet", Color(0.6, 0.6, 0.65), "armor", 10)
	_base("padded_vest", "Padded Vest", "chest", Color(0.5, 0.4, 0.3), "armor", 10)
	_base("chain_mail", "Chain Mail", "chest", Color(0.65, 0.65, 0.7), "armor", 20)
	_base("leather_gloves", "Leather Gloves", "gloves", Color(0.5, 0.35, 0.2), "armor", 3)
	_base("worn_boots", "Worn Boots", "boots", Color(0.4, 0.3, 0.2), "armor", 3)
	_base("bone_ring", "Bone Ring", "ring", Color(0.9, 0.9, 0.8))
	_base("old_amulet", "Old Amulet", "amulet", Color(0.8, 0.7, 0.3))

	# Belts: the better the base, the more flask slots it opens (and the rarer it drops)
	_belt("rope_belt", "Rope Belt", 2, Color(0.62, 0.50, 0.32), "max_life", 10, 70)
	_belt("leather_belt", "Leather Belt", 3, Color(0.50, 0.33, 0.20), "max_life", 20, 45)
	_belt("heavy_belt", "Heavy Belt", 4, Color(0.45, 0.42, 0.40), "armor", 15, 25)
	_belt("chain_belt", "Chain Belt", 5, Color(0.70, 0.72, 0.78), "armor", 10, 12)

	# Flasks: drunk from a flask slot, never used up, on a cooldown. Life and Power flasks recover
	# over their duration; Utility flasks give a buff for theirs.
	var I := StatBlock.ModType.INCREASED
	var life := Color(0.90, 0.15, 0.20)
	var power := Color(1.0, 0.55, 0.10)
	_flask("small_life_flask", "Small Life Flask", life, 35,
		{"kind": "life", "amount": 0.30, "duration": 3.0, "cooldown": 8.0, "tier": 1})
	_flask("medium_life_flask", "Medium Life Flask", life, 25,
		{"kind": "life", "amount": 0.45, "duration": 3.0, "cooldown": 9.0, "tier": 2})
	_flask("large_life_flask", "Large Life Flask", life, 15,
		{"kind": "life", "amount": 0.60, "duration": 3.5, "cooldown": 10.0, "tier": 3})
	_flask("small_power_flask", "Small Power Flask", power, 25,
		{"kind": "power", "amount": 40.0, "duration": 3.0, "cooldown": 8.0, "tier": 1})
	_flask("medium_power_flask", "Medium Power Flask", power, 18,
		{"kind": "power", "amount": 70.0, "duration": 3.0, "cooldown": 9.0, "tier": 2})
	_flask("large_power_flask", "Large Power Flask", power, 10,
		{"kind": "power", "amount": 100.0, "duration": 3.5, "cooldown": 10.0, "tier": 3})
	_flask("granite_flask", "Granite Flask", Color(0.62, 0.60, 0.58), 10,
		{"kind": "utility", "stat": "armor", "mod": StatBlock.ModType.FLAT, "amount": 50.0,
		"text": "+{v} Armour", "duration": 5.0, "cooldown": 15.0, "tier": 2})
	_flask("quicksilver_flask", "Quicksilver Flask", Color(0.75, 0.85, 0.95), 10,
		{"kind": "utility", "stat": "move_speed", "mod": I, "amount": 0.30,
		"text": "{v}% Increased Movement Speed", "duration": 4.0, "cooldown": 15.0, "tier": 2})
	_flask("silver_flask", "Silver Flask", Color(0.85, 0.85, 0.90), 8,
		{"kind": "utility", "stat": "attack_speed", "mod": I, "amount": 0.20,
		"text": "{v}% Increased Attack Speed", "duration": 5.0, "cooldown": 18.0, "tier": 2})
	_flask("sulphur_flask", "Sulphur Flask", Color(0.95, 0.85, 0.30), 8,
		{"kind": "utility", "stat": "damage", "mod": I, "amount": 0.25,
		"text": "{v}% Increased Damage", "duration": 4.0, "cooldown": 18.0, "tier": 2})


func _belt(id: String, name: String, slots: int, col: Color, imp_stat: String, imp_val: float, weight: int) -> void:
	_base(id, name, "belt", col, imp_stat, imp_val)
	bases[-1].flask_slots = slots
	bases[-1].weight = weight


func _flask(id: String, name: String, col: Color, weight: int, def: Dictionary) -> void:
	_base(id, name, "flask", col)
	var b := bases[-1]
	b.flask = def
	b.weight = weight
	b.icon = IconFactory.potion_icon(id, col, int(def.get("tier", 1)))


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

	# Flask modifiers. Prefixes change the flask; suffixes work while it is in effect.
	_flask_affix("fl_ample", "Ample", true, "{v}% Increased Amount Recovered", "flask_amount", 0.15, 0.35, true, ["life", "power"])
	_flask_affix("fl_seething", "Seething", true, "Recovers Instantly, {v}% Less Amount Recovered", "flask_instant", 0.25, 0.25, true, ["life", "power"])
	_flask_affix("fl_chemist", "Chemist's", true, "{v}% Reduced Cooldown", "flask_cooldown", 0.10, 0.25, true)
	_flask_affix("fl_enduring", "Enduring", true, "{v}% Increased Duration", "flask_duration", 0.20, 0.45, true)
	_flask_affix("fl_potent", "Potent", true, "{v}% Increased Effect", "flask_effect", 0.15, 0.35, true, ["utility"])
	_flask_affix("fl_iron_skin", "of Iron Skin", false, "+{v} Armour during Effect", "flask_armor", 15, 45, false)
	_flask_affix("fl_haste", "of Haste", false, "{v}% Increased Movement Speed during Effect", "flask_move", 0.06, 0.15, true)
	_flask_affix("fl_fury", "of Fury", false, "{v}% Increased Attack Speed during Effect", "flask_atk", 0.05, 0.12, true)
	_flask_affix("fl_berserker", "of the Berserker", false, "{v}% Increased Damage during Effect", "flask_dmg", 0.06, 0.15, true)
	_flask_affix("fl_warding", "of Warding", false, "Removes and Prevents Slows during Effect", "flask_warding", 1, 1, false)


## A flask modifier: `kinds` limits it to life / power / utility flasks (empty = any).
func _flask_affix(id: String, word: String, prefix: bool, text: String, stat: String, lo: float, hi: float,
		pct: bool, kinds: Array[String] = []) -> void:
	_affix(id, text, stat, StatBlock.ModType.INCREASED, lo, hi, pct)
	var a := affixes[-1]
	a.slots = ["flask"]
	a.flask_kinds = kinds
	a.prefix = prefix
	a.word = word


# ---------- rolling ----------

func roll_item(ilvl: int = 1, forced_rarity: int = -1, slot: String = "") -> ItemInstance:
	if forced_rarity < 0 and slot == "":
		var r := randf()
		if r < LEGENDARY_CHANCE + SET_CHANCE:
			var u := UniqueItems.roll(ilvl, r >= LEGENDARY_CHANCE, smart_class)
			if u != null:
				return u
	var item := ItemInstance.new()
	# Bases not yet reachable at this item level (a few levels' grace), and bases switched off, don't drop
	var pool := bases.filter(func(b): return (slot == "" or b.slot == slot) and b.weight > 0 and b.drop_level <= ilvl + 2)
	if pool.is_empty():
		pool = bases.filter(func(b): return slot == "" or b.slot == slot)
	if smart_class != null and randf() < SMART_LOOT_CHANCE:
		var usable := pool.filter(func(b): return b.weapon_type == "" or smart_class.weapon_types.has(b.weapon_type))
		if not usable.is_empty():
			pool = usable
	item.base = _pick_base(pool)
	item.ilvl = ilvl
	item.implicit_roll = ItemInstance.roll_implicit()
	item.rarity = forced_rarity if forced_rarity >= 0 else _roll_rarity()

	var count := 0
	match item.rarity:
		ItemInstance.Rarity.MAGIC:
			count = randi_range(1, 2)
		ItemInstance.Rarity.RARE:
			count = randi_range(3, 4) if item.is_flask() else randi_range(3, 5)

	roll_affixes(item, count)
	item.display_name = _make_name(item)
	item.sockets = ItemInstance.roll_sockets(item.base, item.rarity)
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
## Each kind of item draws from its own modifiers (AffixDef.fits); a flask also has room for one
## prefix and one suffix when Magic, two of each when Rare.
func add_random_affix(item: ItemInstance) -> bool:
	var taken := item.affix_ids()
	var room := flask_affix_room(item)
	var candidates: Array = affixes.filter(func(a): return a.min_ilvl <= item.ilvl and not taken.has(a.id) \
		and a.fits(item.base) and (not item.is_flask() or int(room["prefix" if a.prefix else "suffix"]) > 0))
	var picked: AffixDef = _pick_weighted(candidates)
	if picked == null:
		return false
	item.affixes.append(_roll_affix(picked, item.ilvl))
	return true


func roll_affixes(item: ItemInstance, count: int) -> void:
	for i in count:
		if not add_random_affix(item):
			break


## How many more prefixes and suffixes a flask can take: {"prefix": n, "suffix": n}.
func flask_affix_room(item: ItemInstance) -> Dictionary:
	var cap := 2 if item.rarity >= ItemInstance.Rarity.RARE else (1 if item.rarity == ItemInstance.Rarity.MAGIC else 0)
	var room := {"prefix": cap, "suffix": cap}
	for e in item.affixes:
		var def := find_affix(String(e.id))
		if def != null:
			room["prefix" if def.prefix else "suffix"] -= 1
	return room


## Re-rolls each existing affix's value inside its range, keeping which affixes it has.
func reroll_values(item: ItemInstance) -> void:
	for i in item.affixes.size():
		var def := find_affix(item.affixes[i].id)
		if def != null:
			item.affixes[i] = _roll_affix(def, item.ilvl)


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


## Affix value: the range grows with item level and the roll leans to the high end.
func _roll_affix(a: AffixDef, item_level := 1) -> Dictionary:
	if a.min_value == a.max_value and a.slots.has("flask"):
		return make_entry(a, a.min_value)  # a fixed flask property (Seething, Warding)
	var scale := ItemInstance.ilvl_scale(item_level, a.is_percent)
	var v := lerpf(a.min_value, a.max_value, ItemInstance.ilvl_roll(item_level)) * scale
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


## A base at random, the commoner ones more often (ItemBase.weight).
func _pick_base(pool: Array) -> ItemBase:
	var total := 0
	for b in pool:
		total += maxi(int(b.weight), 1)
	var r := randi_range(1, total)
	for b in pool:
		r -= maxi(int(b.weight), 1)
		if r <= 0:
			return b
	return pool.back()


func _make_name(item: ItemInstance) -> String:
	if item.is_flask() and item.rarity == ItemInstance.Rarity.MAGIC:
		# Path of Exile style: "Ample Small Life Flask of Haste"
		var pre := ""
		var suf := ""
		for e in item.affixes:
			var def := find_affix(String(e.id))
			if def != null and def.prefix:
				pre = def.word + " "
			elif def != null:
				suf = " " + def.word
		return pre + item.base.display_name + suf
	if item.rarity == ItemInstance.Rarity.RARE:
		return "%s %s %s" % [NAME_PREFIXES.pick_random(), item.base.display_name, NAME_SUFFIXES.pick_random()]
	return item.base.display_name
