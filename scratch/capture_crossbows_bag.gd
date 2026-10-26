extends Node2D

func item(id: String, rarity := ItemInstance.Rarity.MAGIC) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = 25
	it.display_name = it.base.display_name
	return it

func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	for id in ["hunting_crossbow", "light_crossbow", "arbalest", "repeating_crossbow", "siege_crossbow", "runic_arbalest"]:
		p.bag.add(item(id, [1, 2, 0][randi() % 3]))
	p.equip_to(item("dragon_crossbow", 2), "weapon", true)
	p.inventory_changed.emit()
	town.menu.open("details")
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/crossbows_bag.png"))
	town.queue_free()
	await get_tree().process_frame

	RenderingServer.set_default_clear_color(Color(0.42, 0.36, 0.26))
	var held := [
		"hunting_crossbow", "light_crossbow", "arbalest", "repeating_crossbow",
		"siege_crossbow", "runic_arbalest", "dragon_crossbow"
	]
	var rigs := []
	for i in held.size():
		var r := RigSprite.new()
		r.base_scale = 0.32
		r.weapon_from_gear = true
		r.rig_dir = RigSprite.ARCHER_RIG
		r.position = Vector2(130 + (i % 4) * 380, 280 + (i / 4) * 320)
		add_child(r)
		Appearance.apply(r, Appearance.default_look())
		r.set_gear("weapon", held[i])
		r.play_loop("Idle")
		rigs.append(r)
	for i in 6:
		await get_tree().process_frame
	for r in rigs:
		r.play_once("Shooting", 0.6)
	await get_tree().create_timer(0.18).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/crossbows_held.png"))
	print("saved crossbows bag and held screenshots")
	get_tree().quit(0)
