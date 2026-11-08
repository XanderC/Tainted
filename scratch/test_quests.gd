extends Node2D
## Runs the quest engine end to end on Act I's first quests: The First Incursion (main: Brom to High Priestess Althea,
## through Dennis and the Briarwolf Alpha) and The Lost Heirloom (side: Merchant Corwin): offering, steps in order,
## the boss staying dead until the hand-in, turning in for rewards, markers and the tracker, saving, and an old
## character's quests moving over (Quests.migrate). Headless:
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
	check(Quests.npc_marker("corwin") == "!", "Corwin has a quest for you")
	check(Quests.npc_marker("battlemaster") == "!", "Brom has the main quest")
	check(Quests.npc_marker("althea") == "", "Althea has nothing yet")
	var lines := Quests.tracker_lines()
	check(lines.size() == 1 and lines[0]["text"].contains("Brom"), "the tracker points at the main quest giver")
	var opts := Quests.npc_options("corwin")
	check(opts.size() == 1 and opts[0]["action"] == "offer", "Corwin offers The Lost Heirloom")

	# The First Incursion, step by step
	var q := "a1_first_incursion"
	check(Quests.available(q), "the main quest can be picked up")
	Quests.start(q)
	check(Quests.state(q) == Quests.ACTIVE and Quests.current_step(q)["key"] == "briarwolf", "starts with the briarwolves at the gate")
	Quests.notify("talk", "dennis")
	check(Quests.step_index(q) == 0, "talking to Dennis early doesn't skip ahead")
	check(Quests.boss_alive("briar_alpha"), "the Alpha is waiting")
	for i in 7:
		Quests.notify("kill", "briarwolf")
	check(Quests.step_index(q) == 0, "seven of eight is not enough")
	Quests.notify("kill", "ghoul")
	check(Quests.step_index(q) == 0, "other monsters don't count")
	Quests.notify("kill", "briarwolf")
	check(Quests.current_step(q)["key"] == "hunting_lodge", "eight clear the road: next, the hunting lodge")
	Quests.notify("reach", "hunting_lodge")
	check(Quests.current_step(q)["key"] == "briar_alpha", "next: the Alpha")
	check(not Quests.wants("use", "rift_shard"), "the shard waits until the Alpha is dead")
	Quests.notify("kill_boss", "briar_alpha")
	check(not Quests.boss_alive("briar_alpha"), "the Alpha stays dead until the hand-in")
	check(Quests.wants("use", "rift_shard"), "now the shard can be taken")
	Quests.notify("use", "rift_shard")
	check(Quests.current_step(q)["key"] == "dennis", "then Dennis")
	var g := Quests.npc_options("dennis")
	check(g.size() == 1 and g[0]["action"] == "talk" and String(g[0]["text"]).contains("Althea"), "Dennis sends you to Althea")
	Quests.notify("talk", "dennis")
	check(Quests.state(q) == Quests.READY, "ready to hand in")
	check(Quests.npc_marker("althea") == "?", "Althea shows a ?")
	check(Quests.tracker_lines()[0]["text"].contains("Althea"), "the tracker says to go back to her")

	var orbs := GameState.orb_count("transmute")
	var xp := GameState.xp
	var lvl := GameState.level
	var points := GameState.skill_points
	var got := Quests.turn_in(q, p)
	check(Quests.state(q) == Quests.DONE, "done once handed in")
	check(GameState.orb_count("transmute") == orbs + 2, "2 transmutation orbs")
	check(GameState.xp > xp or GameState.level > lvl, "experience given")
	check(GameState.skill_points >= points + 1, "a passive point")
	check(got.size() >= 3, "the rewards are listed (%s)" % [got])
	check(Quests.turn_in(q, p).is_empty(), "it can't be handed in twice")
	check(Quests.npc_marker("althea") == "", "nothing more from Althea")
	check(Quests.boss_alive("briar_alpha"), "and the Alpha is back for good, to farm")

	# The Lost Heirloom: the lockbox, then Corwin's gem
	var h := "a1_lost_heirloom"
	Quests.start(h)
	Quests.notify("use", "lockbox")
	check(Quests.step_index(h) == 0, "the lockbox can't be taken before the manor is found")
	Quests.notify("reach", "ruined_manor")
	check(Quests.wants("use", "lockbox"), "the lockbox is wanted once you are at the manor")
	Quests.notify("use", "lockbox")
	check(Quests.state(h) == Quests.READY and Quests.npc_marker("corwin") == "?", "ready to hand in to Corwin")
	var gems := GameState.gem_count("topaz_2")
	var hgot := Quests.turn_in(h, p)
	check(Quests.state(h) == Quests.DONE and GameState.gem_count("topaz_2") == gems + 1, "the gem is paid (%s)" % [hgot])

	# An old character's quests move over
	var moved := Quests.migrate({
		"a1_into_the_wastes": {"state": "done", "step": 1, "count": 0},
		"a1_lost_caravan": {"state": "active", "step": 1, "count": 0},
		"nonsense": {"state": "active", "step": 0, "count": 0},
		h: {"state": "active", "step": 1, "count": 0}})
	check(moved.get("a1_first_incursion", {}).get("state", "") == "done", "the old first quest counts for The First Incursion")
	check(not moved.has("a1_lost_caravan") and not moved.has("a1_into_the_wastes") and not moved.has("nonsense"), "quests that no longer exist are dropped")
	check(moved.get(h, {}).get("state", "") == "active", "quests that do exist are kept as they were")
	var moved2 := Quests.migrate({"a1_lost_caravan": {"state": "done", "step": 4, "count": 0}})
	check(moved2.get(h, {}).get("state", "") == "done", "the old side quest counts for The Lost Heirloom")

	# A fresh visit to the Wilds: waypoint, exit, the zone full of monsters, and the Alpha is back (quest done)
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "town"
	var zn = load("res://scenes/zone.tscn").instantiate()
	add_child(zn)
	await get_tree().process_frame
	check(zn._waypoint != null and zn._exits.size() >= 1, "the zone has its waypoint and exit")
	check(get_tree().get_nodes_in_group("enemies").size() > 40, "the zone is full of monsters (%d)" % get_tree().get_nodes_in_group("enemies").size())
	check(zn._boss != null, "once the quest is handed in, its boss is back to fight again")
	check(zn.player.global_position.distance_to(zn._exits[0]["node"].global_position) < 300, "arriving from town puts you by the road back")

	# Saved with the character
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.quests))
	check(data.get(q, {}).get("state", "") == "done", "quest progress survives saving")

	print("quests: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
