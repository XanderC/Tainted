extends Node2D
## Map terrain, on Oakhaven Outpost (the town is a map now): the river is water (walls you can't cross) and its bridge is
## floor with a deck; the terrace is raised floor with a ring of wall round it and steps up the cliff; the roads are laid
## on open ground; and the town's people stand well apart (no crowding). Walks the player into the river, over the bridge,
## up the steps and into the terrace's edge. Takes scratch/terrain_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_terrain.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name_))


## Walks `p` with velocity `v` for `frames` physics frames.
func walk(p: Player, v: Vector2, frames: int) -> void:
	for i in frames:
		p.velocity = v
		p.move_and_slide()
		await get_tree().physics_frame


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var data := MapData.load_map("oakhaven")
	check(String(data.name) == "Oakhaven Outpost" and ActDB.TOWN_NAME == "Oakhaven Outpost", "the town is Oakhaven Outpost's map")
	var maze := MazeMap.new()
	maze.setup("oakhaven")

	# The river: water is a wall, a bridge is floor
	var water := 0
	var bridges := 0
	for y in maze.rows:
		for x in maze.cols:
			var c := Vector2i(x, y)
			if maze.is_water(c):
				water += 1
				check(maze.is_wall(c), "river cell %s is a wall" % c)
			if maze.is_bridge(c):
				bridges += 1
				check(not maze.is_wall(c) and not maze.is_water(c), "the bridge at %s is floor" % c)
	check(water > 25 and bridges == 1, "a river (%d cells) with its bridge (%d)" % [water, bridges])
	check(maze.line_clear(Vector2(30.5 * 128, 20 * 128), Vector2(28 * 128, 20 * 128)), "a river doesn't block a clear line")

	# The terrace: footprint, floor inside, wall ring, steps
	var terraces := MapData.objects_of(data, "terrace")
	check(terraces.size() == 1, "one terrace")
	var t: Dictionary = terraces[0]
	var tx := int(t.x)
	var ty := int(t.y)
	var tw := int(t.w)
	var th := int(t.h)
	check(maze.is_terrace(Vector2i(tx, ty)) and maze.is_wall(Vector2i(tx, ty)), "its ring is wall")
	check(maze.is_terrace(Vector2i(tx + 3, ty + 3)) and not maze.is_wall(Vector2i(tx + 3, ty + 3)), "its middle is floor")
	for sx in t.stairs:
		var c := Vector2i(tx + int(sx), ty + th - 1)
		check(not maze.is_wall(c), "the steps at %s are floor" % c)
	check(maze.is_wall(Vector2i(tx + 2, ty + th - 1)), "the cliff face beside the steps is wall")
	check(not maze.is_terrace(Vector2i(tx - 3, ty + 4)), "outside the footprint is not the terrace")

	# Roads lie on open ground (not on walls or water)
	var roads: Array = data.get("roads", [])
	var bad := 0
	for y in roads.size():
		for x in String(roads[y]).length():
			if String(roads[y])[x] != "." and maze.is_wall(Vector2i(x, y)):
				bad += 1
	check(roads.size() == maze.rows and bad == 0, "roads on open ground (%d bad)" % bad)

	# The people stand well apart, and everyone can be reached from the start
	var spots := {}
	for o in data.objects:
		if o.type == "marker":
			spots[String(o.id)] = Vector2(float(o.x), float(o.y))
	var npcs: Array = spots.keys().filter(func(k): return k.begins_with("npc_"))
	check(npcs.size() == 11, "eleven people (%d)" % npcs.size())
	var nearest := 1.0e9
	for i in npcs.size():
		for j in range(i + 1, npcs.size()):
			nearest = minf(nearest, (spots[npcs[i]] as Vector2).distance_to(spots[npcs[j]]))
	check(nearest >= 4.0 * 128.0, "no two people closer than 4 cells, 512 px (nearest %.1f)" % (nearest / 128.0))
	var seen := {maze.world_to_cell(spots.spawn): true}
	var queue: Array = [maze.world_to_cell(spots.spawn)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not seen.has(n) and not maze.is_wall(n):
				seen[n] = true
				queue.append(n)
	for k in spots:
		check(seen.has(maze.world_to_cell(spots[k])), "%s can be reached from the start" % k)

	# In the town itself
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await settle(0.8)
	var player: Player = town.player
	player.can_fight = false
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	# Into the river: stopped by it
	player.global_position = Vector2(29.5, 22.5) * 128.0 - Vector2(300, 0)
	await walk(player, Vector2(300, 0), 60)
	check(player.global_position.x < 29.0 * 128.0, "the river stops the player (x = %.1f cells)" % (player.global_position.x / 128.0))
	# Over the bridge
	player.global_position = Vector2(30.0, 17.5) * 128.0
	await walk(player, Vector2(300, 0), 60)
	check(player.global_position.x > 32.2 * 128.0, "the bridge takes the player across (x = %.1f cells)" % (player.global_position.x / 128.0))
	shot("terrain_bridge.png")
	# Up the steps: from below the cliff, north through the stair cells
	var sx0 := tx + int(t.stairs[0])
	player.global_position = Vector2(sx0 + 0.9, ty + th + 1.5) * 128.0
	await walk(player, Vector2(0, -300), 80)
	check(player.global_position.y < (ty + th - 1.0) * 128.0, "the steps lead up onto the terrace (y = %.1f cells)" % (player.global_position.y / 128.0))
	await settle(0.4)
	shot("terrain_terrace.png")
	# Along the terrace: the ring holds the edge
	player.global_position = Vector2(tx + 4.5, ty + 3.5) * 128.0
	await walk(player, Vector2(-300, 0), 80)
	check(player.global_position.x > (tx + 0.9) * 128.0, "the terrace's edge holds (x = %.1f cells, edge at %d)" % [player.global_position.x / 128.0, tx + 1])
	# Not through the cliff beside the steps
	player.global_position = Vector2(tx + 3.5, ty + th - 2.5) * 128.0
	await walk(player, Vector2(0, 300), 80)
	check(player.global_position.y < (ty + th - 0.9) * 128.0, "the cliff face holds (y = %.1f cells)" % (player.global_position.y / 128.0))
	# The square
	player.global_position = Vector2(17.5, 19.5) * 128.0
	await settle(0.4)
	shot("terrain_square.png")
	print("terrain: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
