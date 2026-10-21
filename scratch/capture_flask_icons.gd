extends Node2D
## Screenshots of the flask icons (saved as scratch/flask_<name>.png): in the bag and the paperdoll,
## and the HUD flask bar. Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_flask_icons.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	GameState.attributes = {"str": 300, "dex": 300}
	p.refresh_attributes()
	p.bag.clear()
	var ids := ["small_life_flask", "medium_life_flask", "large_life_flask", "small_power_flask", "medium_power_flask",
		"large_power_flask", "granite_flask", "quicksilver_flask", "silver_flask", "sulphur_flask"]
	var belt := LootGenerator.roll_item(30, ItemInstance.Rarity.NORMAL, "belt")
	belt.base = LootGenerator.base_by_id("chain_belt")
	p.bag.add(belt)
	p.equip_to(belt, "belt")
	for i in ids.size():
		var f := ItemInstance.new()
		f.base = LootGenerator.base_by_id(ids[i])
		f.ilvl = 20
		f.display_name = f.base.display_name
		p.bag.add(f)
		if i < 5:
			p.equip_flask(f, i)
	p.inventory_changed.emit()
	town.menu.open("details")
	await _shot("bag")
	town.menu.close()
	await _shot("hud")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/flask_%s.png" % n))
	print("saved ", n)
