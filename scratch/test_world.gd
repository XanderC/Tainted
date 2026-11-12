extends Node2D
## Act I phase 6: the four dynamic world encounters (ZoneEncounters: a cursed shrine, tears in reality, the dying pilgrim, the pyre of the
## dead) and the four spawning mini-dungeons (MiniDungeons, MiniDungeon: the Rot-Damp Cellar, the Forgotten Bone Pit, the Hermit's Sanctum
## with its free bench, the Weeping Fissure). Run:
##   godot --path . --resolution 1600x720 res://scratch/test_world.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func soak(player: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		player.hp = player.stats.get_stat("max_life")
		await settle(0.1)
		t += 0.1


func _kill(e) -> void:
	if is_instance_valid(e):
		e._shield_t = 0.0
		e.take_damage(1.0e12)


func _kill_all(list: Array) -> void:
	for e in list.duplicate():
		_kill(e)


func _loot(zone: Zone) -> int:
	return zone.get_children().filter(func(n): return n is LootPickup or n is CurrencyPickup).size()


func _enemies(zone: Zone) -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return is_instance_valid(e) and zone.is_ancestor_of(e) and not e._dead)


func _zone(id: String, origin := "") -> Zone:
	GameState.current_zone = id
	GameState.zone_entry = "start"
	GameState.mini_origin = origin
	var z: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(z)
	return z


func _clear_random(zone: Zone) -> void:
	for e in zone.get_children().filter(func(n): return n is ZoneEncounters):
		e.queue_free()
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.has_meta("dungeon"):
			i.queue_free()
	for e in _enemies(zone):  # a clean field
		e.queue_free()
	await settle(0.3)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {}
	GameState.waypoints = []
	var zone := _zone("dune_wastes")
	await settle(1.2)
	var player: Player = zone.player
	await _clear_random(zone)
	check("shrine" in ZoneEncounters.KINDS and "rift" in ZoneEncounters.KINDS and "pilgrim" in ZoneEncounters.KINDS and "pyre" in ZoneEncounters.KINDS, "all four events are kinds")

	# ---- The cursed shrine ----
	var sh := ZoneEncounters.roll(zone, "shrine")
	check(sh != null and sh.state == "idle" and sh._it != null and sh._it.is_in_group("interactables"), "a cursed shrine, to be used")
	player.global_position = sh.pos + Vector2(0, 260)
	await settle(0.3)
	check(sh.foes.is_empty(), "quiet until it is used")
	var loot0 := _loot(zone)
	sh._it.action.call()
	await settle(0.4)
	check(sh.state == "waves" and sh.wave == 1 and sh.foes.size() >= 5, "using it sends the first wave (%d)" % sh.foes.size())
	check(not sh._it.is_in_group("interactables"), "and it cannot be used twice")
	var elite := false
	for round_ in 6:
		await soak(player, 0.3)
		if sh.state == "done":
			break
		elite = elite or sh.foes.any(func(e): return is_instance_valid(e) and e.tier == MonsterAffix.Tier.ELITE)
		_kill_all(sh.foes)
		await soak(player, 0.5)
	check(sh.wave == ZoneEncounters.SHRINE_WAVES, "three waves came (%d)" % sh.wave)
	check(elite, "the last led by an elite")
	await soak(player, 0.5)
	check(sh.state == "done", "cleansed: done (%s)" % sh.state)
	check(_loot(zone) - loot0 >= 5, "a cluster of loot (%d)" % (_loot(zone) - loot0))
	check(player.blessing_t > 100.0, "and a two-minute blessing (%.0f s)" % player.blessing_t)
	check(absf(player.stats.get_stat("res_all") - 0.1) < 0.001 or player.stats.get_stat("res_all") >= 0.1, "that raises every resistance")
	player.blessing_t = 0.05
	await settle(0.3)
	check(player.blessing_t <= 0.0 and player.stats.get_stat("res_all") < 0.1, "until it ends")
	sh.queue_free()
	sh._it.queue_free()

	# ---- Tears in reality ----
	var ri := ZoneEncounters.roll(zone, "rift")
	check(ri != null and ri.state == "waiting", "a rift, closed")
	player.global_position = ri.pos + Vector2(0, 1500)
	await settle(0.3)
	check(ri.state == "waiting", "far away it is quiet")
	player.global_position = ri.pos + Vector2(0, 800)
	await soak(player, 0.4)
	check(ri.state == "open" and ri.spires.size() == 3 and ri.time_left > 70.0, "close: it opens with three spires")
	var spire: Enemy = ri.spires[0]
	var spire_at := spire.global_position
	check(spire.kind == "rift_spire" and spire.display_name == "Rift Spire", "the spires are enemies you can destroy")
	await soak(player, 0.8)
	check(spire.global_position.distance_to(spire_at) < 5.0, "and stand still")
	player.global_position = ri.pos + Vector2(0, 340)
	var d0 := player.global_position.distance_to(ri.pos)
	await soak(player, 1.0)
	check(player.global_position.distance_to(ri.pos) < d0 - 20.0, "it pulls you in (%.0f -> %.0f)" % [d0, player.global_position.distance_to(ri.pos)])
	await soak(player, 3.0)
	check(ri.foes.size() >= 3 and ri.foes.any(func(e): return is_instance_valid(e) and e.tier == MonsterAffix.Tier.ELITE), "it vomits out elite monsters (%d)" % ri.foes.size())
	var loot1 := _loot(zone)
	for sp in ri.spires.duplicate():
		_kill(sp)
	await soak(player, 0.5)
	check(ri.state == "done" and _loot(zone) > loot1, "all three spires down: the rift seals and pays out")
	_kill_all(ri.foes)
	ri.queue_free()
	await settle(0.3)
	var ri2 := ZoneEncounters.roll(zone, "rift")
	player.global_position = ri2.pos + Vector2(0, 800)
	await soak(player, 0.4)
	ri2.time_left = 0.05
	await soak(player, 0.6)
	check(ri2.state == "burst" and is_instance_valid(zone._boss) and zone._boss.display_name == "Rift Horror", "left too long: a Rift Horror tears through")
	_kill(zone._boss)
	_kill_all(ri2.foes)
	for sp in ri2.spires.duplicate():
		_kill(sp)
	await soak(player, 0.6)
	ri2.queue_free()
	await _clear_random(zone)

	# ---- The dying pilgrim ----
	var pi := ZoneEncounters.roll(zone, "pilgrim")
	check(pi != null and pi.state == "waiting", "a pilgrim, waiting")
	player.global_position = pi.pos + Vector2(0, 450)
	await soak(player, 0.5)
	check(pi.state == "defend" and pi.wave >= 1 and pi.foes.size() >= 4, "close: the first wave comes (%d)" % pi.foes.size())
	check(pi.life > 99.0, "his life is full")
	var fiend: Enemy = pi.foes[0]
	fiend.global_position = pi.pos + Vector2(40, 20)
	fiend._shield_t = 5.0  # (it lives while it tears at him)
	await soak(player, 1.2)
	check(pi.life < 95.0, "a fiend at him tears at his life (%.1f)" % pi.life)
	_kill(fiend)
	for round_ in 8:
		await soak(player, 0.4)
		if pi.state == "done":
			break
		_kill_all(pi.foes)
	check(pi.wave == ZoneEncounters.PILGRIM_WAVES and pi.state == "done", "four waves, and he lived (%d, %s)" % [pi.wave, pi.state])
	check(pi.life > 50.0 and pi._it != null and pi._it.is_in_group("interactables"), "above half his life: the reliquary opens")
	var loot2 := _loot(zone)
	pi._it.action.call()
	await settle(0.3)
	check(_loot(zone) - loot2 >= 3, "and pays out (%d)" % (_loot(zone) - loot2))
	pi.queue_free()
	var pi2 := ZoneEncounters.roll(zone, "pilgrim")
	player.global_position = pi2.pos + Vector2(0, 450)
	await soak(player, 0.5)
	pi2.life = 2.0
	var f2: Enemy = pi2.foes[0]
	f2.global_position = pi2.pos + Vector2(30, 10)
	f2._shield_t = 5.0
	await soak(player, 1.0)
	check(pi2.state == "failed", "if he dies the rite fails (%s)" % pi2.state)
	_kill(f2)
	_kill_all(pi2.foes)
	pi2.queue_free()
	await _clear_random(zone)

	# ---- The pyre of the dead ----
	var py := ZoneEncounters.roll(zone, "pyre")
	check(py != null and py.state == "waiting" and py._it != null, "a pile of the dead")
	player.global_position = py.pos + Vector2(0, 1600)
	await settle(0.3)
	check(py.state == "waiting", "far away they are still")
	player.global_position = py.pos + Vector2(0, 900)
	await soak(player, 0.4)
	check(py.state == "stirring" and py.time_left > 30.0, "close: they begin to stir")
	player.global_position = py.pos + Vector2(0, 160)
	var loot3 := _loot(zone)
	py._it.action.call()
	await soak(player, 0.5)
	check(py.state == "burning" and py.foes.size() >= 12 and is_instance_valid(py._ring), "lit: the swarm enrages, and a ring of fire shuts you in (%d)" % py.foes.size())
	check(py.foes.any(func(e): return is_instance_valid(e) and e.tier == MonsterAffix.Tier.ELITE), "with elites in it")
	_kill_all(py.foes)
	await soak(player, 0.8)
	check(py.state == "done" and _loot(zone) - loot3 >= 4, "the brawl won: the ring drops and it pays out (%d)" % (_loot(zone) - loot3))
	await settle(0.3)
	check(not is_instance_valid(py._ring) or py._ring.is_queued_for_deletion(), "the ring is gone")
	py.queue_free()
	var py2 := ZoneEncounters.roll(zone, "pyre")
	player.global_position = py2.pos + Vector2(0, 900)
	await soak(player, 0.4)
	py2.time_left = 0.05
	await soak(player, 0.6)
	check(py2.state == "risen" and py2.foes.size() >= 12 and py2._ring == null, "too slow: they rise, with no ring")
	_kill_all(py2.foes)
	await soak(player, 0.6)
	check(py2.state == "done", "and are put down again")
	py2.queue_free()
	await _clear_random(zone)

	# ---- The entrance ----
	check(MiniDungeons.roll(zone, Vector2(INF, INF), "mini_cellar") != null, "an entrance can be placed in an open zone")
	var entrance: Interactable = null
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.has_meta("dungeon"):
			entrance = i
	check(entrance != null and entrance.get_meta("dungeon") == "mini_cellar" and entrance.prompt.contains("Rot-Damp Cellar"), "it leads to the cellar")
	check(entrance.global_position.distance_to(zone.maze.start_pos) >= 900.0, "away from where you arrive")
	check(MiniDungeons.roll(_zone_dummy(), Vector2(INF, INF), "mini_cellar") == null, "none where there can be none")
	zone._mini_exit = entrance.global_position + Vector2(0, 110)
	GameState.zone_entry = "mini_cellar"
	check(zone._arrival().distance_to(zone._mini_exit) < 1.0, "coming back up puts you at the entrance")
	zone.queue_free()
	await settle(0.4)

	# ---- The Rot-Damp Cellar ----
	zone = _zone("mini_cellar", "dune_wastes")
	await settle(1.2)
	player = zone.player
	check(zone.area_level == ActDB.zone("dune_wastes").area_level + 1, "as hard as the zone above, and a little more (%d)" % zone.area_level)
	check(zone._exits.size() == 1 and zone._exits[0].target == "dune_wastes", "its way up leads back to where you came from")
	var maggots := _enemies(zone).filter(func(e): return e.kind == "blood_maggot")
	check(maggots.size() >= 15, "swarming with blood maggots (%d)" % maggots.size())
	var chest: Interactable = null
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.prompt == "Open the chest":
			chest = i
	check(chest != null, "a chest on a hoard")
	player.global_position = chest.global_position + Vector2(0, 150)
	chest.action.call()
	await settle(0.4)
	var mimic := _enemies(zone).filter(func(e): return e.kind == "mimic")
	check(mimic.size() == 1 and mimic[0].tier == MonsterAffix.Tier.ELITE, "it is a mimic")
	var loot4 := _loot(zone)
	_kill_all(mimic)
	await settle(0.5)
	check(_loot(zone) - loot4 >= 5, "its hoard spills out (%d)" % (_loot(zone) - loot4))
	zone.queue_free()
	await settle(0.4)

	# ---- The Forgotten Bone Pit ----
	zone = _zone("mini_bonepit", "weeping_hollow")
	await settle(1.2)
	player = zone.player
	var md: MiniDungeon = zone.get_node("MiniDungeon")
	check(md != null and not md.sprung, "a bone pit, quiet")
	check(_enemies(zone).size() > 5 and _enemies(zone).all(func(e): return e.kind in ActDB.zone("mini_bonepit").kinds), "skeletons about the rooms (%d)" % _enemies(zone).size())
	var pit: Vector2 = zone.maze.markers["pit"][0]
	player.global_position = pit + Vector2(-600, 0)
	await settle(0.3)
	check(not md.sprung, "outside the pit nothing happens")
	player.global_position = pit
	await soak(player, 0.4)
	check(md.sprung and md._gates.size() == 2, "step in: portcullises slam over both ways (%d)" % md._gates.size())
	var champs := _enemies(zone).filter(func(e): return e.kind == "skeleton_champion")
	check(champs.size() == 1 and champs[0].tier == MonsterAffix.Tier.LEGENDARY, "with an elite champion")
	var loot5 := _loot(zone)
	_kill_all(champs)
	await soak(player, 0.6)
	check(md._gates.is_empty() and _loot(zone) - loot5 >= 3, "dead: the gates rise and it pays out")
	zone.queue_free()
	await settle(0.4)

	# ---- The Hermit's Sanctum ----
	zone = _zone("mini_sanctum", "ashen_verge")
	await settle(1.2)
	player = zone.player
	md = zone.get_node("MiniDungeon")
	check(_enemies(zone).is_empty(), "a quiet cave: nothing in it")
	var bench: Interactable = null
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.prompt == "Use the abandoned crafting bench":
			bench = i
	check(bench != null, "an abandoned crafting bench")
	var rare := LootGenerator.roll_item(6, ItemInstance.Rarity.RARE)
	player.add_to_bag(rare)
	var before := rare.to_dict()
	var orbs0 := GameState.orb_count("chaos")
	var said := {"msg": ""}
	var panel := HermitBench.open(zone, player, func(m: String): said.msg = m)
	await settle(0.3)
	check(get_tree().paused and panel.gear().has(rare), "it lists your gear, with the game paused")
	panel._select(rare)
	check(not panel._mods.disabled and not panel._socks.disabled, "a Rare item can be rerolled both ways")
	check(HermitBench.mod_orb(rare) == "chaos" and HermitBench.mod_orb(LootGenerator.roll_item(6, ItemInstance.Rarity.MAGIC)) == "regal", "Chaos for a Rare, Regal for a Magic")
	panel._use(false)
	await settle(0.3)
	check(said.msg != "" and not get_tree().paused, "used: a message, and the game goes on (%s)" % said.msg)
	check(rare.to_dict() != before, "its modifiers are rerolled")
	check(GameState.orb_count("chaos") == orbs0, "and no orb was spent")
	md.used = true
	bench.action.call()
	check(md.used, "the bench is spent after one use")
	zone.queue_free()
	await settle(0.4)

	# ---- The Weeping Fissure ----
	zone = _zone("mini_fissure", "sunken_fen")
	await settle(1.2)
	player = zone.player
	md = zone.get_node("MiniDungeon")
	check(md._dark != null and md._dark_mat != null, "the dark: a shader over the screen")
	check(md.guardians.size() == 3 and md.guardians.all(func(e): return e.tier == MonsterAffix.Tier.ELITE), "three elite guardians")
	check(_enemies(zone).size() > 25, "high enemy density (%d)" % _enemies(zone).size())
	var tainted: Interactable = null
	for i in get_tree().get_nodes_in_group("interactables"):
		if zone.is_ancestor_of(i) and i.prompt == "Open the Tainted Chest":
			tainted = i
	var loot6 := _loot(zone)
	tainted.action.call()
	await settle(0.3)
	check(not md.chest_open and _loot(zone) == loot6, "the chest is bound while the guardians live")
	_kill_all(md.guardians)
	await settle(0.4)
	check(md.guardians.is_empty(), "guardians dead")
	tainted.action.call()
	await settle(0.4)
	check(md.chest_open and _loot(zone) - loot6 >= 6, "the tethers snap: the Tainted Chest pays out (%d)" % (_loot(zone) - loot6))
	print("world: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## A zone that can have no entrance (the Ossuary).
func _zone_dummy() -> Zone:
	var z := Zone.new()
	z.zone_id = "grand_ossuary_1"
	return z
