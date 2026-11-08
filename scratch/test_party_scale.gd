extends Node2D
## Diablo II style "Players X" (PartyScale): the more players in the area, the more it takes to kill a monster,
## and the more XP and drops each kill gives; alone, nothing changes. Players are the RemotePlayers in the scene,
## so this fakes them with nodes in that group.
##   godot --path . --resolution 1600x720 res://scratch/test_party_scale.tscn

var _fails := 0
var _fakes: Array[Node] = []


## What a monster asks of a RemotePlayer when it looks for someone to go for: a dead one is passed over.
class FakeRemote extends Node2D:
	var dead := true
	var hp := 1.0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _players(n: int) -> void:  # n players in all: you and n - 1 others
	for f in _fakes:
		f.queue_free()
	_fakes.clear()
	for i in n - 1:
		var f := FakeRemote.new()
		f.add_to_group("remote_players")
		add_child(f)
		_fakes.append(f)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	check(PartyScale.size() == 1 and PartyScale.life() == 1.0 and PartyScale.xp() == 1.0 and PartyScale.drops() == 1.0 and PartyScale.summary() == "", "alone: nothing changes")
	_players(3)
	await get_tree().process_frame
	check(PartyScale.size() == 3, "three players here (%d)" % PartyScale.size())
	check(is_equal_approx(PartyScale.life(), 1.0 + 2.0 * PartyScale.LIFE_PER_EXTRA), "life x%.2f" % PartyScale.life())
	check(PartyScale.xp() > 1.0 and PartyScale.drops() > 1.0, "more XP and more drops")
	check(PartyScale.summary().contains("life") and PartyScale.summary().contains("XP"), "the party list says so (%s)" % PartyScale.summary())
	_players(1)
	await get_tree().process_frame
	check(PartyScale.size() == 1, "and it goes when they leave")

	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await get_tree().create_timer(1.0).timeout

	# Life: the same blow takes less of it with more players
	var e: Enemy = null
	for c in get_tree().get_nodes_in_group("enemies"):
		if c is Enemy and c.tier == MonsterAffix.Tier.NORMAL and not c.is_boss:
			e = c
			break
	check(e != null, "a plain monster to hit")
	e.max_hp = 1000.0
	e.hp = 1000.0
	var h0 := e.hp
	e.take_damage(10.0)
	var alone := h0 - e.hp
	_players(3)
	await get_tree().process_frame
	var h1 := e.hp
	e.take_damage(10.0)
	var party := h1 - e.hp
	check(alone > 5.0 and absf(party - alone / PartyScale.life()) < 0.01, "a blow does %.2f alone, %.2f with three (life x%.1f)" % [alone, party, PartyScale.life()])
	e.take_damage(0.0)

	# XP: a kill gives more
	_players(1)
	await get_tree().process_frame
	GameState.level = 30  # no level-ups in the way of reading the XP
	var lvl := GameState.level
	GameState.xp = 0.0
	var e1: Enemy = get_tree().get_nodes_in_group("enemies")[1] as Enemy
	e1.take_damage(e1.hp * 10.0 * PartyScale.life())
	var gain1 := GameState.xp if GameState.level == lvl else -1.0
	_players(3)
	await get_tree().process_frame
	GameState.xp = 0.0
	var e2: Enemy = get_tree().get_nodes_in_group("enemies")[2] as Enemy
	e2.max_hp = e1.max_hp
	e2.take_damage(e2.hp * 10.0 * PartyScale.life())
	var gain3 := GameState.xp if GameState.level == lvl else -1.0
	check(gain1 > 0.0 and gain3 > 0.0 and absf(gain3 / gain1 - PartyScale.xp()) < 0.01, "a kill gives %.1f XP alone, %.1f with three (x%.2f)" % [gain1, gain3, PartyScale.xp()])

	# Drops: over many kills, more of them
	_players(1)
	await get_tree().process_frame
	var dummy := Enemy.new()
	var n1 := _drops(zone, dummy, 1500)
	_players(4)
	await get_tree().process_frame
	var n4 := _drops(zone, dummy, 1500)
	check(n4 > n1 * 1.3, "1500 kills drop %d things alone, %d with four" % [n1, n4])
	print("party scale: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _drops(zone: Node, dummy: Enemy, kills: int) -> int:
	var total := 0
	for i in kills:
		zone._on_monster_died(dummy, Vector2(100, 100))
		for p in get_tree().get_nodes_in_group("pickups"):
			total += 1
			p.remove_from_group("pickups")
			p.queue_free()
	return total
