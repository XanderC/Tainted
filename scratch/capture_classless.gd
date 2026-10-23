extends Node2D
## A look at the classless game: a bow user on the archer rig loosing a Multishot, with the split
## Adrenaline / Mana globe; Firebolt and Frost Nova; Arc; and the new passive tree. Saves
## scratch/cl_<n>.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_classless.tscn

var main
var p: Player


func _ready() -> void:
	GameState.give_starter_skills()
	GameState.level = 30
	GameState.attributes = {"str": 30, "dex": 60, "vit": 10, "ene": 60}
	GameState.skill_points = 30
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.2)
	p = main.player
	p.refresh_attributes()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	p.global_position = main.maze.random_floor_near(main.maze.start_pos, 150.0, 250.0)
	for i in 3:
		var e := Enemy.new()
		e.max_hp = 1.0e7
		e.speed = 0.0
		e.touch_damage = 0.0
		e.set_kind("zombie")
		main.add_child(e)
		e.global_position = p.global_position + Vector2(260, -80 + 80 * i)
	p.resource = 60.0
	var bow := _item("long_bow")
	p.bag.add(bow)
	p.equip_to(bow, "weapon")
	await _wait(0.5)
	_slot(1, "multishot")
	_slot(2, "frost_nova")
	_slot(3, "arc")
	p.mana = p.max_mana() * 0.7
	p.facing = Vector2.RIGHT
	p.use_skill(1)
	await _wait(0.12)
	_shot(1)
	await _wait(1.0)
	p.unequip("weapon")
	await _wait(0.3)
	_slot(0, "firebolt")
	p._cooldowns[0] = 0.0
	p.use_skill(0)
	await _wait(0.15)
	_shot(2)
	await _wait(0.6)
	p.use_skill(2)
	await _wait(0.2)
	_shot(3)
	await _wait(0.8)
	p.use_skill(3)
	await _wait(0.12)
	_shot(4)
	await _wait(0.5)
	for nid in ["str_p0", "str_p1", "dex_p0", "dex_p1", "str_w0", "str_wn", "str_c0", "str_c1"]:
		GameState.allocate_node(nid)
	main.skill_tree_ui.open()
	await _wait(0.6)
	_shot(5)
	get_tree().quit()


func _slot(i: int, id: String) -> void:
	if GameState.skill_gem_count(id) <= 0 and GameState.slot_of(id) < 0:
		GameState.add_skill_gem(id, 1)
	GameState.set_slot_skill(i, id)


func _item(base_id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(base_id)
	it.ilvl = 1
	it.display_name = it.base.display_name
	return it


func _shot(n: int) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/cl_%d.png" % n))


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
