extends Node2D
## Screenshots of a zone's barrels, crates and urns and a chest as placed (not moved): the Blackroot Wilds, near the first
## chest and near the first cluster away from the start. Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_breakables.tscn


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	for i in 10:
		await get_tree().process_frame
	var props := get_tree().get_nodes_in_group("breakables")
	var chests := get_tree().get_nodes_in_group("interactables").filter(func(n): return n is LootChest)
	var spot: Vector2 = chests[0].global_position + Vector2(-140, 40)
	zone.player.global_position = spot
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/breakables_chest.png"))
	var best: Node2D = props[0]
	var dense := 0
	for b in props:
		var n := props.filter(func(o): return o.global_position.distance_to(b.global_position) < 300.0).size()
		if n > dense:
			dense = n
			best = b
	zone.player.global_position = best.global_position + Vector2(-120, 60)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/breakables_cluster.png"))
	print("props %d, densest spot has %d within 300 px" % [props.size(), dense])
	get_tree().quit(0)
