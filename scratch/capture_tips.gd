extends Node2D
## Screenshots of item cards shown where an item is tapped (saved as scratch/tip_<name>.png): a bag
## item compared with what is worn, worn gear, and a stash item. Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_tips.tscn


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
	var menu: GameMenu = town.menu
	GameState.attributes = {"str": 300, "dex": 300}
	p.refresh_attributes()
	p.bag.clear()
	var worn := item("leather_jerkin")
	p.bag.add(worn)
	p.equip_to(worn, "chest")
	for id in ["brigandine", "broad_sword", "iron_gauntlets", "despot_axe"]:
		p.bag.add(item(id, ItemInstance.Rarity.RARE))
	p.inventory_changed.emit()
	menu.open()
	Input.warp_mouse(Vector2(980, 520))
	menu.select(p.inventory[0])
	await _shot("bag")
	Input.warp_mouse(Vector2(1200, 250))
	menu.select(worn)
	await _shot("worn")
	var unid := item("battle_plate", ItemInstance.Rarity.RARE)
	unid.identified = false
	p.bag.add(unid)
	p.inventory_changed.emit()
	Input.warp_mouse(Vector2(1300, 600))
	menu.select(unid)
	await _shot("unid")
	p.bag.remove(unid)
	menu.close()
	var st := item("frost_plate", ItemInstance.Rarity.RARE)
	GameState.stash.add(st)
	menu.open_vendor("stash")
	Input.warp_mouse(Vector2(300, 300))
	(menu.current_panel() as StashPanel).tab = "items"
	menu.selected = st
	menu.show_item_tip(st)
	await _shot("stash")
	GameState.stash.remove(st)
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/tip_%s.png" % n))
	print("saved ", n)
