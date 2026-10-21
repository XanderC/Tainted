extends Node2D
## Screenshots of armour (saved as scratch/armour_<name>.png): characters in each tier of body armour,
## gloves, boots and helmet, and the pieces in the bag. Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_armour.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.62, 0.66)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var chests: Array = LootGenerator.CHEST_BASES
	var n := 0
	for c in chests:
		var t := float(n) / float(chests.size() - 1)
		var rig := RigSprite.new()
		rig.base_scale = 0.26
		rig.weapon_from_gear = true
		layer.add_child(rig)
		Appearance.apply(rig, Appearance.random_look())
		rig.set_gear("chest", c[0])
		rig.set_gear("gloves", LootGenerator.GLOVE_BASES[int(round(t * (LootGenerator.GLOVE_BASES.size() - 1)))][0])
		rig.set_gear("boots", LootGenerator.BOOT_BASES[int(round(t * (LootGenerator.BOOT_BASES.size() - 1)))][0])
		rig.set_gear("helmet", LootGenerator.HELMET_BASES[int(round(t * (LootGenerator.HELMET_BASES.size() - 1)))][0])
		rig.set_gear("weapon", "broad_sword")
		rig.play_loop("Idle")
		rig.position = Vector2(100 + (n % 7) * 215, 250 + (n / 7) * 340)
		var l := Label.new()
		l.text = String(c[1])
		l.add_theme_color_override("font_color", Color.BLACK)
		l.position = rig.position + Vector2(-60, 30)
		layer.add_child(l)
		n += 1
	await _shot("worn")
	layer.queue_free()
	var p: Player = town.player
	p.bag.clear()
	for table in [LootGenerator.CHEST_BASES.slice(0, 6), LootGenerator.GLOVE_BASES.slice(0, 4), LootGenerator.BOOT_BASES.slice(0, 4)]:
		for c in table:
			var it := ItemInstance.new()
			it.base = LootGenerator.base_by_id(c[0])
			it.ilvl = 10
			it.display_name = it.base.display_name
			p.bag.add(it)
	p.inventory_changed.emit()
	town.menu.open("details")
	await _shot("bag")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/armour_%s.png" % n))
	print("saved ", n)
