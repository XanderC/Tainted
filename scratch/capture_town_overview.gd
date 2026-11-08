extends Node2D
## A picture of the whole town from above (the camera pulled right back): scratch/town_overview.png.
##   godot --path . --resolution 1900x1100 res://scratch/capture_town_overview.tscn


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 8:
		await get_tree().process_frame
	var cam: Camera2D = null
	for c in town.player.get_children():
		if c is Camera2D:
			cam = c
	cam.zoom = Vector2(0.33, 0.33)
	cam.limit_left = -10000
	cam.limit_right = 10000
	cam.limit_top = -10000
	cam.limit_bottom = 10000
	town.player.global_position = Vector2(20 * 128, 15 * 128)
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/town_overview.png"))
	get_tree().quit()
