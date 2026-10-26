extends Node2D
## Screenshots of the Merchant's cards (scratch/shoptip_<name>.png): a ware with Buy, a bag item with Sell.
##   godot --path . --resolution 1600x720 res://scratch/capture_shop_tips.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: GameMenu = town.menu
	var p: Player = town.player
	var it := LootGenerator.roll_item(12, ItemInstance.Rarity.MAGIC, "")
	it.base = LootGenerator.base_by_id("brigandine")
	it.display_name = it.base.display_name
	p.bag.add(it)
	menu.open_vendor("shop")
	await get_tree().process_frame
	var shop := menu.current_panel() as ShopPanel
	var orb: Dictionary = shop._wares().filter(func(w): return w.type == "orb")[0]
	Input.warp_mouse(Vector2(300, 250))
	shop._ware = orb
	menu.refresh()
	shop._show_ware_tip(orb, Vector2(300, 250))
	await _shot("ware")
	var tip := menu.item_tip()
	print("main ", tip._main.size, " min ", tip._main.get_combined_minimum_size(), " body ", tip._body.size, " bodymin ", tip._body.get_combined_minimum_size())
	for c in tip._body.get_children():
		print("  ", c.get_class(), " ", c.position, " ", c.size, " min ", c.get_combined_minimum_size())
	Input.warp_mouse(Vector2(980, 520))
	menu.select(it)
	await _shot("sell")
	p.bag.remove(it)
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/shoptip_%s.png" % n))
	print("saved ", n)
