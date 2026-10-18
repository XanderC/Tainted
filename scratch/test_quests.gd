extends Node2D
## Runs the quest engine end to end on The Lost Caravan and Into the Wastes: offering, steps in
## order, the boss staying dead, turning in for rewards, markers and the tracker, saving. Headless:
##   godot --headless --path . res://scratch/test_quests.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	var p: Player = town.player
	GameState.quests = {}
	GameState.waypoints = []
	GameState.tutorial_stage = GameState.TUTORIAL_DONE

	# Offers
	check(Quests.npc_marker("hesk") == "!", "Hesk has a quest for you")
	check(Quests.npc_marker("battlemaster") == "!", "Brom has the main quest")
	var lines := Quests.tracker_lines()
	check(lines.size() == 1 and lines[0]["text"].contains("Brom"), "the tracker points at the main quest giver")
	var opts := Quests.npc_options("hesk")
	check(opts.size() == 1 and opts[0]["action"] == "offer", "Hesk offers The Lost Caravan")

	# The Lost Caravan, step by step
	var q := "a1_lost_caravan"
	Quests.start(q)
	check(Quests.state(q) == Quests.ACTIVE and Quests.current_step(q)["key"] == "caravan_wreck", "starts at the wreck")
	Quests.notify("talk", "caravan_guard")
	check(Quests.step_index(q) == 0, "talking to the guard early doesn't skip ahead")
	check(Quests.boss_alive("raider_captain"), "Vesh is waiting")
	Quests.notify("reach", "caravan_wreck")
	check(Quests.npc_marker("caravan_guard") == "?", "the guard has something to say")
	var g := Quests.npc_options("caravan_guard")
	check(g.size() == 1 and g[0]["action"] == "talk" and String(g[0]["text"]).contains("Vesh"), "the guard tells you about Vesh")
	Quests.notify("talk", "caravan_guard")
	check(Quests.current_step(q)["key"] == "raider_captain", "next: the raider captain")
	check(not Quests.wants("use", "strongbox"), "the strongbox waits until Vesh is dead")
	Quests.notify("kill_boss", "raider_captain")
	check(not Quests.boss_alive("raider_captain"), "Vesh stays dead")
	check(Quests.wants("use", "strongbox"), "now the strongbox can be taken")
	Quests.notify("use", "strongbox")
	check(Quests.state(q) == Quests.READY, "ready to hand in")
	check(Quests.npc_marker("hesk") == "?", "Hesk shows a ?")

	var orbs := GameState.orb_count("alteration")
	var xp := GameState.xp
	var lvl := GameState.level
	var bag := p.bag.count()
	var got := Quests.turn_in(q, p)
	check(Quests.state(q) == Quests.DONE, "done once handed in")
	check(GameState.orb_count("alteration") == orbs + 3, "3 alteration orbs")
	check(GameState.xp > xp or GameState.level > lvl, "experience given")
	check(p.bag.count() == bag + 1, "the flask reward is in the bag")
	check(got.size() >= 3, "the rewards are listed (%s)" % [got])
	check(Quests.turn_in(q, p).is_empty(), "it can't be handed in twice")
	check(Quests.npc_marker("hesk") == "", "nothing more from Hesk")

	# Into the Wastes: the waypoint step, then Brom
	Quests.start("a1_into_the_wastes")
	Quests.notify("waypoint", "dune_wastes")
	check(Quests.state("a1_into_the_wastes") == Quests.READY, "touching the waypoint completes it")
	check(Quests.tracker_lines()[0]["text"].contains("Return to"), "the tracker says to go back")

	# Saved with the character
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.quests))
	check(data.get(q, {}).get("state", "") == "done", "quest progress survives saving")

	# The zone builds: map objects, packs, the boss gone since its quest is past it
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "town"
	var zn = load("res://scenes/zone.tscn").instantiate()
	add_child(zn)
	await get_tree().process_frame
	check(zn._waypoint != null and zn._exits.size() >= 1, "the zone has its waypoint and exit")
	check(get_tree().get_nodes_in_group("enemies").size() > 40, "the zone is full of monsters (%d)" % get_tree().get_nodes_in_group("enemies").size())
	check(zn._boss == null, "a dead quest boss doesn't come back")
	check(zn.player.global_position.distance_to(zn._exits[0]["node"].global_position) < 300, "arriving from town puts you by the road back")

	print("quests: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
