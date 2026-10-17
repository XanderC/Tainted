class_name Crafting
extends RefCounted
## The rules of each orb, and recipe crafting. Orbs change an item in place; equipped
## items have their stat modifiers removed and re-applied around the change.

const R := ItemInstance.Rarity


## Orbs that still work on Legendary and Set items (as in Path of Exile).
const UNIQUE_OK := ["vaal", "whetstone", "armourer", "jeweller", "blessed", "divine", "mirror"]
## Orbs used somewhere else (not on items).
const NOT_ITEM_ORBS := {"regret": "Use it in the passive tree to refund a node",
	"gemcutter": "Use it on a gem in the Skills panel"}


## "" if the orb can be used on the item, otherwise a short reason why not.
static func orb_block_reason(item: ItemInstance, orb: String) -> String:
	if NOT_ITEM_ORBS.has(orb):
		return NOT_ITEM_ORBS[orb]
	if item == null:
		return "Pick an item"
	if orb == "identify":
		return "" if not item.identified else "Already identified"
	if not item.identified:
		return "Identify it first"
	if item.corrupted:
		return "Corrupted items can't be changed"
	if item.mirrored:
		return "Mirrored items can't be changed"
	if item.is_unique() and not UNIQUE_OK.has(orb):
		return "Legendary and Set items can't be altered"
	if item.is_runeword():
		return "Runeword items can't be altered"
	var n := item.affixes.size()
	# A flask has room for one prefix and one suffix when Magic, two of each when Rare
	var flask_full := false
	if item.is_flask():
		var room := LootGenerator.flask_affix_room(item)
		flask_full = int(room.prefix) <= 0 and int(room.suffix) <= 0
	match orb:
		"transmute":
			if item.rarity != R.NORMAL: return "Needs a Normal item"
		"alteration":
			if item.rarity != R.MAGIC: return "Needs a Magic item"
		"augment":
			if item.rarity != R.MAGIC: return "Needs a Magic item"
			if n >= ItemInstance.MAX_AFFIXES[R.MAGIC] or flask_full: return "Item is full"
		"regal":
			if item.rarity != R.MAGIC: return "Needs a Magic item"
		"alchemy", "chance":
			if item.rarity != R.NORMAL: return "Needs a Normal item"
		"chaos":
			if item.rarity != R.RARE: return "Needs a Rare item"
		"exalt":
			if item.rarity != R.RARE: return "Needs a Rare item"
			if n >= ItemInstance.MAX_AFFIXES[R.RARE] or flask_full: return "Item is full"
		"divine":
			if item.affixes.is_empty() and item.powers.is_empty(): return "Item has no affixes"
		"annul":
			if item.affixes.is_empty(): return "Item has no affixes"
		"scour":
			if item.rarity == R.NORMAL: return "Already Normal"
		"blessed":
			if item.base.implicit_stat == "": return "Item has no implicit"
		"jeweller":
			if socket_cap(item) == 0: return "Belts and flasks have no sockets"
			if socket_cap(item) <= 1 and item.sockets == 1: return "Can only ever have 1 socket"
		"whetstone":
			if not item.is_weapon(): return "Needs a weapon"
			if item.quality >= ItemInstance.MAX_QUALITY: return "Quality is already 20%"
		"armourer":
			if item.is_weapon() or item.base.implicit_stat != "armor": return "Needs armour or a shield"
			if item.quality >= ItemInstance.MAX_QUALITY: return "Quality is already 20%"
		"mirror":
			# The copy is the same shape as the original, so it needs a space that size
			if is_instance_valid(GameState.player) and GameState.player.bag.find_free(item) == ItemGrid.NONE:
				return "No room in the bag for the copy"
	return ""


## Most sockets an item can roll (ItemBase.max_sockets: up to 6 on two-handed weapons and body armour).
static func socket_cap(item: ItemInstance) -> int:
	return item.base.max_sockets()


## Spends one orb and applies it. Returns {"ok": bool, "msg": String}.
static func apply_orb(player: Player, item: ItemInstance, orb: String) -> Dictionary:
	var why := orb_block_reason(item, orb)
	if why != "":
		return {"ok": false, "msg": why}
	if GameState.orb_count(orb) <= 0:
		return {"ok": false, "msg": "You have none"}
	GameState.add_orb(orb, -1)
	if orb == "mirror":
		var copy := ItemInstance.from_dict(item.to_dict())
		copy.mirrored = true
		player.add_to_bag(copy)
		return {"ok": true, "msg": "Mirrored %s!" % item.display_name}
	var result := {"msg": ""}
	player.modify_item(item, func(): result.msg = _do_orb(item, orb))
	return {"ok": true, "msg": result.msg if result.msg != "" else "%s used" % CraftingDB.ORBS[orb].short}


## Applies an orb's effect. Returns a message when the result is worth telling ("" otherwise).
static func _do_orb(item: ItemInstance, orb: String) -> String:
	match orb:
		"identify":
			item.identify()
			return "Identified: %s" % item.display_name
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
			if item.rarity == R.LEGENDARY:
				UniqueItems.reroll_powers(item)
		"scour":
			item.rarity = R.NORMAL
			item.affixes.clear()
			item.display_name = item.base.display_name
		"annul":
			var gone: Dictionary = item.affixes.pick_random()
			item.affixes.erase(gone)
			return "Annulled: %s" % gone.text
		"blessed":
			item.implicit_roll = ItemInstance.roll_implicit()
			return "Implicit is now +%d" % int(item.implicit_value())
		"chance":
			return _chance(item)
		"jeweller":
			var cap := socket_cap(item)
			var n := item.sockets
			for t in 6:  # try for a different count
				n = randi_range(1, cap)
				if n != item.sockets:
					break
			item.sockets = n
			while item.gems.size() > n:  # gems that no longer fit go back to the pouch
				GameState.add_gem(item.gems.pop_back(), 1)
			return "%d socket%s" % [n, "" if n == 1 else "s"]
		"whetstone", "armourer":
			var add := 5 if item.rarity == R.NORMAL else (2 if item.rarity == R.MAGIC else 1)
			item.quality = mini(item.quality + add, ItemInstance.MAX_QUALITY)
			return "Quality +%d%%" % item.quality
		"vaal":
			return _vaal(item)
	return ""


## Orb of Chance: Normal -> mostly Magic, sometimes Rare, rarely the Legendary or Set item of that base.
static func _chance(item: ItemInstance) -> String:
	var r := randf()
	var uid := ""
	if r < 0.05:
		uid = UniqueItems.unique_for_base(item.base.id, false)
	elif r < 0.09:
		uid = UniqueItems.unique_for_base(item.base.id, true)
	if uid != "":
		_become(item, UniqueItems.make(uid, item.ilvl))
		return "Lucky! It became %s!" % item.display_name
	if r < 0.30:
		item.rarity = R.RARE
		LootGenerator.roll_affixes(item, randi_range(3, 5))
	else:
		item.rarity = R.MAGIC
		LootGenerator.roll_affixes(item, randi_range(1, 2))
	LootGenerator.rename(item)
	return "It became %s" % ItemInstance.Rarity.keys()[item.rarity].capitalize()


## Vaal Orb: corrupt with one of four outcomes.
static func _vaal(item: ItemInstance) -> String:
	item.corrupted = true
	match randi() % 4:
		0:
			return "Corrupted: no change"
		1:
			item.implicit_roll = minf(item.implicit_roll + 0.25, 1.5)
			return "Corrupted: stronger implicit (+%d)" % int(item.implicit_value())
		2:
			if socket_cap(item) == 0:
				return "Corrupted: no change"  # belts and flasks never take sockets
			item.sockets = mini(item.sockets + 1, socket_cap(item) + 1)
			return "Corrupted: extra socket (%d)" % item.sockets
	if item.is_unique():
		LootGenerator.reroll_values(item)
		UniqueItems.reroll_powers(item)
		return "Corrupted: values rerolled"
	item.rarity = R.RARE
	item.affixes.clear()
	LootGenerator.roll_affixes(item, randi_range(4, 6))
	LootGenerator.rename(item)
	return "Corrupted: rerolled into a Rare"


## Turns `item` into `other` in place (keeps the object, so bag / equipment references stay valid).
static func _become(item: ItemInstance, other: ItemInstance) -> void:
	if other == null:
		return
	item.base = other.base
	item.unique_id = other.unique_id
	item.rarity = other.rarity
	item.display_name = other.display_name
	item.affixes = other.affixes
	item.powers = other.powers
	item.implicit_roll = other.implicit_roll


## Crafts a recipe. Returns {"ok", "msg"}.
static func craft(player: Player, recipe_id: String) -> Dictionary:
	var r: Dictionary = CraftingDB.RECIPES[recipe_id]
	if not GameState.knows_recipe(recipe_id):
		return {"ok": false, "msg": "Recipe not known"}
	if not GameState.can_afford(r.cost):
		return {"ok": false, "msg": "Not enough orbs"}
	var res: Dictionary = r.result
	if res.type == "orb":
		GameState.pay(r.cost)
		GameState.add_orb(res.id, int(res.n))
		return {"ok": true, "msg": "Crafted %d %s" % [res.n, CraftingDB.ORBS[res.id].short]}
	var ilvl := GameState.craft_ilvl() + int(res.get("ilvl_bonus", 0))
	var item: ItemInstance
	if res.type == "unique":
		# Plans forge at your character level at least, so a found plan stays useful
		item = UniqueItems.make(String(res.id), maxi(ilvl, GameState.level + int(res.get("ilvl_bonus", 0))))
	else:
		item = LootGenerator.roll_item(ilvl, int(res.rarity), String(res.slot))
	# Made before anything is spent: gear takes a space its shape, so check this one fits
	if not player.can_fit(item):
		return {"ok": false, "msg": "No room in the bag for %s" % item.display_name}
	GameState.pay(r.cost)
	player.add_to_bag(item)
	return {"ok": true, "msg": "Crafted %s" % item.display_name, "item": item}
