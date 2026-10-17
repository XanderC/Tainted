extends Node2D
## Screenshot of the inventory with a bag item selected: the item panel (no Equip / Drop buttons)
## and the 🗑 Drop box beside the bag. Needs a window; pass a size to check a phone's shape:
##   godot --path . --resolution 1600x720 res://scratch/capture_drop_box.tscn


func item(id: String, rarity := ItemInstance.Rarity.NORMAL) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	for id in ["greatsword", "chain_mail", "rusty_sword", "iron_helm", "tower_shield", "oak_staff", "bone_ring",
			"dagger", "leather_gloves", "small_life_flask", "rope_belt", "worn_boots"]:
		p.bag.add(item(id, ItemInstance.Rarity.MAGIC))
	p.inventory_changed.emit()
	town.menu.open("details")
	town.menu.select(p.inventory[1])
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	var name := "drop_box_%dx%d.png" % [img.get_width(), img.get_height()]
	img.save_png(ProjectSettings.globalize_path("res://scratch/" + name))
	print("saved ", name)
	get_tree().quit(0)
