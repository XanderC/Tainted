extends Node2D
## Pets (PetDB, Pet): one trots beside the player and fetches the currency lying near them, as tapping
## it would (to the stash), but leaves gear alone, leaves what lies far from the player and Town Portal
## scrolls the player can't carry; choosing another pet in Options swaps it at once, "None" removes it.
## Takes scratch/pets.png (all of them) and scratch/pet_options.png.
##   godot --path . --resolution 1600x720 res://scratch/test_pet.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.2) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.pet = "hedgehog"
	GameState.tp_scrolls = 3
	var zone = load("res://scenes/town.tscn").instantiate()
	add_child(zone)
	await settle(0.6)
	var player: Player = zone.player
	var pet: Pet = PetDB.node

	check(is_instance_valid(pet) and pet.is_inside_tree(), "a pet is in the scene")
	check(pet.id == "hedgehog", "it is the one chosen")
	check(pet.global_position.distance_to(player.global_position) < 200.0, "it starts beside the player")

	# It follows
	player.global_position += Vector2(0, -500)
	await settle(2.5)
	check(pet.global_position.distance_to(player.global_position) < 220.0, "it keeps up with the player (%.0f px)" % pet.global_position.distance_to(player.global_position))

	# It fetches currency lying near the player
	var shards_before := GameState.shard_count("alchemy") + 1000 * GameState.orb_count("alchemy")
	var near := CurrencyPickup.new()
	near.kind = "shard"
	near.id = "alchemy"
	near.amount = 4
	near.position = player.global_position + Vector2(300, 80)
	zone.add_child(near)
	var bundle := CurrencyPickup.add_to_bundle(zone, "Currency", ["orb", "chaos", 2], player.global_position + Vector2(-320, 60))
	var chaos_before := GameState.orb_count("chaos")
	await settle(4.0)
	check(not is_instance_valid(near) or near.is_queued_for_deletion(), "it took the shards lying near the player")
	check(not is_instance_valid(bundle) or bundle.is_queued_for_deletion(), "and the pile of currency")
	check(GameState.shard_count("alchemy") + 1000 * GameState.orb_count("alchemy") > shards_before, "the shards reached the stash")
	check(GameState.orb_count("chaos") == chaos_before + 2, "so did the orbs (%d -> %d)" % [chaos_before, GameState.orb_count("chaos")])

	# It leaves gear alone
	var gear := LootPickup.new()
	gear.item = LootGenerator.roll_item(5, 0)
	gear.position = player.global_position + Vector2(200, 40)
	zone.add_child(gear)
	# ... and what lies far from the player (beyond its reach of them)
	var far := CurrencyPickup.new()
	far.kind = "shard"
	far.id = "alchemy"
	far.position = player.global_position + Vector2(Pet.SEEK + 400.0, 0)
	zone.add_child(far)
	# ... and scrolls the player can carry no more of
	GameState.tp_scrolls = GameState.MAX_SCROLLS
	var scroll := CurrencyPickup.new()
	scroll.kind = "scroll"
	scroll.id = "town_portal"
	scroll.position = player.global_position + Vector2(-200, -60)
	zone.add_child(scroll)
	await settle(3.5)
	check(is_instance_valid(gear) and not gear.is_queued_for_deletion(), "it leaves gear for the player")
	check(is_instance_valid(far) and not far.is_queued_for_deletion(), "it leaves what lies far from the player")
	check(is_instance_valid(scroll) and not scroll.is_queued_for_deletion(), "it leaves a scroll the player can't carry")
	GameState.tp_scrolls = 3
	await settle(3.0)
	check(not is_instance_valid(scroll) or scroll.is_queued_for_deletion(), "and takes it once there is room")
	check(GameState.tp_scrolls == 4, "the scroll was added (%d)" % GameState.tp_scrolls)

	# Pets can't be hurt or block: no collision with anything but walls
	check(pet.collision_layer == 0 and pet.collision_mask == 1, "it only collides with walls")

	# Choosing another pet
	GameState.set_pet("boar")
	await settle(0.5)
	check(is_instance_valid(PetDB.node) and PetDB.node.id == "boar" and PetDB.node != pet, "choosing the boar swaps the pet")
	check(not is_instance_valid(pet) or pet.is_queued_for_deletion(), "the old one is gone")
	GameState.set_pet("bee")
	await settle(0.5)
	check(PetDB.node.id == "bee", "and the bee")
	var bee_shard := CurrencyPickup.new()
	bee_shard.kind = "shard"
	bee_shard.id = "alchemy"
	bee_shard.position = player.global_position + Vector2(-250, 100)
	zone.add_child(bee_shard)
	await settle(3.5)
	check(not is_instance_valid(bee_shard) or bee_shard.is_queued_for_deletion(), "a flying pet fetches too")
	GameState.set_pet("nonsense")
	check(GameState.pet == "bee", "an unknown pet is refused")

	# The Options window steps through them
	var btn := _find_button(zone.menu, "⚙")
	btn.pressed.emit()
	await settle(0.3)
	var ui: Node = null
	for c in zone.menu.get_children():
		if c is OptionsUI:
			ui = c
	check(ui != null, "the Options window opens")
	var next := _find_button(ui, "▶")
	check(next != null, "it has a pet selector")
	next.pressed.emit()  # bee -> bird
	await settle(0.4)
	check(GameState.pet == "bird", "stepping on goes to the next pet")
	next.pressed.emit()  # bird -> none (the list wraps)
	await settle(0.4)
	check(GameState.pet == "", "stepping on from the last pet is none")
	check(not is_instance_valid(PetDB.node) or PetDB.node.is_queued_for_deletion(), "and the pet goes")
	next.pressed.emit()
	await settle(0.5)
	check(GameState.pet == "hedgehog" and is_instance_valid(PetDB.node) and PetDB.node.id == "hedgehog", "and round to the hedgehog again")
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/pet_options.png"))
	var done := _find_button(ui, "Done")
	done.pressed.emit()
	await settle(0.3)

	# PetDB.step wraps both ways
	check(PetDB.step("", -1) == "bird" and PetDB.step("bird", 1) == "", "the list wraps both ways")

	# All three side by side, for a look
	var shots: Array[Pet] = []
	for i in PetDB.PETS.size():
		var p := Pet.new()
		p.owner_player = player
		p.id = PetDB.PETS.keys()[i]
		p.position = player.global_position + Vector2(-480 + i * 120, 150)
		p._warped = true  # stays where it was put
		zone.add_child(p)
		shots.append(p)
	GameState.pet = ""
	PetDB.node.queue_free()
	await settle(0.1)
	for p in shots:
		p.set_physics_process(false)  # stand still for the picture
	await settle(0.4)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/pets.png"))

	print("pets: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _find_button(from: Node, text_part: String) -> Button:
	for c in from.find_children("*", "Button", true, false):
		if (c as Button).text.contains(text_part):
			return c
	return null
