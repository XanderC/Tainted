extends Node2D
## Screenshot of the stash's Currency tab with a bag item selected. Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_currency.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	var it := LootGenerator.roll_item(10, ItemInstance.Rarity.MAGIC, "chest")
	p.bag.add(it)
	p.inventory_changed.emit()
	town.menu.open_vendor("stash")
	(town.menu.current_panel() as StashPanel).tab = "currency"
	town.menu.select(it)
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/currency_tab.png"))
	print("saved currency_tab.png")
	get_tree().quit(0)
