extends Node2D
## A pet in a rift maze: it finds its way round walls (the maze's path) to the currency lying near the
## player, and never ends up inside a wall while it follows.
##   godot --path . --resolution 1600x720 res://scratch/test_pet_rift.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.pet = "boar"
	GameState.test_map = "twin_oasis"
	var rift = load("res://scenes/main.tscn").instantiate()
	add_child(rift)
	get_tree().current_scene = rift  # the pet asks the current scene for its maze
	await get_tree().create_timer(0.6).timeout
	var player: Player = rift.player
	var pet: Pet = PetDB.node
	check(is_instance_valid(pet), "the pet is in the rift")
	var maze: MazeMap = rift.maze

	# What lies in the maze near the player, some way round: the monsters are asleep, the player stays put
	var spots: Array[Vector2] = []
	for i in 3:
		spots.append(maze.random_floor_near(player.global_position, 350.0, 600.0))
	var drops: Array[CurrencyPickup] = []
	for p in spots:
		var c := CurrencyPickup.new()
		c.kind = "shard"
		c.id = "chaos"
		c.amount = 3
		c.position = p
		rift.add_child(c)
		drops.append(c)

	var in_wall := 0
	for i in 160:  # about 8 seconds
		await get_tree().create_timer(0.05).timeout
		if is_instance_valid(pet) and maze.is_wall(maze.world_to_cell(pet.global_position)):
			in_wall += 1
	var left := 0
	for c in drops:
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			left += 1
	check(left == 0, "it fetched all the drops in the maze (%d left)" % left)
	check(in_wall == 0, "it never stood in a wall (%d samples)" % in_wall)
	check(pet.global_position.distance_to(player.global_position) < 400.0, "and it is back beside the player (%.0f px)" % pet.global_position.distance_to(player.global_position))
	print("pet in the rift: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
