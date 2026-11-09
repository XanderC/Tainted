extends Node2D
## Town shows the skill buttons, greyed out: tapping one fires nothing (it opens the skill picker, see
## test_town_hotkey_picker). Takes scratch/town_skills.png.
##   godot --path . --resolution 1600x720 res://scratch/test_town_skills.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().create_timer(0.8).timeout
	var btns: Array = town.find_children("*", "SkillButton", true, false)
	check(btns.size() == SkillButton.CENTRES.size(), "town has all %d skill buttons (%d)" % [SkillButton.CENTRES.size(), btns.size()])
	for b in btns:
		check(b.disabled and b.visible, "button %d is shown and disabled" % b.index)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = btns[0].global_position + btns[0].size * 0.5
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.2).timeout
	check(not btns[0]._is_down, "tapping a greyed-out button does nothing")
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/town_skills.png"))
	print("town skills: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
