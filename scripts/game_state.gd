extends Node
## Autoload "GameState": everything that persists between dungeon runs
## (gold, orbs, materials, recipes, and the player's items). Saved to user://.

signal changed

const SAVE_PATH := "user://tainted_save.json"

var gold := 0
var orbs := {}
var materials := {}
var known_recipes: Array[String] = []
var runs_cleared := 0
var player: Player
const STASH_SIZE := 60
var stash: Array[ItemInstance] = []  # shared storage, account-wide

var _pending_inventory: Array = []
var _pending_equipment := {}
var _restoring := false
var _save_queued := false


func _ready() -> void:
	if not load_game():
		_new_game()


func _new_game() -> void:
	gold = CraftingDB.STARTING_GOLD
	orbs = CraftingDB.STARTING_CURRENCY.duplicate()
	materials = CraftingDB.STARTING_MATERIALS.duplicate()
	known_recipes.clear()
	for id in CraftingDB.RECIPES:
		if CraftingDB.RECIPES[id].source == "start":
			known_recipes.append(id)
	runs_cleared = 0
	stash.clear()
	_pending_inventory.clear()
	_pending_equipment.clear()


## Item level used by crafting recipes; grows as you clear dungeons.
func craft_ilvl() -> int:
	return mini(3 + runs_cleared * 2, 40)


# ---------- counts ----------

func orb_count(id: String) -> int:
	return int(orbs.get(id, 0))


func material_count(id: String) -> int:
	return int(materials.get(id, 0))


func add_orb(id: String, n: int) -> void:
	orbs[id] = maxi(orb_count(id) + n, 0)
	_changed()


func add_material(id: String, n: int) -> void:
	materials[id] = maxi(material_count(id) + n, 0)
	_changed()


func add_gold(n: int) -> void:
	gold = maxi(gold + n, 0)
	_changed()


func can_afford_materials(cost: Dictionary) -> bool:
	for k in cost:
		if material_count(k) < int(cost[k]):
			return false
	return true


func spend_materials(cost: Dictionary) -> void:
	for k in cost:
		materials[k] = material_count(k) - int(cost[k])
	_changed()


## Applies a drops dictionary ({"gold", "materials", "orbs"}).
func grant(drops: Dictionary) -> void:
	gold += int(drops.get("gold", 0))
	for k in drops.get("materials", {}):
		materials[k] = material_count(k) + int(drops.materials[k])
	for k in drops.get("orbs", {}):
		orbs[k] = orb_count(k) + int(drops.orbs[k])
	_changed()


# ---------- recipes ----------

func knows_recipe(id: String) -> bool:
	return known_recipes.has(id)


func learn_recipe(id: String) -> bool:
	if knows_recipe(id) or not CraftingDB.RECIPES.has(id):
		return false
	known_recipes.append(id)
	_changed()
	return true


## A random recipe of the given source you don't know yet, or "" if you know them all.
func random_unknown_recipe(source: String) -> String:
	var pool: Array = []
	for id in CraftingDB.RECIPES:
		if CraftingDB.RECIPES[id].source == source and not knows_recipe(id):
			pool.append(id)
	return "" if pool.is_empty() else String(pool.pick_random())


func buy_recipe(id: String) -> bool:
	var price: int = CraftingDB.RECIPES[id].get("price", 0)
	if gold < price or knows_recipe(id):
		return false
	gold -= price
	return learn_recipe(id)


func buy_orb(id: String) -> bool:
	var price: int = CraftingDB.ORBS[id].price
	if gold < price:
		return false
	gold -= price
	add_orb(id, 1)
	return true


func buy_material(id: String) -> bool:
	var price: int = CraftingDB.MATERIALS[id].price
	if price <= 0 or gold < price:
		return false
	gold -= price
	add_material(id, 1)
	return true


# ---------- shared stash ----------

func stash_item(item: ItemInstance) -> bool:
	if stash.size() >= STASH_SIZE or not is_instance_valid(player) or not player.inventory.has(item):
		return false
	player.inventory.erase(item)
	stash.append(item)
	player.inventory_changed.emit()
	return true


func take_from_stash(item: ItemInstance) -> bool:
	if not stash.has(item) or not is_instance_valid(player) or player.inventory.size() >= Player.BAG_SIZE:
		return false
	stash.erase(item)
	player.inventory.append(item)
	player.inventory_changed.emit()
	return true


static func sell_price(item: ItemInstance) -> int:
	match item.rarity:
		ItemInstance.Rarity.MAGIC: return 8 + item.ilvl * 2
		ItemInstance.Rarity.RARE: return 25 + item.ilvl * 5
	return 2 + item.ilvl


func sell_item(item: ItemInstance) -> int:
	if not is_instance_valid(player) or not player.inventory.has(item):
		return 0
	var g := sell_price(item)
	player.inventory.erase(item)
	gold += g
	player.inventory_changed.emit()  # also queues a save and refreshes UIs
	return g


# ---------- player hookup and saving ----------

## Called by the player once its rig exists: puts saved items back on it.
func attach_player(p: Player) -> void:
	player = p
	_restoring = true
	for d in _pending_inventory:
		var it := ItemInstance.from_dict(d)
		if it != null and p.inventory.size() < Player.BAG_SIZE:
			p.inventory.append(it)
	for slot in _pending_equipment:
		var it := ItemInstance.from_dict(_pending_equipment[slot])
		if it != null and it.base.slot == slot:
			p.equip(it)
	p.hp = p.stats.get_stat("max_life")
	_restoring = false
	p.inventory_changed.connect(_changed)
	p.inventory_changed.emit()


func _changed() -> void:
	changed.emit()
	if _restoring or _save_queued:
		return
	_save_queued = true
	save.call_deferred()


func save() -> void:
	_save_queued = false
	var inv: Array = []
	var eq := {}
	if is_instance_valid(player):
		for it in player.inventory:
			inv.append(it.to_dict())
		for slot in player.equipment:
			eq[slot] = player.equipment[slot].to_dict()
		_pending_inventory = inv  # kept fresh so the next scene's player restores the latest state
		_pending_equipment = eq
	else:
		inv = _pending_inventory
		eq = _pending_equipment
	var data := {
		"version": 1, "gold": gold, "orbs": orbs, "materials": materials,
		"recipes": known_recipes, "runs_cleared": runs_cleared,
		"stash": stash.map(func(i): return i.to_dict()),
		"inventory": inv, "equipment": eq,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	gold = int(data.get("gold", 0))
	orbs = _ints(data.get("orbs", {}))
	materials = _ints(data.get("materials", {}))
	known_recipes.clear()
	for id in data.get("recipes", []):
		if CraftingDB.RECIPES.has(String(id)):
			known_recipes.append(String(id))
	runs_cleared = int(data.get("runs_cleared", 0))
	stash.clear()
	for d in data.get("stash", []):
		var it := ItemInstance.from_dict(d)
		if it != null:
			stash.append(it)
	_pending_inventory = data.get("inventory", [])
	_pending_equipment = data.get("equipment", {})
	return true


func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = int(d[k])
	return out


## Wipes the save (debug). Call, then restart the game.
func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_new_game()
