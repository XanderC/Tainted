extends Node2D
## Opens the tutorial and the town and takes a picture of each, to see the camera and the world labels
## (scratch/smoke_tutorial.png, smoke_town.png).
##   godot --path . --resolution 1600x720 res://scratch/smoke_scenes.tscn


func _ready() -> void:
	GameState.tutorial_stage = 0
	var tut = load("res://scenes/tutorial.tscn").instantiate()
	add_child(tut)
	for i in 30:
		await get_tree().process_frame
	_shot("smoke_tutorial.png")
	tut.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 30:
		await get_tree().process_frame
	_shot("smoke_town.png")
	get_tree().quit()


func _shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name_))
