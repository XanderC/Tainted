extends Node2D
## Screenshots of the Ossuary maps and the Verge's mausoleum as the game draws them (walls, floor, dressing), saved as maps_<n>.png in the
## folder given after --out= (default: scratch/). Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_maps.tscn -- --out=<folder>

const SHOTS := [
	["sepulcher_of_mourning", Vector2(29, 22), 0.2],
	["sepulcher_of_mourning", Vector2(8, 22), 0.55],
	["sepulcher_of_mourning", Vector2(24, 22), 0.55],
	["sepulcher_of_mourning", Vector2(46, 22), 0.55],
	["sepulcher_of_mourning", Vector2(52, 20), 0.55],
	["grand_ossuary_2", Vector2(54, 35), 0.55],
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
		get_viewport().get_texture().get_image().save_png(out + "oss_%d.png" % i)
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
