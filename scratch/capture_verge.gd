extends Node2D
## Screenshots of maps as the game draws them (walls, floor, dressing), saved as maps_<n>.png in the
## folder given after --out= (default: scratch/). Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_maps.tscn -- --out=<folder>

const SHOTS := [
	["ashen_verge", Vector2(36, 24), 0.2],
	["ashen_verge", Vector2(12, 25), 0.55],
	["ashen_verge", Vector2(33, 13), 0.55],
	["ashen_verge", Vector2(31, 37), 0.55],
	["ashen_verge", Vector2(62, 25), 0.55],
	["ashen_verge", Vector2(49, 39), 0.55],
	["ashen_verge", Vector2(52, 10), 0.55],
]


func _ready() -> void:
	var out := "res://scratch/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	y_sort_enabled = true
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	for i in SHOTS.size():
		var s: Array = SHOTS[i]
		var m: Node2D
		m = MazeMap.new()
		m.setup("oakhaven" if s[0] == "town" else s[0])
		cam.position = s[1] * MazeMap.CELL
		add_child(m)
		cam.zoom = Vector2(s[2], s[2])
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "verge_%d.png" % i)
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
