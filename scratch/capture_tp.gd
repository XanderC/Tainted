extends Node
## A look at town portal scrolls: the 🌀 button and a portal just read in the Dune Wastes, then the
## portal back by the town square. Saves scratch/tp_1.png, tp_2.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_tp.tscn

var runner := false


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	GameState.give_starter_skills()
	GameState.tp_scrolls = 7
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	get_tree().change_scene_to_file("res://scenes/zone.tscn")
	await _wait(1.5)
	var z = get_tree().current_scene
	z.player.global_position = z.maze.random_floor_near(z.maze.start_pos, 300.0, 400.0)
	await _wait(0.6)
	TownPortals.read_scroll(z)
	z.player.global_position += Vector2(90, 30)
	await _wait(0.8)
	_shot(1)
	var tp: TownPortal = get_tree().get_nodes_in_group("town_portals")[0]
	z.player.global_position = tp.global_position
	tp._plate.pressed.emit()
	await _wait(2.0)
	_shot(2)
	get_tree().quit()


func _shot(n: int) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/tp_%d.png" % n))


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
