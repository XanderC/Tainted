extends Node2D
## Another player's skills as your game shows them (RemotePlayer.show_fx): four copies of a player,
## each showing one, saved to scratch/pfx.png.
##   godot --path . res://scratch/capture_pfx.tscn


func _ready() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(640, 360)
	add_child(cam)
	var look := {"name": "Ally", "level": 12, "class": "warrior", "look": Appearance.random_look(), "gear": {}}
	var fx := [
		["swing", 0.0, 120.0, 105.0, "e6e6f2", 1.5],  # longer than a real swing: the first frames are slow
		["ring", 135.0, "ff9933", 0.35],
		["spin", 135.0, "66ccff", 0.4],
		["ground", 0.0, 0.0, 140.0, "cc8844", 5.0],
	]
	for i in fx.size():
		var rp := RemotePlayer.new()
		add_child(rp)
		var at := Vector2(200 + i * 300, 380)
		rp.setup(10 + i, look, {"p": at})
		var d: Array = fx[i].duplicate()
		if d[0] == "ground":
			d[1] = at.x
			d[2] = at.y
		rp.show_fx(d)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/pfx.png"))
	print("saved pfx.png")
	get_tree().quit()
