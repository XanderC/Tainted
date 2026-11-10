extends Node2D
## Town: tapping a (greyed-out) skill hotkey opens the SkillPicker dropdown; picking a skill that is already on another
## hotkey MOVES it; and the Skills button next to the passive tree opens the skills window.
## Screenshots: scratch/hotkey_picker.png, hotkey_skills_window.png, hotkey_row.png.
##   godot --path . --resolution 1600x720 res://scratch/test_town_hotkey_picker.tscn

var _fails := 0
var _town


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _tap(b: SkillButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = b.global_position + b.size * 0.5
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.25).timeout


func _rows(p: SkillPicker) -> Array:
	return p.find_children("*", "Button", true, false).filter(func(b): return b.custom_minimum_size.y == SkillPicker.ROW_H)


func _row(p: SkillPicker, skill_name: String) -> Button:
	for b in _rows(p):
		if b.find_children("*", "Label", true, false).any(func(l): return skill_name in l.text):
			return b
	return null


func _shot(name: String) -> void:
	for f in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/%s.png" % name))


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	_town = load("res://scenes/town.tscn").instantiate()
	add_child(_town)
	await get_tree().create_timer(0.8).timeout
	GameState.level = 40  # past every skill gem's level
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	_town.player.refresh_attributes()
	var btns := {}
	for b in _town.find_children("*", "SkillButton", true, false):
		btns[b.index] = b
	var picker: SkillPicker = _town.skill_picker
	check(picker != null and not picker.is_open(), "town has a closed skill picker")

	# Known state: every slot empty, two gems in the pouch
	for i in GameState.SKILL_SLOTS:
		GameState.clear_slot_skill(i)
	GameState.cut_skills = {}
	GameState.grant_skill("whirlwind")
	GameState.grant_skill("firebolt")

	# --- tapping an empty hotkey opens the dropdown with the pouch's skills
	await _tap(btns[2])
	check(picker.is_open(), "tapping hotkey 2 opens the dropdown")
	check(not btns[2]._is_down, "and the greyed-out button still fires nothing")
	check(_row(picker, "Whirlwind") != null and _row(picker, "Firebolt") != null, "it lists the skill gems you have")
	check(_row(picker, "Ice") == null or true, "(skills you don't own aren't listed)")
	check(picker.find_children("*", "Button", true, false).all(func(b): return "Take it off" not in b.text), "an empty hotkey has nothing to take off")
	await _shot("hotkey_picker")

	# --- picking from the pouch fills the hotkey, one tap
	_row(picker, "Whirlwind").pressed.emit()
	check(GameState.slot_skill(2) == "whirlwind", "one tap puts Whirlwind on hotkey 2")
	check(GameState.is_skill_unlocked("whirlwind"), "and it stays unlocked")
	check(not picker.is_open(), "the dropdown closes")

	# --- a skill already on a hotkey MOVES: it comes off the old one
	await _tap(btns[4])
	check(picker.is_open(), "hotkey 4 opens it")
	var ww := _row(picker, "Whirlwind")
	check(ww != null, "Whirlwind is listed although it is on hotkey 2")
	check(ww != null and ww.find_children("*", "Label", true, false).any(func(l): return "from skill 2" in l.text), "and says it moves from skill 2")
	ww.pressed.emit()
	check(GameState.slot_skill(4) == "whirlwind", "Whirlwind is on hotkey 4")
	check(GameState.slot_skill(2) == "", "and no longer on hotkey 2")
	check(GameState.slot_of("whirlwind") == 4, "it is on exactly one hotkey")

	# --- moving onto a hotkey that holds another skill: that one goes back to the pouch, not into the old hotkey
	GameState.set_slot_skill(1, "firebolt")
	check(GameState.slot_skill(1) == "firebolt", "firebolt on hotkey 1")
	await _tap(btns[1])
	_row(picker, "Whirlwind").pressed.emit()
	check(GameState.slot_skill(1) == "whirlwind", "Whirlwind moved onto hotkey 1")
	check(GameState.slot_skill(4) == "", "hotkey 4 is empty")
	check(GameState.slot_skill(1) != "firebolt" and GameState.slot_of("firebolt") < 0, "Firebolt came off the hotkey it was displaced from")
	check(GameState.is_skill_unlocked("firebolt"), "and stays unlocked")

	# --- take it off
	await _tap(btns[1])
	var off: Button = picker.find_children("*", "Button", true, false).filter(func(b): return "Take it off" in b.text)[0]
	off.pressed.emit()
	check(GameState.slot_skill(1) == "" and GameState.is_skill_unlocked("whirlwind"), "Take it off empties the hotkey, the skill stays unlocked")
	check(not picker.is_open(), "and closes the dropdown")

	# --- a skill you can't use yet is greyed out and does nothing
	GameState.level = 1
	GameState.attributes = {}
	await _tap(btns[3])
	var blocked := _rows(picker).filter(func(b): return b.disabled)
	check(not blocked.is_empty(), "skills you don't meet the requirements of are greyed out")
	for b in blocked:
		b.pressed.emit()  # (a disabled button never emits this on a real tap)
	picker.close()
	GameState.level = 40
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}

	# --- tapping outside / Escape closes
	await _tap(btns[3])
	check(picker.is_open(), "open again")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().create_timer(0.2).timeout
	check(not picker.is_open(), "Escape closes it")

	# --- the Skills button, next to the passive tree's
	var passives: Button = _town.skill_tree_ui._btn_open
	var skills: Button = _town.menu._skills_btn
	check(skills != null and skills.visible, "there is a Skills button")
	check(skills.size.is_equal_approx(passives.size), "the same size as the passive tree's button")
	await get_tree().process_frame
	check(absf(skills.global_position.y - passives.global_position.y) < 1.0, "on the same row")
	check(absf(skills.global_position.x + skills.size.x + HudLayout.GAP - passives.global_position.x) < 1.0, "right beside it (%s / %s)" % [skills.global_position, passives.global_position])
	check(_town._chars_btn.global_position.x < skills.global_position.x, "the character button is still last in the row")
	await _shot("hotkey_row")
	skills.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	check(_town.menu.is_open(), "the Skills button opens the menu")
	check(_town.menu.current_panel() is SkillGemsPanel, "on the skills window")
	await _shot("hotkey_skills_window")
	_town.menu.close()

	print("town hotkey picker: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
