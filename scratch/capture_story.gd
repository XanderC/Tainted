extends Node2D
## Screenshots of the story pieces (scratch/story_<name>.png): town with quest markers, Hesk's
## offer, the quest log, the Dune Wastes at the road in, the wreck and the raider camp.
##   godot --path . --resolution 1600x720 res://scratch/capture_story.tscn


func _ready() -> void:
	GameState.quests = {}
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await _wait()
	town.player.global_position = Vector2(-330, 380)
	await _shot("town")
	town.dialogue.open("hesk")
	town.dialogue._pick(Quests.npc_options("hesk")[0])
	await _shot("offer")
	Quests.start("a1_lost_caravan")
	Quests.start("a1_into_the_wastes")
	town.dialogue.close()
	town.quest_log.open()
	await _shot("log")
	town.quest_log.close()
	town.queue_free()
	await get_tree().process_frame

	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "town"
	var zn = load("res://scenes/zone.tscn").instantiate()
	add_child(zn)
	await _wait()
	await _shot("zone_in")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.aggro_range = 0.0 if false else e.aggro_range
	var wreck: Vector2 = Vector2(35.5 * 128, 22.5 * 128)
	zn.player.global_position = wreck + Vector2(0, 200)
	await _wait()
	await _shot("wreck")
	zn.player.global_position = Vector2(57.5 * 128, 13.5 * 128)
	zn.player.can_fight = false
	await _wait()
	await _shot("camp")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	GameState.quests["a1_lost_caravan"] = {"state": "active", "step": 3, "count": 0}
	zn.player.global_position = Vector2(59.5 * 128, 9.5 * 128)
	await _wait()
	await _shot("strongbox")
	town = load("res://scenes/town.tscn").instantiate()
	zn.queue_free()
	GameState.zone_entry = "dune_wastes"
	add_child(town)
	await _wait()
	await _shot("town_west")
	get_tree().quit(0)


func _wait() -> void:
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout


func _shot(n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/story_%s.png" % n))
	print("saved ", n)
