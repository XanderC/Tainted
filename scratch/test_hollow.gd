extends Node2D
## Act I phase 2: the Weeping Hollow (Chapter 2, Poisoning the Well: the cave theme, the tainted river and its bridges, the
## Brood Cyst, Skittering Matron Vhol, the Purge Ward) and the Sunken Fen (mire that slows you, A Taste for Rot with its
## choice of reward), and the ways between them and the Blackroot Wilds. Takes scratch/hollow_*.png and fen_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_hollow.tscn

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


## Everything the map puts on open ground and reachable from its start (a flood fill over its floor).
func check_map(id: String) -> Dictionary:
	var data := MapData.load_map(id)
	var grid: Array = data.grid
	var cell: float = float(data.cell)
	var start := Vector2i.ZERO
	for o in data.objects:
		if o.type == "start":
			start = Vector2i(int(float(o.x) / cell), int(float(o.y) / cell))
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y >= 0 and n.y < grid.size() and n.x >= 0 and n.x < String(grid[0]).length() and String(grid[n.y])[n.x] == "." and not seen.has(n):
				seen[n] = true
				queue.append(n)
	for o in data.objects:
		if o.type in ["start", "portal", "waypoint", "npc", "boss", "quest_object", "trigger"]:
			var c := Vector2i(int(float(o.x) / cell), int(float(o.y) / cell))
			check(seen.has(c), "%s: %s %s is on open ground you can reach" % [id, o.type, o.get("id", o.get("target", ""))])
	return data


## The bosses hit as hard as they do for a character of the level the story has brought you to (BossDB "power"): this one has the life for it.
func _tough(p: Player) -> void:
	p.stats.add_mod("max_life", StatBlock.ModType.FLAT, 20000.0, "test")
	p.hp = p.stats.get_stat("max_life")


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {}
	GameState.waypoints = []

	# The maps and the ways between them
	var wilds := check_map("dune_wastes")
	var hollow := check_map("weeping_hollow")
	var fen := check_map("sunken_fen")
	var targets := []
	for o in wilds.objects:
		if o.type == "portal":
			targets.append(String(o.target))
	check("weeping_hollow" in targets and "sunken_fen" in targets and "town" in targets, "the Wilds lead to town, the Hollow and the Fen (%s)" % [targets])
	check(ActDB.zone("weeping_hollow").map == "weeping_hollow" and ActDB.zone("sunken_fen").map == "sunken_fen", "both are zones")
	check(String(hollow.theme) == "hollow" and FileAccess.file_exists("res://assets/tiles/hollow/bg.png"), "the Hollow has its own cave look")
	check(MapData.objects_of(hollow, "boss")[0].id == "matron_vhol" and BossDB.has("matron_vhol"), "Matron Vhol has a boss fight")
	check(MapData.objects_of(fen, "npc")[0].id == "voss", "Voss is in the Fen")
	var water := 0
	var bridges := 0
	var mire := 0
	for row in hollow.water:
		water += String(row).count("~")
		bridges += String(row).count("=")
	for row in fen.water:
		mire += String(row).count(",")
	check(water > 30 and bridges == 2, "the Hollow's tainted river (%d cells) has two bridges (%d)" % [water, bridges])
	check(mire > 100, "the Fen has mire (%d cells)" % mire)

	# The mire slows
	var fm := MazeMap.new()
	fm.setup("sunken_fen")
	var wet := Vector2i(-1, -1)
	var dry := Vector2i(-1, -1)
	for y in fm.rows:
		for x in fm.cols:
			var c := Vector2i(x, y)
			if wet.x < 0 and fm.is_mire(c):
				wet = c
			if dry.x < 0 and not fm.is_wall(c) and not fm.is_mire(c) and x > 10 and y > 10:
				dry = c
	check(is_equal_approx(MazeMap.slow_at(fm.cell_center(wet)), MazeMap.MIRE_SLOW), "mire slows (%.2f)" % MazeMap.slow_at(fm.cell_center(wet)))
	check(MazeMap.slow_at(fm.cell_center(dry)) == 1.0, "dry ground doesn't")
	fm.free()

	# Chapter 2 needs Chapter 1
	var ch2 := "a1_poisoning_the_well"
	check(not Quests.available(ch2), "Althea has nothing for you before the first chapter is done")
	GameState.quests["a1_first_incursion"] = {"state": Quests.DONE, "step": 5, "count": 0}
	check(Quests.available(ch2) and Quests.npc_marker("althea") == "!", "after it she has the well for you")
	Quests.start(ch2)
	check(Quests.current_step(ch2).key == "weeping_hollow", "it starts at the Hollow")

	# The Weeping Hollow
	GameState.current_zone = "weeping_hollow"
	GameState.zone_entry = "dune_wastes"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.0)
	var player: Player = zone.player
	_tough(player)
	check(Quests.current_step(ch2).key == "brood_cyst", "entering the Hollow is the first step")
	var allowed: Array = ActDB.zone("weeping_hollow").kinds
	var foreign := 0
	for e in _enemies(zone):
		if not e.is_boss and String(e.pack).begins_with("zpack_") and not (e.kind in allowed):
			foreign += 1
	check(foreign == 0 and _enemies(zone).size() > 60, "the caves hold the Hollow's own monsters (%d, %d foreign)" % [_enemies(zone).size(), foreign])
	check(player.global_position.distance_to(zone.maze.portal_pos) < 600.0, "arriving from the Wilds puts you at the cave mouth")
	shot("hollow_start.png")
	var cyst := Vector2.ZERO
	var home := Vector2.ZERO
	for o in hollow.objects:
		if o.type == "trigger" and o.id == "brood_cyst":
			cyst = Vector2(float(o.x), float(o.y))
		if o.type == "boss":
			home = Vector2(float(o.x), float(o.y))
	player.global_position = cyst + Vector2(-300, 120)
	await settle(0.6)
	check(Quests.current_step(ch2).key == "matron_vhol", "reaching the cyst: now its guardian")
	var boss: Enemy = zone._boss
	check(boss != null and boss.brain != null and String(boss.get_meta("boss_id")) == "matron_vhol", "Matron Vhol is there with her fight")
	player.global_position = home + Vector2(-380, 40)
	var waited := 0.0
	while boss.brain.state == BossBrain.S.SLEEP and waited < 3.0:
		await settle(0.1)
		waited += 0.1
	await settle(2.6)
	check(boss._shield_t <= 0.0, "her intro ends")
	shot("hollow_boss.png")
	var adds0 := get_tree().get_nodes_in_group("boss_adds").size()
	boss.hp = boss.max_hp * 0.55
	await settle(2.8)
	check(boss.brain.phase == 1 and get_tree().get_nodes_in_group("boss_adds").size() > adds0, "at 60% the brood answers")
	_kill(boss)
	await settle(0.8)
	check(Quests.current_step(ch2).key == "purge_ward", "she falls: the ward is next")
	await settle(0.4)
	var ward = null
	for qo in zone._quest_objects:
		if qo.id == "purge_ward":
			ward = qo.node
	check(ward != null and ward.visible, "the Purge Ward can be planted")
	ward.action.call()
	check(Quests.state(ch2) == Quests.READY and Quests.npc_marker("althea") == "?", "ready to hand in to Althea")
	var got := Quests.turn_in(ch2, player)
	check(Quests.state(ch2) == Quests.DONE and got.size() >= 4, "and the rewards are paid (%s)" % [got])
	zone.queue_free()
	await settle(0.4)

	# The Sunken Fen
	GameState.current_zone = "sunken_fen"
	GameState.zone_entry = "dune_wastes"
	zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.0)
	player = zone.player
	_tough(player)
	foreign = 0
	for e in _enemies(zone):
		if not e.is_boss and String(e.pack).begins_with("zpack_") and not (e.kind in ActDB.zone("sunken_fen").kinds):
			foreign += 1
	check(foreign == 0 and _enemies(zone, "fen_crawler").size() >= 6, "the Fen's own monsters, Fen Crawlers among them (%d)" % _enemies(zone, "fen_crawler").size())
	# Your speed in the mire
	player.can_fight = false
	var m2 := zone.maze as MazeMap
	var wet2 := Vector2i(-1, -1)
	for y in range(8, m2.rows - 4):
		for x in range(4, m2.cols - 6):
			if wet2.x < 0 and m2.is_mire(Vector2i(x, y)) and m2.is_mire(Vector2i(x + 1, y)) and m2.is_mire(Vector2i(x + 2, y)) and m2.is_mire(Vector2i(x + 3, y)):
				wet2 = Vector2i(x, y)
	check(wet2.x >= 0, "there is a stretch of mire to walk in")
	player.global_position = m2.cell_center(wet2) - Vector2(40, 0)
	var x0 := player.global_position.x
	for i in 20:
		player.joystick.output = Vector2(1, 0)  # walk right, with the player's own movement (which the mire slows)
		await get_tree().physics_frame
	player.joystick.output = Vector2.ZERO
	var in_mire := player.global_position.x - x0
	await settle(0.3)
	shot("fen_mire.png")  # standing in it
	var dry_at := Vector2.ZERO
	for y in range(8, m2.rows - 4):
		for x in range(8, m2.cols - 10):
			if dry_at == Vector2.ZERO and not m2.is_wall(Vector2i(x, y)) and not m2.is_mire(Vector2i(x, y)) and not m2.is_wall(Vector2i(x + 5, y)) and not m2.is_mire(Vector2i(x + 5, y)):
				dry_at = m2.cell_center(Vector2i(x, y))
	player.global_position = dry_at
	x0 = player.global_position.x
	for i in 20:
		player.joystick.output = Vector2(1, 0)  # walk right, with the player's own movement (which the mire slows)
		await get_tree().physics_frame
	player.joystick.output = Vector2.ZERO
	var on_dry := player.global_position.x - x0
	check(in_mire > 5.0 and in_mire < on_dry * 0.7, "the player is slower in the mire (%.0f px against %.0f)" % [in_mire, on_dry])

	# A Taste for Rot, and its choice
	var rot := "a1_taste_for_rot"
	check(Quests.npc_marker("voss") == "!", "Voss has a quest")
	Quests.start(rot)
	for i in 2:
		Quests.notify("kill", "fen_crawler")
	check(Quests.state(rot) == Quests.ACTIVE, "two glands are not enough")
	Quests.notify("kill", "ghoul")
	Quests.notify("kill", "fen_crawler")
	check(Quests.state(rot) == Quests.READY, "three Fen Crawlers: ready")
	var opts := Quests.npc_options("voss")
	check(opts.size() == 2 and opts.all(func(o): return o.action == "turn_in"), "Voss offers two things to choose from (%d)" % opts.size())
	check(Quests.turn_in(rot, player).is_empty() and Quests.state(rot) == Quests.READY, "handing in without choosing does nothing")
	var runes0 := 0
	for r in GameState.runes:
		runes0 += int(GameState.runes[r])
	var points0 := GameState.attr_points
	var level0 := GameState.level
	var paid := Quests.turn_in(rot, player, 1)
	var runes1 := 0
	for r in GameState.runes:
		runes1 += int(GameState.runes[r])
	check(Quests.state(rot) == Quests.DONE and runes1 == runes0 + 1 and GameState.attr_points == points0 + Attributes.POINTS_PER_LEVEL * (GameState.level - level0), "taking the rune gives a rune and not the points (%s)" % [paid])
	shot("fen_voss.png")
	zone.queue_free()
	await settle(0.3)

	# The old way back: the Wilds' exits
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "weeping_hollow"
	zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(0.8)
	var exit_to_hollow: Node2D = null
	for e in zone._exits:
		if e.target == "weeping_hollow":
			exit_to_hollow = e.node
	check(exit_to_hollow != null and zone.player.global_position.distance_to(exit_to_hollow.global_position) < 300.0, "coming back from the Hollow you stand at its cave mouth in the Wilds")
	print("hollow: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
