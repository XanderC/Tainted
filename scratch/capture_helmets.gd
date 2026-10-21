extends Node2D
## Screenshots of the helmets (saved as scratch/helm_<name>.png): all of them in the bag, and each
## one worn on a character. Needs a window; pass a phone's shape:
##   godot --path . --resolution 1600x720 res://scratch/capture_helmets.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	GameState.attributes = {"str": 300, "dex": 300}
	p.refresh_attributes()
	p.bag.clear()
	for h in LootGenerator.HELMET_BASES:
		var it := LootGenerator.roll_item(30, ItemInstance.Rarity.MAGIC, "helmet")
		it.base = LootGenerator.base_by_id(h[0])
		it.display_name = it.base.display_name
		p.bag.add(it)
	p.inventory_changed.emit()
	town.menu.open("details")
	town.menu.select(p.inventory[8])
	await _shot("bag")
	town.menu.close()

	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.62, 0.66)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var n := 0
	for h in LootGenerator.HELMET_BASES:
		var rig := RigSprite.new()
		rig.base_scale = 0.28
		rig.weapon_from_gear = true
		layer.add_child(rig)
		Appearance.apply(rig, Appearance.random_look())
		rig.set_gear("helmet", h[0])
		rig.play_loop("Idle")
		rig.position = Vector2(110 + (n % 7) * 215, 190 + (n / 7) * 330)
		var l := Label.new()
		l.text = String(h[1])
		l.add_theme_color_override("font_color", Color.BLACK)
		l.position = rig.position + Vector2(-60, 40)
		layer.add_child(l)
		n += 1
	await _shot("worn")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/helm_%s.png" % n))
	print("saved ", n)
