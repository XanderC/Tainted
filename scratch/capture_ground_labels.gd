extends Node2D
## Ground item name plates: a pile of drops (plates stack, no overlap), then tapping plates:
## one in reach, one far away (the player walks over), and one with the bag full.
##   godot --path . --resolution 1600x720 res://scratch/capture_ground_labels.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 3:
		await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	var at := p.global_position + Vector2(140, -40)
	var picks: Array[LootPickup] = []
	for i in 12:
		var pk := LootPickup.new()
		pk.item = LootGenerator.roll_item(10, [0, 0, 1, 1, 2][i % 5])
		pk.position = at + Vector2(randf_range(-90, 90), randf_range(-50, 50))
		town.add_child(pk)
		picks.append(pk)
	await get_tree().create_timer(0.6).timeout
	_shot("ground_labels.png")
	var fails := 0
	# Overlap check
	for a in picks:
		for b in picks:
			if a != b and a._plate.get_global_rect().intersects(b._plate.get_global_rect()):
				fails += 1
	print("overlapping plates: ", fails / 2)
	# A tap from far away: the player walks over, then takes it
	var far := picks[0]
	var it := far.item
	p.global_position = far.global_position + Vector2(-400, 0)
	far.request_pickup()
	await get_tree().create_timer(2.5).timeout
	print("far item taken: ", p.inventory.has(it) or p.is_worn(it))
	# Bag full: no room message, item stays
	var big := LootPickup.new()
	big.item = LootGenerator.roll_item(10, 0, "chest")
	while p.bag.can_fit(big.item):
		p.bag.add(LootGenerator.roll_item(10, 0, "chest"))
	p.equipment.erase("chest")
	p.equipment["chest"] = LootGenerator.roll_item(60, 2, "chest")  # so it's not an upgrade
	big.position = p.global_position + Vector2(30, 0)
	town.add_child(big)
	await get_tree().process_frame
	big.request_pickup()
	await get_tree().create_timer(0.3).timeout
	print("full bag kept it on the ground: ", is_instance_valid(big) and big.is_inside_tree())
	_shot("ground_full.png")
	get_tree().quit(0)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name))
	print("saved ", name)
