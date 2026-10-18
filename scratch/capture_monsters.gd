extends Node2D
## Every monster kind, boss and NPC skin on the rig (scratch/monsters.png).
##   godot --path . --resolution 1600x900 res://scratch/capture_monsters.tscn


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.42, 0.36, 0.26))
	var ids: Array = []
	for d in DirAccess.get_directories_at("res://assets/skins"):
		ids.append(d)
	ids.sort()
	ids.push_front("")
	var cols := 14
	for i in ids.size():
		var r := RigSprite.new()
		r.base_scale = 0.17
		r.skin = ids[i]
		r.position = Vector2(60 + (i % cols) * 112, 150 + (i / cols) * 170)
		add_child(r)
		r.play_loop("Idle")
		var l := Label.new()
		l.text = ids[i] if ids[i] != "" else "zombie"
		l.position = r.position + Vector2(-55, 6)
		l.add_theme_font_size_override("font_size", 11)
		add_child(l)
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/monsters.png"))
	print("saved monsters")
	get_tree().quit(0)
