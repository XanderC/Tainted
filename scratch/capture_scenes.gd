extends Node
## Screenshots of the real scenes after the map theme change (scenes_<name>.png in the --out= folder):
## Ashfall with its NPCs, a rift with monsters, and the Ashwood at the start.
##   godot --path . --resolution 1600x720 res://scratch/capture_scenes.tscn -- --out=<folder>

var out := "res://scratch/"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	await _scene("res://scenes/town.tscn", "town")
	await _scene("res://scenes/main.tscn", "rift")
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	await _scene("res://scenes/zone.tscn", "zone")
	get_tree().quit()


func _scene(path: String, n: String) -> void:
	var s = load(path).instantiate()
	add_child(s)
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "scenes_%s.png" % n)
	s.queue_free()
	await get_tree().process_frame
