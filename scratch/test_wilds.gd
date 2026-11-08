extends Node2D
## The Blackroot Wilds (Act I, Chapter 1: The First Incursion): the map's things stand on open ground, the zone's packs
## are the Wilds' own kinds, and the chapter plays through in the real zone: eight briarwolves at the gate, the hunting
## lodge, the Briarwolf Alpha (his intro, his pack answering at half life, his death), the rift shard, Dennis. Then the
## town has Althea and Corwin. Takes scratch/wilds_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_wilds.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name_))


func _enemies(zone: Node, kind := "") -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return is_instance_valid(e) and zone.is_ancestor_of(e) and not e._dead and (kind == "" or e.kind == kind))


func _kill(e: Enemy) -> void:
	e._shield_t = 0.0
	e.take_damage(e.max_hp * 100.0 * PartyScale.life())


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {}
	GameState.waypoints = []

	# The map: everything stands on open ground
	var data := MapData.load_map("dune_wastes")
	check(String(data.name) == "Blackroot Wilds" and ActDB.zone_name("dune_wastes") == "Blackroot Wilds", "the zone is the Blackroot Wilds")
	var grid: Array = data.grid
	var cell: float = float(data.cell)
	for o in data.objects:
		if o.type in ["start", "portal", "waypoint", "npc", "boss", "quest_object", "trigger"]:
			var cx := int(float(o.x) / cell)
			var cy := int(float(o.y) / cell)
			check(String(grid[cy])[cx] == ".", "%s %s stands on open ground" % [o.type, o.get("id", "")])
	var ids := {}
	for o in data.objects:
		ids["%s:%s" % [o.type, o.get("id", "")]] = true
	for want in ["npc:dennis", "boss:briar_alpha", "quest_object:rift_shard", "quest_object:lockbox", "trigger:hunting_lodge", "trigger:ruined_manor", "waypoint:", "portal:"]:
		check(ids.has(want), "the map has %s" % want)

	# Roads: the autotiler picks each quarter's piece, and the map lays its paths on open ground
	var alone := func(cells: Array) -> Callable:
		return func(c: Vector2i) -> bool: return cells.has(c)
	check(Array(RoadTiles.pick(alone.call([Vector2i(5, 5)]), Vector2i(5, 5))) == [1, 3, 7, 9], "a lone path cell is four outer corners")
	var row: Array = [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5)]
	check(Array(RoadTiles.pick(alone.call(row), Vector2i(5, 5))) == [2, 2, 8, 8], "the middle of a horizontal path is top and bottom edges")
	check(Array(RoadTiles.pick(alone.call(row), Vector2i(4, 5))) == [1, 2, 7, 8], "its end turns the corners")
	var col: Array = [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)]
	check(Array(RoadTiles.pick(alone.call(col), Vector2i(5, 5))) == [4, 6, 4, 6], "the middle of a vertical path is left and right edges")
	var plus: Array = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6)]
	check(Array(RoadTiles.pick(alone.call(plus), Vector2i(5, 5))) == [13, 12, 11, 10], "a crossing has inner corners")
	check(RoadTiles.pick(alone.call([Vector2i(5, 5)]), Vector2i(5, 5), true)[0] == 14, "cobblestone is the second set (14 ...)")
	var roads: Array = data.get("roads", [])
	check(roads.size() == grid.size() and String(roads[0]).length() == String(grid[0]).length(), "the map has a roads layer the size of its grid")
	var on_wall := 0
	var road_cells := 0
	for y in roads.size():
		for x in String(roads[y]).length():
			if String(roads[y])[x] != ".":
				road_cells += 1
				if String(grid[y])[x] == "#":
					on_wall += 1
	check(road_cells > 100 and on_wall == 0, "paths lie on open ground (%d cells, %d on walls)" % [road_cells, on_wall])

	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "town"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.0)
	var player: Player = zone.player

	# Its monsters are the Wilds' own
	var allowed: Array = ActDB.zone("dune_wastes").kinds
	var foreign := 0
	for e in _enemies(zone):
		if not e.is_boss and String(e.pack).begins_with("zpack_") and not (e.kind in allowed):  # (a random encounter brings its own: cultists, a cottage's zombies)
			foreign += 1
	check(foreign == 0, "no monsters but the Wilds' own kinds (%d others)" % foreign)
	check(_enemies(zone, "briarwolf").size() >= 20, "briarwolves hunt the Wilds (%d)" % _enemies(zone, "briarwolf").size())
	check(_enemies(zone).size() > 100, "and it is full of monsters (%d)" % _enemies(zone).size())
	shot("wilds_start.png")

	# Chapter 1: the gate
	var q := "a1_first_incursion"
	Quests.start(q)
	var wolves := _enemies(zone, "briarwolf").filter(func(e): return not e.is_boss)
	wolves.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	var near_gate := wolves.slice(0, 8)
	for e in near_gate:
		check(e.global_position.distance_to(player.global_position) < 2500.0, "a briarwolf pack is near the gate road")
		break
	for e in near_gate:
		_kill(e)
	await settle(0.3)
	check(Quests.current_step(q).get("key", "") == "hunting_lodge", "eight briarwolves down: on to the lodge")

	# The lodge
	var lodge := Vector2.ZERO
	var home := Vector2.ZERO
	for o in data.objects:
		if o.type == "trigger" and o.id == "hunting_lodge":
			lodge = Vector2(float(o.x), float(o.y))
		if o.type == "boss":
			home = Vector2(float(o.x), float(o.y))
	player.global_position = lodge + Vector2(-300, 60)
	await settle(0.5)
	check(Quests.current_step(q).get("key", "") == "briar_alpha", "reaching the lodge: now the Alpha")
	var dennis_near := false
	for i in get_tree().get_nodes_in_group("interactables"):
		if i.prompt.contains("Dennis"):
			dennis_near = true
	check(dennis_near, "Scout Captain Dennis is at the lodge")
	shot("wilds_lodge.png")

	# The Alpha: intro, his own moves, his pack at half life, his death
	var boss: Enemy = zone._boss
	check(boss != null and boss.is_boss and String(boss.get_meta("boss_id", "")) == "briar_alpha" and boss.brain != null, "the Alpha has a boss fight")
	check(boss.kind == "briarwolf" and boss.display_name == "The Briarwolf Alpha", "he is the pack leader (%s)" % boss.display_name)
	player.global_position = home + Vector2(-330, 0)
	var waited := 0.0
	while boss.brain.state == BossBrain.S.SLEEP and waited < 3.0:
		await settle(0.1)
		waited += 0.1
	check(boss.brain.state != BossBrain.S.SLEEP, "he wakes when you come near")
	await settle(2.2)
	check(boss._shield_t <= 0.0, "his intro is over and he can be hurt")
	shot("wilds_alpha.png")
	var hp0 := boss.hp
	boss.take_damage(10.0)
	check(boss.hp < hp0, "a blow lands")
	var adds0 := get_tree().get_nodes_in_group("boss_adds").size()
	boss.hp = boss.max_hp * 0.45
	await settle(2.5)
	check(boss.brain.phase == 1, "at half life he enters his second phase")
	check(get_tree().get_nodes_in_group("boss_adds").size() > adds0, "his pack answers his howl")
	for a in get_tree().get_nodes_in_group("boss_adds"):
		check(a.kind == "briarwolf", "the ones that answer are briarwolves")
		break
	_kill(boss)
	await settle(0.8)
	check(boss._dead, "he dies")
	check(Quests.current_step(q).get("key", "") == "rift_shard", "the shard is next")
	await settle(0.4)
	var shard = null
	for qo in zone._quest_objects:
		if qo.id == "rift_shard":
			shard = qo.node
	check(shard != null and shard.visible, "the Coagulated Rift Shard shows where the Alpha fell")
	shot("wilds_shard.png")
	shard.action.call()
	check(Quests.current_step(q).get("key", "") == "dennis", "taking it: back to Dennis")
	Quests.notify("talk", "dennis")
	check(Quests.state(q) == Quests.READY and Quests.npc_marker("althea") == "?", "ready to hand in to Althea")

	# The manor and its lockbox
	var h := "a1_lost_heirloom"
	Quests.start(h)
	var manor := Vector2.ZERO
	for o in data.objects:
		if o.type == "trigger" and o.id == "ruined_manor":
			manor = Vector2(float(o.x), float(o.y))
	player.global_position = manor + Vector2(-260, 80)
	await settle(0.6)
	check(Quests.current_step(h).get("key", "") == "lockbox", "reaching the manor: now the lockbox")
	await settle(0.4)
	var box = null
	for qo in zone._quest_objects:
		if qo.id == "lockbox":
			box = qo.node
	check(box != null and box.visible, "the lockbox is there to open")
	shot("wilds_manor.png")
	box.action.call()
	check(Quests.state(h) == Quests.READY, "opening it: back to Corwin")
	zone.queue_free()
	await settle(0.4)

	# The town: Althea and Corwin
	GameState.current_zone = ""
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await settle(0.8)
	var prompts: Array = []
	for i in get_tree().get_nodes_in_group("interactables"):
		prompts.append(i.prompt)
	check(prompts.any(func(t): return t.contains("Althea")), "Althea is in town (%s)" % [prompts])
	check(prompts.any(func(t): return t.contains("Corwin")), "so is Corwin")
	check(not prompts.any(func(t): return t.contains("Hesk")), "and Hesk is gone")
	check(town._hud.text.begins_with("Oakhaven Outpost"), "the town is Oakhaven Outpost")
	shot("wilds_town.png")

	print("wilds: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
