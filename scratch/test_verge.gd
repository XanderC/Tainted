extends Node2D
## Act I phase 3: the Ashen Verge (the ashen theme, both ways in, two bosses in one zone), Chapter 3 (Breaking the Seal:
## the Maddened Grave Warden, the Rift Golem, the two keystone halves, the sealed mausoleum) and the side quest The Last
## Watch (two mutated scouts, the survivor Mara, Dennis). Takes scratch/verge_t_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_verge.tscn

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


func _object(zone: Node, id: String):
	for qo in zone._quest_objects:
		if qo.id == id:
			return qo.node
	return null


## Walk the player to a boss's door and wait until it has woken.
func _wake(zone: Node, boss: Enemy, home: Vector2) -> void:
	zone.player.global_position = home + Vector2(-380, 40)
	var waited := 0.0
	while boss.brain.state == BossBrain.S.SLEEP and waited < 3.0:
		await settle(0.1)
		waited += 0.1
	await settle(2.4)


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
		if o.type in ["start", "portal", "waypoint", "npc", "boss", "quest_object", "trigger", "pack"]:
			var c := Vector2i(int(float(o.x) / cell), int(float(o.y) / cell))
			check(seen.has(c), "%s: %s %s is on open ground you can reach" % [id, o.type, o.get("id", o.get("target", ""))])
	return data


func _targets(data: Dictionary) -> Array:
	var out := []
	for o in data.objects:
		if o.type == "portal":
			out.append(String(o.target))
	return out

## The bosses hit as hard as they do for a character of the level the story has brought you to (BossDB "power"): this one has the life for it.
func _tough(p: Player) -> void:
	p.stats.add_mod("max_life", StatBlock.ModType.FLAT, 20000.0, "test")
	p.hp = p.stats.get_stat("max_life")


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {}
	GameState.waypoints = []

	# The map, and the ways in
	var verge := check_map("ashen_verge")
	check_map("weeping_hollow")
	check_map("sunken_fen")
	check("ashen_verge" in _targets(MapData.load_map("weeping_hollow")), "the Hollow's far gate leads to the Verge")
	check("ashen_verge" in _targets(MapData.load_map("sunken_fen")), "so does the road east out of the Fen")
	check("weeping_hollow" in _targets(verge) and "sunken_fen" in _targets(verge), "and the Verge leads back to both")
	check(ActDB.zone("ashen_verge").map == "ashen_verge" and ActDB.zone_name("ashen_verge") == "Ashen Verge", "it is a zone")
	check(String(verge.theme) == "ashen" and FileAccess.file_exists("res://assets/tiles/ashen/bg.png"), "the Verge has its own ashen look")
	check(MapTheme.load_sprite("ashen", "tree_11") != null and MapTheme.load_sprite("ashen", "bg") != null, "the ashen theme finds its own and the woodland's pictures")
	var ids := []
	for o in MapData.objects_of(verge, "boss"):
		ids.append(String(o.id))
	check("grave_warden" in ids and "rift_golem" in ids and BossDB.has("grave_warden") and BossDB.has("rift_golem"), "both bosses have a fight (%s)" % [ids])
	var scouts := 0
	for o in MapData.objects_of(verge, "pack"):
		if String(o.get("kind", "")) == "mutated_scout":
			scouts += 1
	check(scouts == 2, "two mutated scouts wait in the Verge (%d)" % scouts)
	var has_terrace := false
	for o in verge.objects:
		if o.type == "terrace":
			has_terrace = true
	check(has_terrace, "the mausoleum stands on raised ground")

	# Chapter 3 needs Chapter 2
	var ch3 := "a1_breaking_the_seal"
	check(not Quests.available(ch3), "Althea has no seal to break before the well is poisoned")
	GameState.quests["a1_first_incursion"] = {"state": Quests.DONE, "step": 5, "count": 0}
	GameState.quests["a1_poisoning_the_well"] = {"state": Quests.DONE, "step": 4, "count": 0}
	check(Quests.available(ch3) and Quests.npc_marker("althea") == "!", "after it she has the next chapter")
	check(Quests.npc_marker("dennis") == "!", "and Dennis has missing scouts")
	Quests.start(ch3)
	var watch := "a1_the_last_watch"
	Quests.start(watch)
	check(Quests.current_step(ch3).key == "ashen_verge", "Chapter 3 starts at the Verge")

	# The Ashen Verge
	GameState.current_zone = "ashen_verge"
	GameState.zone_entry = "weeping_hollow"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(1.2)
	var player: Player = zone.player
	_tough(player)
	check(Quests.current_step(ch3).key == "grave_warden", "crossing in is the first step")
	var foreign := 0
	for e in _enemies(zone):
		if not e.is_boss and String(e.pack).begins_with("zpack_") and not (e.kind in ActDB.zone("ashen_verge").kinds) and e.kind != "mutated_scout":
			foreign += 1
	check(foreign == 0 and _enemies(zone).size() > 70, "the Verge's own monsters (%d, %d foreign)" % [_enemies(zone).size(), foreign])
	check(_enemies(zone, "mutated_scout").size() == 2 and _enemies(zone, "bleed_fiend").size() >= 8, "two mutated scouts, and fiends round the rifts")
	check(zone._bosses.size() == 2, "both bosses stand at their posts (%d)" % zone._bosses.size())
	var hollow_exit: Node2D = null
	for e in zone._exits:
		if e.target == "weeping_hollow":
			hollow_exit = e.node
	check(hollow_exit != null and player.global_position.distance_to(hollow_exit.global_position) < 300.0, "arriving from the Hollow puts you at its gate")
	shot("verge_t_start.png")

	# The Maddened Grave Warden
	var warden: Enemy = null
	var golem: Enemy = null
	for b in zone._bosses:
		if String(b.get_meta("boss_id")) == "grave_warden":
			warden = b
		else:
			golem = b
	var warden_home := warden.global_position
	await _wake(zone, warden, warden_home)
	check(zone._boss == warden, "the screen follows the warden, though the golem was made after him")
	check(warden._shield_t <= 0.0, "his intro ends")
	shot("verge_t_warden.png")
	var adds0 := get_tree().get_nodes_in_group("boss_adds").size()
	warden.hp = warden.max_hp * 0.55
	await settle(2.8)
	check(warden.brain.phase == 1 and get_tree().get_nodes_in_group("boss_adds").size() > adds0, "at 60% the dead rise")
	check(golem.brain.state == BossBrain.S.SLEEP, "the golem sleeps through it")
	_kill(warden)
	await settle(0.8)
	check(Quests.current_step(ch3).key == "warden_half", "he falls: his half of the keystone")
	await settle(0.4)
	var half1 = _object(zone, "warden_half")
	check(half1 != null and half1.visible, "it can be taken")
	check(_object(zone, "golem_half") != null and not _object(zone, "golem_half").visible, "the golem's half cannot yet")
	half1.action.call()
	check(Quests.current_step(ch3).key == "rift_golem", "then the golem")
	for n in get_tree().get_nodes_in_group("boss_adds"):
		n.queue_free()

	# The Rift Golem
	await _wake(zone, golem, golem.global_position)
	check(zone._boss == golem, "the screen follows the golem now")
	shot("verge_t_golem.png")
	adds0 = get_tree().get_nodes_in_group("boss_adds").size()
	golem.hp = golem.max_hp * 0.6
	await settle(2.8)
	check(golem.brain.phase == 1 and get_tree().get_nodes_in_group("boss_adds").size() > adds0, "at 65% the rift tears and fiends come through")
	_kill(golem)
	await settle(0.8)
	check(Quests.current_step(ch3).key == "golem_half", "it falls: the second half")
	await settle(0.4)
	var half2 = _object(zone, "golem_half")
	check(half2 != null and half2.visible, "it can be taken")
	half2.action.call()
	check(Quests.current_step(ch3).key == "mausoleum_seal", "last, the mausoleum")
	await settle(0.3)
	var seal = _object(zone, "mausoleum_seal")
	check(seal != null and seal.visible, "the seal's plinth is waiting")
	player.global_position = seal.global_position + Vector2(0, 120)
	await settle(0.5)
	shot("verge_t_mausoleum.png")
	seal.action.call()
	check(Quests.state(ch3) == Quests.READY and Quests.npc_marker("althea") == "?", "ready to hand in to Althea")
	var got := Quests.turn_in(ch3, player)
	check(Quests.state(ch3) == Quests.DONE and got.size() >= 4, "the rewards are paid (%s)" % [got])
	check(Quests.boss_alive("grave_warden") and Quests.boss_alive("rift_golem"), "both bosses are there to farm again")

	# The Last Watch
	check(Quests.current_step(watch).key == "mutated_scout", "The Last Watch asks for the twisted scouts first")
	var mutants := _enemies(zone, "mutated_scout")
	_kill(mutants[0])
	await settle(0.2)
	check(Quests.step_index(watch) == 0, "one is not enough")
	_kill(mutants[1])
	await settle(0.2)
	check(Quests.current_step(watch).key == "mara", "then the survivor")
	var tower: Vector2 = Vector2.ZERO
	for o in MapData.objects_of(verge, "npc"):
		if o.id == "mara":
			tower = Vector2(float(o.x), float(o.y))
	check(tower != Vector2.ZERO, "Mara is at the watchtower")
	var opts := Quests.npc_options("mara")
	check(opts.size() == 1 and opts[0].action == "talk" and String(opts[0].text).contains("armory key"), "she talks about the key")
	Quests.notify("talk", "mara")
	check(Quests.state(watch) == Quests.READY and Quests.npc_marker("dennis") == "?", "back to Dennis")
	var kgot := Quests.turn_in(watch, player)
	var has_key := false
	for line in kgot:
		if String(line).contains("Armory Key"):
			has_key = true
	check(Quests.state(watch) == Quests.DONE and has_key, "Dennis pays, and the key is listed (%s)" % [kgot])
	zone.queue_free()
	await settle(0.4)

	# The way back to the Fen
	GameState.current_zone = "ashen_verge"
	GameState.zone_entry = "sunken_fen"
	zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(0.8)
	var fen_exit: Node2D = null
	for e in zone._exits:
		if e.target == "sunken_fen":
			fen_exit = e.node
	check(fen_exit != null and zone.player.global_position.distance_to(fen_exit.global_position) < 300.0, "from the Fen you stand at its road in the Verge")
	print("verge: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
