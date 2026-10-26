extends Node2D
## Checks the Jeweler's Skills tab dropdowns: no shared gem lists; tapping a slot lists the skill
## gems it can take, tapping one shows its card beside it, tapping it again sockets it (or swaps it
## with its slot), Take it out empties it;
## tapping a link lists the supports, picking one links it, a clashing one is greyed out. With a
## window (--out=<folder>) it saves skill_pick.png and support_pick.png.
##   godot --headless --path . res://scratch/test_skill_dropdown.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _rows(tip: ItemTip) -> Array:
	return tip.find_children("*", "Button", true, false).filter(func(b): return b.visible and b.custom_minimum_size.y == SkillGemsPanel.PICK_ROW_H)


func _button(tip: ItemTip, text: String) -> Button:
	for b in tip.find_children("*", "Button", true, false):
		if b.visible and text in b.text:
			return b
	return null


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: GameMenu = town.menu
	GameState.level = 40  # past every skill gem's level
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	town.player.refresh_attributes()
	GameState.skill_gems["whirlwind"] = 1
	GameState.skill_gems["firebolt"] = 1
	menu.open_vendor("jeweler")
	menu.show_panel("skills")
	await get_tree().process_frame
	var sp: SkillGemsPanel = menu.current_panel()
	check(sp.find_children("*", "Label", true, false).all(func(l): return not "SHARED" in l.text), "no shared gem lists")
	var tip := menu.item_tip()
	# A skill slot
	var slot := 3
	GameState.clear_slot_skill(slot)
	sp._pick_skill(slot, Vector2(400, 300))
	await get_tree().process_frame
	var names := _rows(tip).map(func(b): return b.find_children("*", "Label", true, false)[0].text)
	check(names.any(func(t): return "Whirlwind" in t) and names.any(func(t): return "Firebolt" in t), "the slot's dropdown lists your skill gems (%s)" % [names])
	check(_button(tip, "Take it out") == null, "an empty slot has nothing to take out")
	if out != "":
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "skill_pick.png")
	var ww: Button = _rows(tip).filter(func(b): return "Whirlwind" in b.find_children("*", "Label", true, false)[0].text)[0]
	ww.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameState.slot_skill(slot) == "", "one tap doesn't equip it")
	check(tip._cmp.visible and tip._cmp_body.find_children("*", "Label", true, false).any(func(l): return "Whirlwind" in l.text),
		"it shows its card beside the dropdown")
	check(ww.find_children("*", "Label", true, false).any(func(l): return l.visible and "Tap again" in l.text), "and says tap again")
	if out != "":
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "skill_chosen.png")
	ww.pressed.emit()
	check(GameState.slot_skill(slot) == "whirlwind" and GameState.skill_gem_count("whirlwind") == 0, "tapping it again sockets it")
	check(not tip.visible, "and the dropdown closes")
	var main := GameState.slot_skill(0)
	sp._pick_skill(0, Vector2(400, 300))
	await get_tree().process_frame
	var sw: Array = _rows(tip).filter(func(b): return "Whirlwind" in b.find_children("*", "Label", true, false)[0].text)
	check(sw.size() == 1 and sw[0].find_children("*", "Label", true, false).any(func(l): return "swaps" in l.text), "a gem in another slot says it swaps")
	if sw.size() == 1:
		sw[0].pressed.emit()
		sw[0].pressed.emit()
	check(GameState.slot_skill(0) == "whirlwind" and GameState.slot_skill(slot) == main, "picking it swaps the two slots")
	sp._pick_skill(slot, Vector2(400, 300))
	await get_tree().process_frame
	var take := _button(tip, "Take it out")
	check(take != null, "a filled slot has Take it out")
	if take != null:
		take.pressed.emit()
	check(GameState.slot_skill(slot) == "" and GameState.skill_gem_count(main) > 0, "Take it out: back with the shared gems")
	# A support link
	var sups := SkillGemsPanel.owned_supports()
	check(not sups.is_empty(), "there are loose supports to link")
	sp._pick_support(0, 0, Vector2(400, 300))
	await get_tree().process_frame
	var srows := _rows(tip)
	var there: Array = GameState.slot_supports(0)
	var expect := sups.filter(func(r): return there.is_empty() or r != there[0]).size()
	check(srows.size() == expect, "the link's dropdown lists your supports (%d of %d)" % [srows.size(), expect])
	if out != "":
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "support_pick.png")
	var pick: Array = srows.filter(func(b): return not b.disabled)
	if not pick.is_empty():
		var before := GameState.slot_supports(0).duplicate()
		pick[0].pressed.emit()
		check(GameState.slot_supports(0) == before, "one tap on a support doesn't link it")
		pick[0].pressed.emit()
		check(GameState.slot_supports(0) != before, "picking a support links it")
	menu.close()
	print("skill dropdown: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
