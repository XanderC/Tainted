extends Node2D
## The weapon set switch is gone: no swap button on the HUD, no I / II in the character panel, no X key,
## and an older save's second weapon set comes back into the bag instead of being lost.
##   godot --path . --resolution 1600x720 res://scratch/test_no_weapon_swap.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var id := GameState.create_character("NoSwap", "warrior")
	check(GameState.select_character(id), "the character is selected")
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	# A save from before: its second set held a sword
	var sword := LootGenerator.roll_item(5, ItemInstance.Rarity.MAGIC, "weapon")
	sword.identify()
	var name_in_save := sword.display_name
	GameState._pending_alt_set = {"weapon": sword.to_dict()}
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().create_timer(0.8).timeout
	var p: Player = town.player
	var found := false
	for it in p.inventory:
		if it.display_name == name_in_save:
			found = true
	for it in GameState.stash.items():
		if it.display_name == name_in_save:
			found = true
	check(found, "the old second set's weapon is in the bag (or the stash)")
	check(GameState._pending_alt_set.is_empty(), "and the old set is cleared")
	check(not p.has_method("swap_weapon_set"), "the player can't swap sets")
	check(town.find_children("*", "WeaponSwapButton", true, false).is_empty() if ClassDB.class_exists("WeaponSwapButton") else true, "no swap button")
	for b in town.find_children("*", "Button", true, false):
		check((b as Button).text != "II", "no II button")
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.pressed = true
	p.equipment.clear()
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.2).timeout
	GameState.save()
	var f := FileAccess.open(GameState._char_path(id), FileAccess.READ)
	var saved = JSON.parse_string(f.get_as_text()) if f != null else {}
	check(not saved.has("alt_weapon_set") and not saved.has("active_weapon_set"), "the save no longer has weapon sets")
	GameState.delete_character(id)
	print("no weapon swap: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
