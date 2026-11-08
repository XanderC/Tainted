extends Node2D
## The pet with a real character, which the other pet tests don't have (their save() does nothing): equip
## one in Options, see it saved, and play the character again from the save.
## Makes a character on this device and deletes it again.
##   godot --path . --resolution 1600x720 res://scratch/test_pet_save.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var id := GameState.create_character("PetTest", "warrior")
	check(GameState.select_character(id), "the character is selected")
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	check(GameState.pet == "", "a new character has no pet")

	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await settle(0.6)
	var btn := _find_button(town.menu, "OPTIONS")
	btn.pressed.emit()
	await settle(0.4)
	var ui: Node = null
	for c in town.menu.get_children():
		if c is OptionsUI:
			ui = c
	check(ui != null, "the Options window opens")
	var next := _find_button(ui, "▶")
	next.pressed.emit()  # none -> hedgehog
	await settle(1.0)
	check(GameState.pet == "hedgehog", "the hedgehog is chosen (%s)" % GameState.pet)
	check(is_instance_valid(PetDB.node) and PetDB.node.id == "hedgehog", "and is beside the player")
	check(not get_tree().paused, "the game is not paused while the window is open")
	var t0: float = PetDB.node._t
	await settle(0.6)
	check(PetDB.node._t > t0 + 0.4, "the pet is alive and animating with the window still open")
	await settle(1.4)

	# What was saved
	var f := FileAccess.open(GameState._char_path(id), FileAccess.READ)
	var saved = JSON.parse_string(f.get_as_text()) if f != null else null
	check(saved is Dictionary and saved.get("pet", "") == "hedgehog", "the pet is in the character's save")

	# Play the character again from the save
	_find_button(ui, "Done").pressed.emit()
	await settle(0.3)
	town.queue_free()
	await settle(0.3)
	GameState.pet = ""
	check(GameState.select_character(id), "the character loads again")
	check(GameState.pet == "hedgehog", "with its pet (%s)" % GameState.pet)
	var town2 = load("res://scenes/town.tscn").instantiate()
	add_child(town2)
	await settle(1.0)
	check(is_instance_valid(PetDB.node) and PetDB.node.id == "hedgehog", "and it is there in the new scene")

	# A zone and a rift with it
	town2.queue_free()
	await settle(0.3)
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.5)
	check(is_instance_valid(PetDB.node) and PetDB.node.is_inside_tree(), "and in a zone")
	zone.queue_free()
	await settle(0.3)
	var rift = load("res://scenes/main.tscn").instantiate()
	add_child(rift)
	await settle(1.5)
	check(is_instance_valid(PetDB.node) and PetDB.node.is_inside_tree(), "and in a rift")

	GameState.delete_character(id)
	print("pet save: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _find_button(from: Node, text_part: String) -> Button:
	for c in from.find_children("*", "Button", true, false):
		if (c as Button).text.contains(text_part):
			return c
	return null
