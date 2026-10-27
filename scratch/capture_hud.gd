extends Node2D
## Screenshot of the combat HUD with the skill buttons (scratch/hud.png).
## Needs a window:  godot --path . --resolution 1280x720 res://scratch/capture_hud.tscn


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/hud.png"))
	get_tree().quit()
