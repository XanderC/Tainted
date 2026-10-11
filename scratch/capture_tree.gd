extends Node2D
## Screenshot of the town's passive tree (header with the Respec button):
##   godot --path . --resolution 1600x720 res://scratch/capture_tree.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 3:
		await get_tree().process_frame
	town.skill_tree_ui.open()
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/tree_%dx%d.png" % [img.get_width(), img.get_height()]))
	print("saved")
	get_tree().quit(0)
