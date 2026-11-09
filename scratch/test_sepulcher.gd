extends Node2D
## Act I phase 5: the Sepulcher of Mourning (the great door from the Lower Ossuary, the flooded nave, the apse) and Chapter 5, Lord
## Malaphax the Flesh-Torn: iron first, and at half his life the Veil Realm (the dark, the shadows' ticking damage, the Rift
## Soul that ends it), then at a fifth two souls at once. Takes scratch/sep_t_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_sepulcher.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits, keeping the player alive (the boss is fighting them).
func soak(player: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		player.hp = player.stats.get_stat("max_life")
		await settle(0.1)
		t += 0.1


func shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name_))


func _kill(e: Enemy) -> void:
	e._shield_t = 0.0
	e.take_damage(e.max_hp * 100.0 * PartyScale.life())


func _object(zone: Node, id: String):
	for qo in zone._quest_objects:
		if qo.id == id:
			return qo.node
	return null


func _check_map(id: String) -> Dictionary:
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
		if o.type in ["start", "portal", "waypoint", "npc", "boss", "quest_object", "trigger", "pack", "trap", "vault"]:
			var c := Vector2i(int(float(o.x) / cell), int(float(o.y) / cell))
			check(seen.has(c), "%s: %s %s is on open ground you can reach (%s)" % [id, o.type, o.get("id", o.get("target", "")), c])
	return data


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {}
	GameState.waypoints = []
	GameState.opened_vaults = []

	# The maps and what they are made of
	var l2 := _check_map("grand_ossuary_2")
	var sep := _check_map("sepulcher_of_mourning")
	check(String(sep.theme) == "crypt" and sep.has("water"), "the Sepulcher is the crypt theme with a flooded floor")
	for f in ["veil_rift", "glass_1", "glass_2", "glass_3", "glass_shard_1", "river", "river_2"]:
		check(ResourceLoader.exists("res://assets/tiles/crypt/%s.png" % f), "crypt/%s exists" % f)
	var door := MapData.objects_of(l2, "portal").filter(func(o): return String(o.target) == "sepulcher_of_mourning")
	check(door.size() == 1 and String(door[0].get("requires", "")) == "a1_descent_into_madness", "the great door lets out only once the third anchor is broken")
	check(MapData.objects_of(sep, "portal").any(func(o): return String(o.target) == "grand_ossuary_2"), "and the Sepulcher leads back")
	check(ActDB.zone("sepulcher_of_mourning").map == "sepulcher_of_mourning" and ActDB.zone_name("sepulcher_of_mourning") == "Sepulcher of Mourning", "it is a zone")
	check(BossDB.has("lord_malaphax") and MonsterKinds.KINDS.has("rift_soul"), "Malaphax has a fight and the soul a kind")
	var d := BossDB.def("lord_malaphax")
	check(d.phases.size() == 3 and d.phases[1].has("veil") and d.phases[2].veil.souls == 2 and String(d.phases[1].skin) == "hell_knight", "two faces, and the Veil Realm in both of the later phases")
	var bosses := MapData.objects_of(sep, "boss")
	check(bosses.size() == 1 and bosses[0].id == "lord_malaphax", "he waits in the apse")

	# Chapter 5
	GameState.quests["a1_first_incursion"] = {"state": Quests.DONE, "step": 5, "count": 0}
	GameState.quests["a1_poisoning_the_well"] = {"state": Quests.DONE, "step": 4, "count": 0}
	GameState.quests["a1_breaking_the_seal"] = {"state": Quests.DONE, "step": 6, "count": 0}
	var ch5 := "a1_lord_malaphax"
	check(not Quests.available(ch5), "no Malaphax before the anchors are broken")
	GameState.quests["a1_descent_into_madness"] = {"state": Quests.DONE, "step": 8, "count": 0}
	check(Quests.available(ch5) and Quests.npc_marker("althea") == "!", "then Althea has the last chapter")
	Quests.start(ch5)
	check(Quests.current_step(ch5).key == "sepulcher_of_mourning", "it starts at the great door")

	GameState.current_zone = "sepulcher_of_mourning"
	GameState.zone_entry = "grand_ossuary_2"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.2)
	var player: Player = zone.player
	check(Quests.current_step(ch5).key == "lord_malaphax", "going through is the first step")
	check(zone._bosses.size() == 1, "one boss")
	var foreign := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and zone.is_ancestor_of(e) and not e.is_boss and String(e.pack).begins_with("zpack_") and not (e.kind in ActDB.zone("sepulcher_of_mourning").kinds):
			foreign += 1
	check(foreign == 0, "the Sepulcher's own monsters (%d foreign)" % foreign)
	var back: Node2D = null
	for e in zone._exits:
		if e.target == "grand_ossuary_2":
			back = e.node
	check(back != null and player.global_position.distance_to(back.global_position) < 300.0, "you arrive at the door")
	var m = MazeMap.current
	var wet := 0
	for y in 44:
		for x in 58:
			if m.is_mire(Vector2i(x, y)):
				wet += 1
	check(wet > 100, "the floor is flooded: mire cells (%d)" % wet)
	player.global_position = Vector2(23 * 128, 22 * 128)
	await settle(0.5)
	check(MazeMap.slow_at(player.global_position) < 1.0, "and it slows you")
	shot("sep_t_nave.png")

	# Lord Malaphax: iron
	var boss: Enemy = zone._bosses[0]
	player.global_position = boss.global_position + Vector2(-420, 30)
	var waited := 0.0
	while boss.brain.state == BossBrain.S.SLEEP and waited < 3.0:
		await settle(0.1)
		waited += 0.1
	await soak(player, 3.4)
	check(zone._boss == boss and boss._shield_t <= 0.0, "his fight begins, and the bar is his")
	check(boss.skin == "death_knight" and boss.brain.phase == 0 and not is_instance_valid(boss.brain._realm), "iron first: no Veil Realm yet")
	shot("sep_t_iron.png")
	await soak(player, 5.0)
	var used: Dictionary = boss.brain.moves_used
	check(used.has("cleave") or used.has("tear") or used.has("crush"), "he cleaves and tears the ground (%s)" % [used])
	check(not used.has("scythes") and not used.has("dash"), "and has no scythes yet")

	# Phase 2: the rift flesh and the Veil Realm
	boss.hp = boss.max_hp * 0.45
	var t := 0.0
	while t < 9.0 and not (boss.brain.phase == 1 and is_instance_valid(boss.brain._realm)):
		await soak(player, 0.2)
		t += 0.2
	check(boss.brain.phase == 1 and boss.skin == "hell_knight", "at half his life he tears off the iron")
	var realm: VeilRealm = boss.brain._realm
	check(is_instance_valid(realm), "the Veil Realm opens")
	if is_instance_valid(realm):
		check(realm.alive_souls().size() == 1 and realm.alive_souls()[0].kind == "rift_soul", "one Rift Soul drifts in the arena")
		await soak(player, 1.2)
		shot("sep_t_veil.png")
		player.hp = player.stats.get_stat("max_life")
		var hp0 := player.hp
		realm._tick_t = 0.0
		realm._process(0.0)
		check(player.hp < hp0, "the shadows tear at you (%.1f)" % (hp0 - player.hp))
		var soul: Enemy = realm.alive_souls()[0]
		_kill(soul)
		await soak(player, 1.2)
		check(not is_instance_valid(boss.brain._realm), "destroy the soul and the dark lifts")
		boss.brain._veil_t = 0.4
		await soak(player, 1.6)
		check(is_instance_valid(boss.brain._realm), "and it comes again")
		for s in boss.brain._realm.alive_souls():
			_kill(s)
		await soak(player, 1.2)
	used = boss.brain.moves_used
	check(used.has("scythes") or used.has("dash") or used.has("drop") or used.has("hop"), "he fights with scythes, dashes and drops now (%s)" % [used])

	# Phase 3: two souls
	boss.hp = boss.max_hp * 0.15
	t = 0.0
	while t < 9.0 and not (boss.brain.phase == 2 and is_instance_valid(boss.brain._realm)):
		await soak(player, 0.2)
		t += 0.2
	check(boss.brain.phase == 2, "at a fifth, the last of him")
	realm = boss.brain._realm
	check(is_instance_valid(realm) and realm.alive_souls().size() == 2, "two souls this time")
	if is_instance_valid(realm):
		_kill(realm.alive_souls()[0])
		await soak(player, 0.4)
		check(is_instance_valid(boss.brain._realm) and not boss.brain._realm._over, "one is not enough")
		for s in boss.brain._realm.alive_souls():
			_kill(s)
		await soak(player, 1.2)

	# He falls
	check(not is_instance_valid(_object(zone, "rift_scar")) or not _object(zone, "rift_scar").visible, "the rift is only a rift before he falls")
	_kill(boss)
	await soak(player, 0.8)
	check(Quests.current_step(ch5).key == "rift_scar", "he falls: the torn rift")
	await soak(player, 0.4)
	var scar = _object(zone, "rift_scar")
	check(scar != null and scar.visible, "it can be looked into")
	scar.action.call()
	check(Quests.state(ch5) == Quests.READY and Quests.npc_marker("althea") == "?", "ready to hand in to Althea")
	var got := Quests.turn_in(ch5, player)
	check(Quests.state(ch5) == Quests.DONE and got.size() >= 6 and got.any(func(l): return String(l).contains("Act I is complete")), "the rewards are paid, and Act I is complete (%s)" % [got])
	check(Quests.boss_alive("lord_malaphax"), "Malaphax can be fought again")
	print("sepulcher: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
