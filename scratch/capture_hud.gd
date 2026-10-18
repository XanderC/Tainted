extends Node2D
## Screenshots of the HUD in the dungeon scene and in town. Needs a window; pass a size to check a phone's shape:
##   godot --path . --resolution 1600x720 res://scratch/capture_hud.tscn


func shot(tag: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/hud_%s_%dx%d.png" % [tag, img.get_width(), img.get_height()]))
	print("saved ", tag)


func _ready() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = scene.player
	p.hp = p.stats.get_stat("max_life") * 0.7
	p.resource = p.max_resource() * 0.45
	GameState.xp = GameState.xp_to_next(GameState.level) * 0.6
	await shot("dungeon")
	var joy: VirtualJoystick = p.joystick
	joy._touch_index = 7
	joy._center = Vector2(260, 520)
	joy._knob = Vector2(320, 480)
	joy.queue_redraw()
	await shot("joystick")
	joy._touch_index = -1
	scene.queue_free()
	await get_tree().process_frame
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	await shot("town")
	get_tree().quit(0)
