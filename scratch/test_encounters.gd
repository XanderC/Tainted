extends Node2D
## Random encounters (ZoneEncounters), forced in the Ashwood and played through: the cottage's zombies
## come out when you get close, clearing them frees a captive who pays out; the ritual starts its
## countdown when you get close, each dead cultist buys time, running out calls a boss, and killing
## them all breaks it and pays out. Also: a spot is found on open floor away from the start, and a
## visit with no encounter has none. Run:
##   godot --headless --path . res://scratch/test_encounters.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func settle(n := 4) -> void:
	for i in n:
		await get_tree().process_frame


func kill_all(list: Array) -> void:
	for e in list.duplicate():
		if is_instance_valid(e):
			e.take_damage(1.0e9)


func loot_count(zone: Zone) -> int:
	return zone.get_children().filter(func(n): return n is LootPickup or n is CurrencyPickup).size()


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(6)
	for e in zone.get_children().filter(func(n): return n is ZoneEncounters):
		e.queue_free()  # (a random one may have been rolled: start clean)
	await settle()

	# --- the cottage ---
	var cot := ZoneEncounters.roll(zone, "cottage")
	check(cot != null, "a cottage can be placed")
	await settle()
	check(cot.pos.distance_to(zone.maze.start_pos) >= ZoneEncounters.MIN_FROM_START, "it is away from the start")
	check(not zone.maze.is_wall(zone.maze.world_to_cell(cot.pos)), "it is on open floor")
	check(cot.state == "closed" and cot.foes.is_empty(), "closed at first, nobody out")
	zone.player.global_position = cot.pos + Vector2(0, 700)
	await settle()
	check(cot.state == "closed", "far away it stays shut")
	zone.player.global_position = cot.pos + Vector2(0, 250)
	await settle()
	check(cot.state == "fight" and cot.foes.size() >= 5, "close: the zombies burst out (%d)" % cot.foes.size())
	var before := loot_count(zone)
	kill_all(cot.foes)
	await settle(4)
	check(cot.state == "captive", "all dead: the captive is there (%s)" % cot.state)
	var who := zone.get_children().filter(func(n): return n is Interactable and n.prompt == "Free the captive")
	check(who.size() == 1, "one captive to free")
	var loot_before := loot_count(zone)
	if who.size() == 1:
		who[0].action.call()
	await settle()
	check(cot.state == "done", "freed")
	check(loot_count(zone) > loot_before, "the captive paid out")
	cot.queue_free()

	# --- the ritual: it runs out ---
	var rit := ZoneEncounters.roll(zone, "ritual")
	check(rit != null, "a ritual can be placed")
	await settle()
	check(rit.state == "waiting" and rit.foes.size() >= 3, "cultists waiting (%d)" % rit.foes.size())
	zone.player.global_position = rit.pos + Vector2(0, 800)
	await settle()
	check(rit.state == "waiting", "far away it has not begun")
	zone.player.global_position = rit.pos + Vector2(0, 500)
	await settle()
	check(rit.state == "chant" and rit.time_left > 40.0, "close: the chanting starts")
	var t0 := rit.time_left
	var first: Enemy = rit.foes[0]
	first.take_damage(1.0e9)
	await settle(2)
	check(rit.time_left > t0 - 1.0 and rit.foes.size() >= 2, "a dead cultist buys time")
	rit.time_left = -1.0
	await settle(4)
	check(rit.state == "summoned", "time's up: it is summoned (%s)" % rit.state)
	check(is_instance_valid(zone._boss) and zone._boss.display_name == "Summoned Horror", "a Summoned Horror appears")
	if is_instance_valid(zone._boss):
		zone._boss.take_damage(1.0e12)
	kill_all(rit.foes)
	await settle(6)
	check(rit.state == "done", "the horror dies and it is done (%s)" % rit.state)
	rit.queue_free()

	# --- the ritual: broken in time ---
	var rit2 := ZoneEncounters.roll(zone, "ritual")
	await settle()
	zone.player.global_position = rit2.pos + Vector2(0, 500)
	await settle()
	var loot2 := loot_count(zone)
	kill_all(rit2.foes)
	await settle(4)
	check(rit2.state == "done" and rit2.time_left > 0.0, "all cultists dead in time: broken")
	check(loot_count(zone) > loot2, "breaking it pays out")
	print("encounters: ", "ok" if fails == 0 else "%d failed" % fails)
	get_tree().quit(fails)
