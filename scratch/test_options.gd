extends Node2D
## The Options window and the camera zoom it sets: the button under BAG opens it and pauses the game, the
## slider and the step buttons zoom every camera as they move, Reset, Done and Escape close it, the zoom is
## clamped and kept on the device, and a new scene starts at the saved zoom. Takes scratch/options.png.
##   godot --path . --resolution 1600x720 res://scratch/test_options.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _ready() -> void:
	var kept := GameCamera.zoom()  # what is saved now, put back at the end
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameCamera.set_zoom(GameCamera.DEFAULT_ZOOM)

	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await settle()
	var cam: Camera2D = town.player.get_child(town.player.get_child_count() - 1) if false else _camera(town)
	check(cam != null, "the town has a game camera")
	check(is_equal_approx(cam.zoom.x, 0.75), "the camera starts at the saved zoom (%.2f)" % cam.zoom.x)

	# The button under BAG
	var btn := _find_button(town.menu, "OPTIONS")
	check(btn != null and btn.visible, "an Options button is on screen")
	btn.pressed.emit()
	await settle()
	var ui := _find(town.menu, "OptionsUI")
	check(ui != null, "the window opens")
	check(get_tree().paused, "the game is paused while it is open")
	check(not btn.visible, "the button is out of the way meanwhile")

	var slider: HSlider = _find_type(ui, "HSlider")
	check(is_equal_approx(slider.value, 0.75), "the slider shows the zoom (%.2f)" % slider.value)
	slider.value = 0.5  # as if dragged
	await settle()
	check(is_equal_approx(cam.zoom.x, 0.5), "dragging zooms the camera at once (%.2f)" % cam.zoom.x)
	check(GameCamera.text(15) == 30, "world text is sized for it (%d)" % GameCamera.text(15))
	var more := _find_button(ui, "+")
	var less := _find_button(ui, "−")
	check(less.disabled and not more.disabled, "at the far end only + works")
	more.pressed.emit()
	await settle()
	check(is_equal_approx(cam.zoom.x, 0.55) and is_equal_approx(slider.value, 0.55), "+ steps it (%.2f)" % cam.zoom.x)
	GameCamera.set_zoom(0.6)
	await settle()
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/options.png"))

	_find_button(ui, "Reset").pressed.emit()
	await settle()
	check(is_equal_approx(cam.zoom.x, 0.75) and is_equal_approx(slider.value, 0.75), "Reset goes back to the default")
	slider.value = 0.9
	await settle()
	_find_button(ui, "Done").pressed.emit()
	await settle()
	check(not is_instance_valid(ui) or ui.is_queued_for_deletion(), "Done closes it")
	check(not get_tree().paused, "and the game goes on")
	var cfg := ConfigFile.new()
	cfg.load(Options.FILE)
	check(is_equal_approx(float(cfg.get_value("view", "zoom", -1.0)), 0.9), "the zoom is kept on the device (%s)" % str(cfg.get_value("view", "zoom", "none")))

	# Escape closes it too
	btn.pressed.emit()
	await settle()
	ui = _find(town.menu, "OptionsUI")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await settle()
	check(ui == null or not is_instance_valid(ui) or ui.is_queued_for_deletion(), "Escape closes it")
	check(not get_tree().paused, "Escape lets the game go on")

	# Out-of-range values are held to the ends
	GameCamera.set_zoom(5.0)
	check(is_equal_approx(GameCamera.zoom(), GameCamera.MAX_ZOOM), "too close is held to the limit")
	GameCamera.set_zoom(0.1)
	check(is_equal_approx(GameCamera.zoom(), GameCamera.MIN_ZOOM), "too far is held to the limit")

	# A new scene starts at the zoom that was kept
	GameCamera.set_zoom(0.65)
	town.queue_free()
	await settle()
	var zone_node = _new_zone()
	await settle()
	var zcam := _camera(zone_node)
	check(zcam != null and is_equal_approx(zcam.zoom.x, 0.65), "a new scene's camera starts at the kept zoom")

	GameCamera.set_zoom(kept)
	print("options: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _new_zone() -> Node:
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var z = load("res://scenes/zone.tscn").instantiate()
	add_child(z)
	return z


func _camera(scene: Node) -> Camera2D:
	for c in get_tree().get_nodes_in_group(GameCamera.GROUP):
		if scene.is_ancestor_of(c):
			return c
	return null


func _find(from: Node, class_: String) -> Node:
	for c in from.get_children():
		if c.get_script() != null and String(c.get_script().get_global_name()) == class_:
			return c
	return null


func _find_type(from: Node, type_: String) -> Node:
	for c in from.find_children("*", type_, true, false):
		return c
	return null


func _find_button(from: Node, text_part: String) -> Button:
	for c in from.find_children("*", "Button", true, false):
		if (c as Button).text.contains(text_part):
			return c
	return null
