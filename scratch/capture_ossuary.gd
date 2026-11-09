extends Node2D
## Screenshots of the Ossuary maps and the Verge's mausoleum as the game draws them (walls, floor, dressing), saved as maps_<n>.png in the
## folder given after --out= (default: scratch/). Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_maps.tscn -- --out=<folder>

const SHOTS := [
	["grand_ossuary_1", Vector2(33, 23), 0.2],
	["grand_ossuary_1", Vector2(10, 23), 0.55],
	["grand_ossuary_1", Vector2(22, 22), 0.55],
	["grand_ossuary_1", Vector2(14, 8), 0.55],
	["grand_ossuary_1", Vector2(40, 8), 0.55],
	["grand_ossuary_1", Vector2(40, 18), 0.55],
	["grand_ossuary_1", Vector2(58, 23), 0.55],
	["grand_ossuary_2", Vector2(30, 23), 0.2],
	["grand_ossuary_2", Vector2(10, 7), 0.55],
	["grand_ossuary_2", Vector2(46, 34), 0.55],
	["grand_ossuary_2", Vector2(48, 12), 0.55],
	["ashen_verge", Vector2(62, 23), 0.55],
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
