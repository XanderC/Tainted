extends Node2D
## The new weapons: a bag of them (scratch/weapons_bag.png) and characters holding them
## (scratch/weapons_held.png).  godot --path . --resolution 1600x720 res://scratch/capture_weapons.tscn


func item(id: String, rarity := ItemInstance.Rarity.MAGIC) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = 20
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	for id in ["reaver_blade", "labrys", "dragon_spear", "colossus_mallet", "eternal_sword", "runic_hatchet",
			"corsair_sabre", "dragon_mace", "skean", "gilded_aegis", "kite_shield", "void_staff"]:
		p.bag.add(item(id, [1, 2, 0][randi() % 3]))
	p.equip_to(item("war_sword", 2), "weapon", true)
	p.equip_to(item("heater_shield", 1), "offhand", true)
	p.inventory_changed.emit()
	town.menu.open("details")
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/weapons_bag.png"))
	town.queue_free()
	await get_tree().process_frame

	RenderingServer.set_default_clear_color(Color(0.42, 0.36, 0.26))
	var held := [["eternal_sword", "gilded_aegis"], ["labrys", ""], ["dragon_spear", ""], ["colossus_mallet", ""],
		["corsair_sabre", "spiked_shield"], ["runic_hatchet", "kite_shield"], ["reaver_blade", ""], ["dragon_mace", "tower_shield"]]
	var rigs := []
	for i in held.size():
		var r := RigSprite.new()
		r.base_scale = 0.32
		r.weapon_from_gear = true
		r.position = Vector2(140 + (i % 4) * 380, 300 + (i / 4) * 330)
		add_child(r)
		Appearance.apply(r, Appearance.default_look())
		r.set_gear("weapon", held[i][0])
		if held[i][1] != "":
			r.set_offhand(held[i][1], true)
		r.play_loop("Idle")
		rigs.append(r)
	for i in 6:
		await get_tree().process_frame
	for r in rigs:
		r.play_once("Slashing", 0.6)
	await get_tree().create_timer(0.18).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/weapons_held.png"))
	print("saved weapons")
	get_tree().quit(0)
