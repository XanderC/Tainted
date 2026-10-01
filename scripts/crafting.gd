class_name Crafting
extends RefCounted
## The rules of each orb, and recipe crafting. Orbs change an item in place; equipped
## items have their stat modifiers removed and re-applied around the change.

const R := ItemInstance.Rarity


## "" if the orb can be used on the item, otherwise a short reason why not.
static func orb_block_reason(item: ItemInstance, orb: String) -> String:
	if item == null:
		return "Pick an item"
	var n := item.affixes.size()
	match orb:
		"transmute":
			if item.rarity != R.NORMAL: return "Needs a Normal item"
		"alteration":
			if item.rarity != R.MAGIC: return "Needs a Magic item"
		"augment":
			if item.rarity != R.MAGIC: return "Needs a Magic item"
			if n >= ItemInstance.MAX_AFFIXES[R.MAGIC]: return "Item is full"
		"regal":
			if item.rarity != R.MAGIC: return "Needs a Magic item"
		"alchemy":
			if item.rarity != R.NORMAL: return "Needs a Normal item"
		"chaos":
			if item.rarity != R.RARE: return "Needs a Rare item"
		"exalt":
			if item.rarity != R.RARE: return "Needs a Rare item"
			if n >= ItemInstance.MAX_AFFIXES[R.RARE]: return "Item is full"
		"divine":
			if item.affixes.is_empty(): return "Item has no affixes"
		"scour":
			if item.rarity == R.NORMAL: return "Already Normal"
	return ""


## Spends one orb and applies it. Returns {"ok": bool, "msg": String}.
static func apply_orb(player: Player, item: ItemInstance, orb: String) -> Dictionary:
	var why := orb_block_reason(item, orb)
	if why != "":
		return {"ok": false, "msg": why}
	if GameState.orb_count(orb) <= 0:
		return {"ok": false, "msg": "You have none"}
	GameState.add_orb(orb, -1)
	player.modify_item(item, func(): _do_orb(item, orb))
	return {"ok": true, "msg": "%s used" % CraftingDB.ORBS[orb].short}


static func _do_orb(item: ItemInstance, orb: String) -> void:
	match orb:
		"transmute":
			item.rarity = R.MAGIC
			LootGenerator.roll_affixes(item, randi_range(1, 2))
			LootGenerator.rename(item)
		"alteration":
			item.affixes.clear()
			LootGenerator.roll_affixes(item, randi_range(1, 2))
		"augment":
			LootGenerator.add_random_affix(item)
		"regal":
			item.rarity = R.RARE
			LootGenerator.add_random_affix(item)
			LootGenerator.rename(item)
		"alchemy":
			item.rarity = R.RARE
			LootGenerator.roll_affixes(item, 4)
			LootGenerator.rename(item)
		"chaos":
			item.affixes.clear()
			LootGenerator.roll_affixes(item, randi_range(4, 5))
			LootGenerator.rename(item)
		"exalt":
			LootGenerator.add_random_affix(item)
		"divine":
			LootGenerator.reroll_values(item)
		"scour":
			item.rarity = R.NORMAL
			item.affixes.clear()
			item.display_name = item.base.display_name


## Breaks an item (from the bag) into materials. Returns the materials gained.
static func salvage(player: Player, item: ItemInstance) -> Dictionary:
	if not player.inventory.has(item):
		return {}
	var gain := CraftingDB.salvage_yield(item)
	player.inventory.erase(item)
	player.inventory_changed.emit()
	for k in gain:
		GameState.add_material(k, gain[k])
	return gain


static func salvage_all(player: Player, rarity: int) -> Dictionary:
	var total := {}
	for it in player.inventory.duplicate():
		if it.rarity == rarity:
			var g := salvage(player, it)
			for k in g:
				total[k] = int(total.get(k, 0)) + int(g[k])
	return total


## Crafts a recipe. Returns {"ok", "msg"}.
static func craft(player: Player, recipe_id: String) -> Dictionary:
	var r: Dictionary = CraftingDB.RECIPES[recipe_id]
	if not GameState.knows_recipe(recipe_id):
		return {"ok": false, "msg": "Recipe not known"}
	if not GameState.can_afford_materials(r.cost):
		return {"ok": false, "msg": "Not enough materials"}
	var res: Dictionary = r.result
	if res.type == "item" and player.inventory.size() >= Player.BAG_SIZE:
		return {"ok": false, "msg": "Bag is full"}
	GameState.spend_materials(r.cost)
	if res.type == "orb":
		GameState.add_orb(res.id, int(res.n))
		return {"ok": true, "msg": "Crafted %d %s" % [res.n, CraftingDB.ORBS[res.id].short]}
	var item := LootGenerator.roll_item(GameState.craft_ilvl() + int(res.get("ilvl_bonus", 0)), int(res.rarity), String(res.slot))
	player.inventory.append(item)
	player.inventory_changed.emit()
	return {"ok": true, "msg": "Crafted %s" % item.display_name, "item": item}
