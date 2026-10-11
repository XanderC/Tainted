extends Node2D
## Screenshots: an unidentified Rare's details (Identify button), then the Sage in town.
##   godot --path . --resolution 1600x720 res://scratch/capture_identify.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 3:
		await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	var it := LootGenerator.roll_item(20, ItemInstance.Rarity.RARE, "chest")
	it.unidentify()
	p.bag.add(it)
	p.inventory_changed.emit()
	town.menu.open()
	town.menu.select(it)
	await get_tree().create_timer(0.5).timeout
	_shot("identify_details.png")
	town.menu.close()
	p.bag.clear()
	p.global_position = Vector2(-600, 230)
	await get_tree().create_timer(0.5).timeout
	_shot("identify_sage.png")
	get_tree().quit(0)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name))
	print("saved ", name)
