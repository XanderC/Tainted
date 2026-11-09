extends Node2D
## Act I phase 4: the Grand Ossuary (the crypt theme, two levels, the gate from the Verge that opens with the seal), Chapter 4
## (Descent into Madness: three heralds and three Veil Anchors, an elite ambush at each), Restless Ancestors (four urns, the
## pedestal, a lasting resistance), the armory vault behind its cracked wall (the key from The Last Watch) and the spike traps.
##   godot --path . --resolution 1600x720 res://scratch/test_ossuary.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func _enemies(zone: Node, kind := "") -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return is_instance_valid(e) and zone.is_ancestor_of(e) and not e._dead and (kind == "" or e.kind == kind))


func _kill(e: Enemy) -> void:
	e._shield_t = 0.0
	e.take_damage(e.max_hp * 100.0 * PartyScale.life())


func _object(zone: Node, id: String):
	for qo in zone._quest_objects:
		if qo.id == id:
			return qo.node
	return null


func _objects(zone: Node, key: String) -> Array:
	return zone._quest_objects.filter(func(q): return q.id == key).map(func(q): return q.node)


func _boss(zone: Node, id: String) -> Enemy:
	for b in zone._bosses:
		if String(b.get_meta("boss_id")) == id:
			return b
	return null


func _wake(zone: Node, boss: Enemy) -> void:
	zone.player.global_position = boss.global_position + Vector2(-380, 40)
	var waited := 0.0
	while boss.brain.state == BossBrain.S.SLEEP and waited < 3.0:
		await settle(0.1)
		waited += 0.1
	await settle(2.0)


func _load_zone(id: String, entry: String):
	GameState.current_zone = id
	GameState.zone_entry = entry
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.2)
	return zone


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


func _targets(data: Dictionary) -> Array:
	return MapData.objects_of(data, "portal").map(func(o): return String(o.target))


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {}
	GameState.waypoints = []
	GameState.opened_vaults = []

	# The maps and what they are made of
	var verge := _check_map("ashen_verge")
	var l1 := _check_map("grand_ossuary_1")
	var l2 := _check_map("grand_ossuary_2")
	check(String(l1.theme) == "crypt" and String(l2.theme) == "crypt", "both levels are the crypt theme")
	for f in ["bg", "walls/middle", "walls/top", "torch_1", "lantern_1", "rift_2", "blood_1", "decor_4", "decor_22", "decor_31", "decor_33"]:
		check(ResourceLoader.exists("res://assets/tiles/crypt/%s.png" % f), "crypt/%s exists" % f)
	check("grand_ossuary_1" in _targets(verge) and "ashen_verge" in _targets(l1), "the Verge leads down to the Ossuary and back")
	check("grand_ossuary_2" in _targets(l1) and "grand_ossuary_1" in _targets(l2), "the stair joins the two levels")
	check(ActDB.zone("grand_ossuary_1").map == "grand_ossuary_1" and ActDB.zone_name("grand_ossuary_2") == "Lower Ossuary", "both are zones")
	for kind in ["skeleton_vanguard", "veil_cultist"]:
		check(MonsterKinds.KINDS.has(kind), "monster kind " + kind)
	for b in ["herald_oren", "herald_sable", "herald_morrow"]:
		check(BossDB.has(b), "boss fight " + b)
	check(MapData.objects_of(l1, "trap").size() >= 8 and MapData.objects_of(l2, "trap").size() >= 8, "spike traps in the hallways")
	check(MapData.objects_of(l1, "vault").size() == 1 and MapData.objects_of(l1, "quest_object").size() == 7, "the vault, four urns, the pedestal and two anchors on level 1")
	var gate := MapData.objects_of(verge, "portal").filter(func(o): return String(o.target) == "grand_ossuary_1")
	check(gate.size() == 1 and String(gate[0].get("requires", "")) == "a1_breaking_the_seal", "the Verge's gate to the Ossuary opens with the seal")

	# The gate opens with the seal
	GameState.quests["a1_first_incursion"] = {"state": Quests.DONE, "step": 5, "count": 0}
	GameState.quests["a1_poisoning_the_well"] = {"state": Quests.DONE, "step": 4, "count": 0}
	var zone = await _load_zone("ashen_verge", "weeping_hollow")
	var ossuary_gate = null
	for e in zone._exits:
		if e.target == "grand_ossuary_1":
			ossuary_gate = e
	check(ossuary_gate != null and not ossuary_gate.node.visible and not zone._exit_open(ossuary_gate), "shut before the seal is broken")
	GameState.quests["a1_breaking_the_seal"] = {"state": Quests.READY, "step": 6, "count": 0}
	await settle(0.3)
	check(zone._exit_open(ossuary_gate) and ossuary_gate.node.visible, "open once it is")
	GameState.quests["a1_breaking_the_seal"] = {"state": Quests.DONE, "step": 6, "count": 0}
	zone.queue_free()
	await settle(0.4)

	# Chapter 4
	var ch4 := "a1_descent_into_madness"
	var spirit_q := "a1_restless_ancestors"
	check(Quests.available(ch4) and Quests.npc_marker("althea") == "!", "Althea has the next chapter")
	Quests.start(ch4)
	check(Quests.current_step(ch4).key == "grand_ossuary_1", "Chapter 4 starts at the gates")
	zone = await _load_zone("grand_ossuary_1", "ashen_verge")
	var player: Player = zone.player
	check(Quests.current_step(ch4).key == "herald_oren", "going in is the first step")
	check(zone._bosses.size() == 2 and _boss(zone, "herald_oren") != null and _boss(zone, "herald_sable") != null, "two heralds wait on this level")
	check(_enemies(zone).size() > 40, "the Ossuary's monsters (%d)" % _enemies(zone).size())
	var foreign := 0
	for e in _enemies(zone):
		if not e.is_boss and String(e.pack).begins_with("zpack_") and not (e.kind in ActDB.zone("grand_ossuary_1").kinds):
			foreign += 1
	check(foreign == 0, "all of them its own kinds (%d foreign)" % foreign)
	check(zone._exits.size() == 2 and zone._exit_open(zone._exits[0]) and zone._exit_open(zone._exits[1]), "the ways out are open")
	var arrival_exit: Node2D = null
	for e in zone._exits:
		if e.target == "ashen_verge":
			arrival_exit = e.node
	check(arrival_exit != null and player.global_position.distance_to(arrival_exit.global_position) < 300.0, "you arrive at the gate from the Verge")

	# The spike traps hurt once per rising
	var traps: Array = zone.get_children().filter(func(c): return c is SpikeTrap)
	check(traps.size() >= 8, "traps in the hallways (%d)" % traps.size())
	var trap: SpikeTrap = traps[0]
	player.global_position = trap.global_position
	var hp0: float = player.hp
	var waited := 0.0
	while trap.rise() < 1.0 and waited < 5.0:
		await settle(0.05)
		waited += 0.05
	await settle(0.15)
	var hit: float = hp0 - player.hp
	check(hit > 0.0 and hit < player.stats.get_stat("max_life") * 0.2, "standing on risen spikes costs Life (%.1f of %.1f)" % [hit, player.stats.get_stat("max_life")])
	var hp1: float = player.hp
	await settle(0.3)
	check(player.hp >= hp1 - 0.01, "but only once per rising")
	player.hp = player.stats.get_stat("max_life")
	player.global_position = arrival_exit.global_position + Vector2(300, 0)

	# The first herald and anchor
	var oren := _boss(zone, "herald_oren")
	await _wake(zone, oren)
	check(zone._boss == oren and oren._shield_t <= 0.0, "Oren's fight begins, and the bar is his")
	var adds0 := get_tree().get_nodes_in_group("boss_adds").size()
	oren.hp = oren.max_hp * 0.5
	await settle(2.8)
	check(oren.brain.phase == 1 and get_tree().get_nodes_in_group("boss_adds").size() > adds0, "at half his life the vanguard rises")
	check(_object(zone, "anchor_1") != null and not _object(zone, "anchor_1").visible, "the anchor is no use before he falls")
	_kill(oren)
	await settle(0.8)
	check(Quests.current_step(ch4).key == "anchor_1", "he falls: the first anchor")
	await settle(0.4)
	var a1 = _object(zone, "anchor_1")
	check(a1 != null and a1.visible and not _object(zone, "anchor_2").visible, "the first anchor can be shattered, the second not yet")
	for n in get_tree().get_nodes_in_group("boss_adds"):
		n.queue_free()
	var before := _enemies(zone).size()
	a1.action.call()
	await settle(0.2)
	var ambush := _enemies(zone).filter(func(e): return String(e.pack).begins_with("ambush_"))
	check(ambush.size() == 5 and ambush.any(func(e): return e.tier == MonsterAffix.Tier.ELITE), "shattering it brings an elite ambush (%d)" % ambush.size())
	check(Quests.current_step(ch4).key == "herald_sable", "on to the second herald")
	for e in ambush:
		e.queue_free()

	# The second
	var sable := _boss(zone, "herald_sable")
	await _wake(zone, sable)
	check(zone._boss == sable, "the bar follows Sable now")
	_kill(sable)
	await settle(0.8)
	check(Quests.current_step(ch4).key == "anchor_2", "the second anchor")
	await settle(0.4)
	for n in get_tree().get_nodes_in_group("boss_adds"):
		n.queue_free()
	_object(zone, "anchor_2").action.call()
	await settle(0.2)
	check(Quests.current_step(ch4).key == "grand_ossuary_2", "then the stair down")
	check(_enemies(zone).filter(func(e): return String(e.pack).begins_with("ambush_") and e.kind == "veil_cultist").size() == 5, "the second ambush is the cult")

	# Restless Ancestors, on level 1
	var spirit_pos := Vector2.ZERO
	for o in MapData.objects_of(l1, "npc"):
		if o.id == "ancestor_spirit":
			spirit_pos = Vector2(float(o.x), float(o.y))
	check(spirit_pos != Vector2.ZERO, "the Weeping Spirit is in the guardroom")
	var offer := Quests.npc_options("ancestor_spirit")
	check(offer.size() == 1 and offer[0].action == "offer" and offer[0].quest == spirit_q, "she asks for her urns")
	Quests.start(spirit_q)
	await settle(0.3)
	var urns := _objects(zone, "urn")
	check(urns.size() == 4 and urns.all(func(n): return n.visible), "four urns lie in the sarcophagi")
	check(not _object(zone, "urn_pedestal").visible, "the pedestal waits for them")
	var tracker := Quests.tracker_lines().filter(func(l): return l.quest == spirit_q)
	check(tracker.size() == 1 and String(tracker[0].text).contains("0 / 4"), "the log counts the urns (%s)" % [tracker])
	for i in 3:
		urns[i].action.call()
	check(Quests.step_index(spirit_q) == 0 and Quests.state(spirit_q) == Quests.ACTIVE, "three are not enough")
	urns[3].action.call()
	check(Quests.current_step(spirit_q).key == "urn_pedestal", "four: the pedestal")
	await settle(0.3)
	check(_object(zone, "urn_pedestal").visible, "the pedestal shows")
	_object(zone, "urn_pedestal").action.call()
	check(Quests.state(spirit_q) == Quests.READY and Quests.npc_marker("ancestor_spirit") == "?", "ready to hand in")
	var res0 := player.resistance(RuneDef.DamageType.FIRE)
	var got := Quests.turn_in(spirit_q, player)
	var res1 := player.resistance(RuneDef.DamageType.FIRE)
	check(Quests.state(spirit_q) == Quests.DONE and got.any(func(l): return String(l).contains("5% to all Resistances")), "the spirit pays (%s)" % [got])
	check(absf(res1 - res0 - 0.05) < 0.001 and absf(Quests.bonus("res_all") - 0.05) < 0.001, "and every resistance is 5%% higher for good (%.3f -> %.3f)" % [res0, res1])
	check(res1 > 0.0 and player.resistance(RuneDef.DamageType.CHAOS) >= 0.05, "poison too")

	# The armory vault
	var wall = null
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.prompt == "Press the cracked wall":
			wall = i
	check(wall != null, "the cracked wall is in the guardroom")
	player.global_position = wall.global_position + Vector2(0, 100)
	var drops0: int = zone.get_children().filter(func(c): return c is LootPickup).size()
	wall.action.call()
	await settle(0.2)
	check(zone.get_children().filter(func(c): return c is LootPickup).size() == drops0 and GameState.opened_vaults.is_empty(), "without the key it will not give")
	GameState.quests["a1_the_last_watch"] = {"state": Quests.DONE, "step": 2, "count": 0}
	wall.action.call()
	await settle(0.4)
	var drops1: int = zone.get_children().filter(func(c): return c is LootPickup).size()
	check(drops1 - drops0 >= 3 and "vault:armory" in GameState.opened_vaults, "with the key it gives way and spills its loot (%d)" % (drops1 - drops0))
	check(not wall.is_in_group("interactables"), "and is not a thing to use again")

	# Level 2
	zone.queue_free()
	await settle(0.4)
	zone = await _load_zone("grand_ossuary_2", "grand_ossuary_1")
	player = zone.player
	check(Quests.current_step(ch4).key == "herald_morrow", "the stair down is the step")
	check(zone._bosses.size() == 1 and _boss(zone, "herald_morrow") != null, "Herald Morrow waits in the choir")
	check(_enemies(zone).size() > 40, "the Lower Ossuary's monsters (%d)" % _enemies(zone).size())
	var back: Node2D = null
	for e in zone._exits:
		if e.target == "grand_ossuary_1":
			back = e.node
	check(back != null and player.global_position.distance_to(back.global_position) < 300.0, "you arrive at the stair")
	var morrow := _boss(zone, "herald_morrow")
	await _wake(zone, morrow)
	adds0 = get_tree().get_nodes_in_group("boss_adds").size()
	morrow.hp = morrow.max_hp * 0.6
	await settle(2.8)
	check(morrow.brain.phase >= 1 and get_tree().get_nodes_in_group("boss_adds").size() > adds0, "Morrow calls the vanguard")
	_kill(morrow)
	await settle(0.8)
	check(Quests.current_step(ch4).key == "anchor_3", "he falls: the last anchor")
	await settle(0.4)
	for n in get_tree().get_nodes_in_group("boss_adds"):
		n.queue_free()
	var a3 = _object(zone, "anchor_3")
	check(a3 != null and a3.visible, "the last anchor can be shattered")
	a3.action.call()
	await settle(0.2)
	check(Quests.state(ch4) == Quests.READY and Quests.npc_marker("althea") == "?", "ready to hand in to Althea")
	check(_enemies(zone).filter(func(e): return String(e.pack).begins_with("ambush_")).size() == 6, "with a last ambush")
	var paid := Quests.turn_in(ch4, player)
	check(Quests.state(ch4) == Quests.DONE and paid.size() >= 4, "the rewards are paid (%s)" % [paid])
	check(Quests.boss_alive("herald_oren") and Quests.boss_alive("herald_morrow"), "the heralds are there to farm again")

	# A vault opened stays open on the next visit
	zone.queue_free()
	await settle(0.4)
	zone = await _load_zone("grand_ossuary_1", "ashen_verge")
	var shut := 0
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.prompt == "Press the cracked wall":
			shut += 1
	check(shut == 0, "the opened vault is open on the next visit")
	print("ossuary: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
