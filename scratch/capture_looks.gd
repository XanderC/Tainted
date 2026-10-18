extends Node2D
## Renders a grid of random character appearances on the real rig (scratch/looks.png), plus one
## of each hairstyle and beard. Needs a window:  godot --path . res://scratch/capture_looks.tscn


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.27, 0.35, 0.27))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var looks: Array = []
	for i in 8:
		looks.append(Appearance.random_look(rng))
	for h in Appearance.options("hair"):
		var l := Appearance.default_look("female" if h in ["bob", "fringe", "straight", "flowing"] else "male")
		l["hair"] = h
		l["hair_color"] = Appearance.HAIR_COLORS.keys()[looks.size() % Appearance.HAIR_COLORS.size()]
		looks.append(l)
	for b in Appearance.options("beards"):
		var l := Appearance.default_look("male")
		l["beard"] = b
		l["beard_color"] = Appearance.HAIR_COLORS.keys()[looks.size() % 10]
		l["skin"] = Appearance.SKIN_TONES.keys()[looks.size() % 5]
		looks.append(l)
	var cols := 9
	for i in looks.size():
		var r := RigSprite.new()
		r.base_scale = 0.3
		r.weapon_from_gear = true
		r.position = Vector2(80 + (i % cols) * 170, 230 + (i / cols) * 240)
		add_child(r)
		r.play_loop("Idle")
		Appearance.apply(r, looks[i])
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/looks.png"))
	print("saved looks")
	get_tree().quit(0)
