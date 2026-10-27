extends Node2D
## Screenshot of the player behind a house in the town (scratch/fade.png). Needs a window:
##   godot --path . --resolution 1280x720 res://scratch/capture_fade.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	var p: Player = town.player
	p.global_position = Vector2(-560, -330)
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/fade.png"))
	get_tree().quit()
