extends Node2D
## Close-up of archer skins mid-shot (scratch/archers.png).


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.42, 0.36, 0.26))
	var ids := ["archer_1", "archer_guy", "elf_archer_2", "undead_archer_1", "skeleton_archer_2", "skeleton_hunter_1", "forest_ranger_1", "archer_3"]
	var rigs: Array = []
	for i in ids.size():
		var r := RigSprite.new()
		r.base_scale = 0.38
		r.skin = ids[i]
		r.position = Vector2(110 + (i % 4) * 390, 320 + (i / 4) * 360)
		add_child(r)
		rigs.append(r)
		r.play_loop("Idle")
	for i in 6:
		await get_tree().process_frame
	for r in rigs:
		r.play_once("Shooting", 1.0)
	await get_tree().create_timer(0.12).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/archers.png"))
	print("saved archers")
	get_tree().quit(0)
