extends Node2D
## Quest bosses can be farmed once their quest is done: The Alpha is at the lodge before his quest and while it works
## towards him, not between his death and the hand-in, and on every fresh visit once it is handed in; each kill drops
## his rewards again, and the finished quest gives nothing more. (A kept zone is as it was left until Reset:
## test_instances.)
##   godot --path . --resolution 1600x720 res://scratch/test_boss_repeat.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _boss(zone) -> Enemy:
	for c in get_tree().get_nodes_in_group("enemies"):
		if c is Enemy and c.is_boss and zone.is_ancestor_of(c) and String(c.get_meta("boss_id", "")) == "briar_alpha":
			return c
	return null


func _visit(label: String, there := true) -> Node:
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await get_tree().create_timer(0.6).timeout
	check((_boss(zone) != null) == there, "The Alpha %s: %s" % ["is at the lodge" if there else "is not there", label])
	return zone


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	# Quest handed in long ago
	GameState.quests = {"a1_first_incursion": {"state": Quests.DONE, "step": 5, "count": 0}}
	var zone = await _visit("the quest is done")
	var boss := _boss(zone)
	var xp0 := GameState.xp
	var loot0 := get_tree().get_nodes_in_group("pickups").size()
	boss.take_damage(boss.max_hp * 100.0 * PartyScale.life())
	await get_tree().create_timer(0.5).timeout
	check(boss._dead, "he can be killed")
	check(get_tree().get_nodes_in_group("pickups").size() > loot0, "and drops his rewards again")
	check(Quests.state("a1_first_incursion") == Quests.DONE, "the finished quest is left alone")
	zone.queue_free()
	await get_tree().create_timer(0.3).timeout

	# Fresh visit again: back
	zone = await _visit("a new visit after he was killed")
	zone.queue_free()
	await get_tree().create_timer(0.3).timeout

	# He is dead in the story until the quest is handed in
	GameState.quests = {"a1_first_incursion": {"state": Quests.ACTIVE, "step": 3, "count": 0}}
	zone = await _visit("the quest is at the strongbox", false)
	zone.queue_free()
	await get_tree().create_timer(0.3).timeout
	GameState.quests = {"a1_first_incursion": {"state": Quests.READY, "step": 5, "count": 0}}
	zone = await _visit("the quest is ready to hand in", false)
	zone.queue_free()
	await get_tree().create_timer(0.3).timeout
	# Working towards him: there
	GameState.quests = {"a1_first_incursion": {"state": Quests.ACTIVE, "step": 2, "count": 0}}
	zone = await _visit("the quest is at his step")
	zone.queue_free()
	await get_tree().create_timer(0.3).timeout
	GameState.quests = {}
	zone = await _visit("before the quest")
	print("boss repeat: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
