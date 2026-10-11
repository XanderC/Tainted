extends Node2D
## Screenshots: the inventory with a belt and flasks (one selected), the Merchant's flasks, and the
## HUD flask bar. Needs a window:  godot --path . res://scratch/capture_flasks.tscn


func item(id: String, rarity := ItemInstance.Rarity.NORMAL, mods: Array = []) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = 12
	for m in mods:
		it.affixes.append(LootGenerator.make_entry(LootGenerator.find_affix(m[0]), m[1]))
	LootGenerator.rename(it)
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var R := ItemInstance.Rarity
	p.equip_to(item("chain_belt", R.MAGIC), "belt", true)
	p.flasks = [item("large_life_flask", R.MAGIC, [["fl_ample", 0.3], ["fl_iron_skin", 30]]),
		item("medium_power_flask"), item("quicksilver_flask", R.MAGIC, [["fl_enduring", 0.4]]),
		item("granite_flask", R.RARE, [["fl_potent", 0.25], ["fl_chemist", 0.2], ["fl_warding", 1], ["fl_fury", 0.08]]),
		item("small_life_flask", R.MAGIC, [["fl_seething", 0.25]])]
	p.flasks[3].display_name = "Grim Granite Flask of Woe"
	p.inventory_changed.emit()

	town.menu.open("details")
	town.menu.select(p.flasks[3])
	await _settle()
	_shot("flask_inventory.png")
	town.menu.close()

	p.use_flask(0)
	p.use_flask(2)
	await _settle()
	_shot("flask_hud.png")

	town.menu.open_vendor("shop")
	await _settle()
	_shot("flask_shop.png")
	get_tree().quit(0)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/" + name))
	print("saved ", name)
