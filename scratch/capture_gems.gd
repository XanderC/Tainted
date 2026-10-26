extends Node2D
## Screenshot of the Gems tab with a gem of every tier and colour, and some runes (scratch/gems_tab.png).
## Needs a window:  godot --path . --resolution 1280x720 res://scratch/capture_gems.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.gems.clear()
	for type in GemDef.TYPES:
		for tier in range(1, 9):
			GameState.gems[GemDef.make_id(type, tier)] = 1 + tier
	for rank in [1, 2, 6, 12, 20, 27, 33]:
		GameState.gems[SocketRune.all_ids()[rank - 1]] = 3
	var menu: GameMenu = town.menu
	menu.open_vendor("stash")
	menu.show_panel("gems")
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/gems_tab.png"))
	get_tree().quit()
