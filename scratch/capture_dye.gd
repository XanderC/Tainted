extends Node2D
## Screenshots of the Dyer and dyed gear (saved as scratch/dye_<name>.png): the Dyer in town, her
## window, and dyed helmets and armour worn and in the bag. Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_dye.tscn


func item(id: String, rarity := ItemInstance.Rarity.MAGIC) -> ItemInstance:
	var it := LootGenerator.roll_item(12, rarity, "")
	it.base = LootGenerator.base_by_id(id)
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	GameState.attributes = {"str": 300, "dex": 300}
	GameState.orbs["transmute"] = 30
	p.refresh_attributes()
	p.bag.clear()
	for id in ["knights_helm", "chain_mail", "viking_helm", "padded_vest", "horned_cap"]:
		p.bag.add(item(id))
	p.equip_to(item("iron_helm"), "helmet", true)
	p.equip_to(item("chain_mail"), "chest", true)
	p.inventory_changed.emit()

	p.global_position = town.DYER + Vector2(110, 70)
	await _shot("dyer")

	town.dye_ui.open()
	await _shot("window")
	town.dye_ui._paint = "crimson"
	town.dye_ui._refresh()
	await _shot("preview")
	town.dye_ui._apply()
	town.dye_ui._item = p.inventory[1]
	town.dye_ui._where = "bag"
	town.dye_ui._paint = "sapphire"
	town.dye_ui._refresh()
	town.dye_ui._apply()
	await _shot("applied")
	town.dye_ui._item = p.equipment["chest"]
	town.dye_ui._where = "worn"
	town.dye_ui._paint = "ruby"
	town.dye_ui._refresh()
	town.dye_ui._apply()
	town.dye_ui._item = p.equipment["helmet"]
	town.dye_ui._paint = "jet"
	town.dye_ui._refresh()
	town.dye_ui._apply()
	await _shot("armour")
	# a row of every dye on the helmet, to judge the colours
	for i in [3, 13, 23, 0, 1, 2, 4, 9, 14]:
		town.dye_ui._item = p.equipment["helmet"]
		town.dye_ui._paint = DyeDB.PALETTE[i][0]
		town.dye_ui._refresh()
		town.dye_ui._apply()
		await _shot("helm_" + str(i))
	town.dye_ui.close()
	town.menu.open("details")
	await _shot("bag")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/dye_%s.png" % n))
	print("saved ", n)
