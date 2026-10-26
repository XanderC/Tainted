extends Node2D
## Screenshots of maps as the game draws them (walls, floor, dressing), saved as maps_<n>.png in the
## folder given after --out= (default: scratch/). Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_maps.tscn -- --out=<folder>

const SHOTS := [  # map id ("town" = Ashfall), centre (cells), zoom
	["bone_labyrinth", Vector2(15, 10.5), 0.36],
	["bone_labyrinth", Vector2(11, 6.5), 0.9],
	["bone_labyrinth", Vector2(23, 15.5), 0.9],
	["twin_oasis", Vector2(15, 10), 0.36],
	["scorched_halls", Vector2(15, 10.5), 0.36],
	["sunken_courtyards", Vector2(15, 9.5), 0.36],
	["dune_wastes", Vector2(35, 23), 0.22],
	["dune_wastes", Vector2(35, 22), 0.6],
	["dune_wastes", Vector2(57, 10), 0.6],
	["dune_wastes", Vector2(13, 36), 0.6],
	["dune_wastes", Vector2(31, 37), 0.6],
	["tutorial", Vector2(17, 4), 0.5],
	["town", Vector2(0, 0), 0.5],
	["town", Vector2(-3, -1.5), 0.9],
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
		if s[0] == "town":
			m = TownMap.new()
			cam.position = s[1] * 128.0
		else:
			m = MazeMap.new()
			m.setup(s[0])
			cam.position = s[1] * MazeMap.CELL
		add_child(m)
		cam.zoom = Vector2(s[2], s[2])
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "maps_%d.png" % i)
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
