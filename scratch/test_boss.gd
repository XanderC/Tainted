extends Node2D
## A boss fight with BossDB's Vesh, the Raider Captain, in the Ashwood: he wakes with an intro (roaring, untouchable)
## and the arena seals; his attacks hurt only what stands in their warning; he moves through his phases
## (roaring, calling adds), enrages after a while, and dies, opening the arena, taking his adds with him and
## dropping his rewards. Then a party member's copy of him (no brain) seals and opens the arena the same way.
## Takes scratch/boss_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_boss.tscn

var _fails := 0
var player: Player


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name_))


func refill() -> void:
	player.hp = player.stats.get_stat("max_life")


func lost() -> float:
	return player.stats.get_stat("max_life") - player.hp


func count_group(g: String) -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group(g):
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			n += 1
	return n


## Waits for the boss's untouchable spell (intro, a roar) to run out by itself, as it does for a player; it must.
func hurtable(boss: Enemy) -> void:
	var waited := 0.0
	while boss._shield_t > 0.0 and waited < 5.0:
		await settle(0.1)
		waited += 0.1
	check(boss._shield_t <= 0.0, "his untouchable spell runs out by itself (%.1f s)" % waited)


func boss_object(zone) -> Dictionary:
	for o in MapData.objects_of(zone.maze.data, "boss"):
		return o
	return {}


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(0.5)
	player = zone.player
	var obj := boss_object(zone)
	check(not obj.is_empty(), "the Ashwood has its boss object")
	var home := Vector2(float(obj.x), float(obj.y))
	var reach: float = float(BossDB.def("raider_captain").arena) + Zone.ARENA_CLEAR
	var camp_packs := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_boss and String(e.pack).begins_with("zpack_") and e.global_position.distance_to(home) < reach - 80.0:  # (a pack's members stand up to 70 px round its centre)
			camp_packs += 1
			print("  near the camp: ", e.pack, " ", e.kind, " ", e.global_position.distance_to(home))
	check(camp_packs == 0, "no ordinary packs in or round his arena (%d)" % camp_packs)
	var packs_elsewhere := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_boss and String(e.pack).begins_with("zpack_"):
			packs_elsewhere += 1
	check(packs_elsewhere > 100, "the rest of the zone is still full (%d monsters)" % packs_elsewhere)
	if zone._boss != null and is_instance_valid(zone._boss):
		zone._boss.queue_free()  # (the zone made him already: make our own, with the old one's ring gone first)
	await settle(0.3)
	zone._spawn_boss(obj)
	var boss: Enemy = zone._boss
	var brain: BossBrain = boss.brain
	check(brain != null, "Vesh has a brain")
	check(boss.aggro_range < 500.0, "he wakes inside his arena (%.0f)" % boss.aggro_range)
	check(BossDB.has("raider_captain") and not BossDB.has("nobody"), "BossDB knows him and no one else")
	check(count_group("boss_arena") == 1, "his arena is placed")
	check(BossArena.current == null, "and not sealed while he sleeps")

	# Walk up: he wakes
	player.global_position = home + Vector2(-380, 40)
	refill()
	await settle(0.5)
	check(boss._aggro, "he wakes when the player comes inside the arena")
	check(brain.state == BossBrain.S.INTRO, "he starts with his intro")
	check(boss._shield_t > 0.0, "and can't be hurt during it")
	var hp0 := boss.hp
	boss.take_damage(1000.0)
	check(is_equal_approx(boss.hp, hp0), "a hit during the intro does nothing")
	await settle(0.4)
	check(BossArena.current != null and BossArena.current.sealed, "the arena seals round them")
	check(count_group("boss_bar") == 1 and zone._boss_bar.visible, "his health bar is up")
	shot("boss_intro.png")

	# The ring holds: the player is stopped walking out
	var inside := player.global_position
	player.global_position = home + Vector2(BossArena.current.radius - 60.0, 0)
	player.velocity = Vector2(900, 0)
	for i in 30:
		player.velocity = Vector2(900, 0)
		player.move_and_slide()
		await get_tree().physics_frame
	check(player.global_position.distance_to(home) < BossArena.current.radius + 10.0, "the ring stops the player leaving (%.0f of %.0f)" % [player.global_position.distance_to(home), BossArena.current.radius])
	# ... but a hireling, a pet or an ally walks through it (a CharacterBody2D as theirs: layer 0, mask walls only)
	var follower := CharacterBody2D.new()
	follower.collision_layer = 0
	follower.collision_mask = 1
	var fs := CollisionShape2D.new()
	var fc := CircleShape2D.new()
	fc.radius = 20.0
	fs.shape = fc
	follower.add_child(fs)
	zone.add_child(follower)
	# (some way round the ring there are real walls too: look where the camp is open, i.e. where the follower is free)
	var crossed := 0
	var stopped := 0
	for k in 16:
		var dir := Vector2.from_angle(TAU * k / 16.0)
		var out_at := home + dir * (BossArena.current.radius + 60.0)
		follower.global_position = out_at
		var free := not follower.test_move(follower.global_transform, -dir * 120.0)
		player.global_position = out_at
		var blocked := player.test_move(player.global_transform, -dir * 120.0)
		if free:
			crossed += 1
			if blocked:
				stopped += 1
	check(crossed > 0, "a hireling or pet crosses the ring (%d of 16 ways round)" % crossed)
	check(stopped == crossed and crossed > 0, "where the player and the monsters can't (%d of %d)" % [stopped, crossed])
	follower.queue_free()
	player.global_position = home + Vector2(-380, 40)

	# His intro ends and he fights: each move in turn
	await settle(2.0)
	check(brain.state != BossBrain.S.INTRO and brain.state != BossBrain.S.SLEEP, "the intro ends")
	# Natural fighting: let him pick moves for a while (the player stays put, can't die)
	for i in 28:
		refill()
		await settle(0.25)
	check(brain.moves_used.size() > 0, "he uses his moves (%s)" % str(brain.moves_used))

	# Where each attack hurts, with the boss and player placed by hand
	boss.global_position = home
	brain._aim = Vector2.RIGHT
	var o := boss.global_position
	var at := func(p: Vector2): player.global_position = p; refill()
	at.call(o + Vector2(300, 0))
	brain._hurt_cone(o, Vector2.RIGHT, 0.75, 620.0, 20.0)
	check(lost() > 0.0, "a volley's cone hurts one standing in it")
	for miss in [Vector2(300, 300), Vector2(-300, 0), Vector2(700, 0)]:
		at.call(o + miss)
		brain._hurt_cone(o, Vector2.RIGHT, 0.75, 620.0, 20.0)
		check(lost() == 0.0, "... and not one at %s" % str(miss))
	at.call(o + Vector2(400, 20))
	brain._hurt_line(o, Vector2.RIGHT, 760.0, 64.0, 20.0)
	check(lost() > 0.0, "a pin shot's line hurts one on it")
	at.call(o + Vector2(400, 120))
	brain._hurt_line(o, Vector2.RIGHT, 760.0, 64.0, 20.0)
	check(lost() == 0.0, "... and not one to the side")
	at.call(o + Vector2(100, 0))
	brain._hurt_circle(o + Vector2(100, 0), 100.0, 20.0)
	check(lost() > 0.0, "a circle hurts one inside it")
	brain._hurt_circle(o + Vector2(500, 0), 100.0, 20.0)
	check(lost() > 0.0, "... (control)")
	refill()
	brain._hurt_circle(o + Vector2(500, 0), 100.0, 20.0)
	check(lost() == 0.0, "... and not one outside it")

	# A move end to end: rain shows five circles at once and lands on the player standing in one
	while brain.state != BossBrain.S.IDLE:
		await settle(0.1)
	at.call(o + Vector2(300, 0))
	for k in brain._cd.keys():
		brain._cd[k] = 0.0
	brain.begin("rain")
	await settle(0.15)
	check(count_group("boss_telegraphs") == 5, "rain warns of five circles (%d)" % count_group("boss_telegraphs"))
	shot("boss_rain.png")
	await settle(1.45)
	check(lost() > 0.0, "and the one on the player lands")
	check(count_group("boss_telegraphs") == 0, "the warnings are gone after")
	await settle(1.2)
	at.call(o + Vector2(300, 0))
	brain.begin("volley")
	await settle(0.2)
	check(count_group("boss_telegraphs") == 1, "a volley warns with one cone")
	shot("boss_volley.png")
	await settle(1.0)
	check(lost() > 0.0, "and hurts the player in front of him")

	# Phase two: at 65%
	await settle(1.0)
	await hurtable(boss)
	boss.hp = boss.max_hp * 0.6
	for i in 40:
		refill()
		await settle(0.1)
		if brain.phase >= 1:
			break
	check(brain.phase == 1, "he is in phase two at 60% life")
	check(brain.state == BossBrain.S.ROAR or boss._shield_t > 0.0 or brain.phase == 1, "he roars")
	await settle(0.5)
	check(count_group("boss_adds") >= 4, "he called his adds (%d)" % count_group("boss_adds"))
	check(count_group("boss_adds") <= int(BossDB.def("raider_captain").max_adds), "no more than he is allowed")
	shot("boss_phase2.png")
	# Phase three: at 30%, and the adds stay capped
	await settle(2.0)
	await hurtable(boss)
	boss.hp = boss.max_hp * 0.25
	for i in 60:
		refill()
		await settle(0.1)
		if brain.phase >= 2:
			break
	check(brain.phase == 2, "and phase three at 25%")
	check(count_group("boss_adds") <= int(BossDB.def("raider_captain").max_adds), "adds still capped (%d)" % count_group("boss_adds"))

	# Enrage
	var speed0 := boss.speed
	brain.fight_t = float(BossDB.def("raider_captain").enrage) - 0.1
	await settle(0.5)
	check(brain.enraged and boss.speed > speed0, "he enrages after his time")

	# He dies: the arena opens, his adds fall, and his rewards drop
	await settle(2.0)
	await hurtable(boss)
	var items_before := count_group("pickups")
	boss.hp = 1.0
	boss.take_damage(1000.0)
	await settle(1.5)
	check(boss._dead, "he dies")
	check(BossArena.current == null, "the arena opens")
	await settle(1.5)
	check(count_group("boss_arena") == 0, "and the ring is gone")
	check(count_group("boss_adds") == 0, "his adds go with him")
	var rewards := count_group("pickups") - items_before
	check(rewards >= 4, "his rewards drop (%d pickups: 2 rares, a magic, currency)" % rewards)
	check(not zone._boss_bar.visible, "his bar goes")

	# Walking out: nothing holds the player now
	player.global_position = home + Vector2(700.0, 0)
	for i in 10:
		player.velocity = Vector2(300, 0)
		player.move_and_slide()
		await get_tree().physics_frame
	check(player.global_position.x > home.x + 700.0, "the player walks out of where the ring was")

	zone.queue_free()
	await settle(0.4)

	# A party member's copy: no brain, but the same ring and bar
	var zone2 = load("res://scenes/zone.tscn").instantiate()
	add_child(zone2)
	await settle(0.5)
	player = zone2.player
	if zone2._boss != null and is_instance_valid(zone2._boss):
		zone2._boss.queue_free()  # (this zone made its own Vesh: the copy takes his place)
	await settle(0.3)
	var copy := Enemy.new()
	copy.remote = true
	copy.is_boss = true
	copy.net_id = 77
	copy.kind = "bandit_archer"
	copy.skin = "archer_guy"
	copy.display_name = "Vesh, the Raider Captain"
	copy.max_hp = 1000.0
	copy.size_mult = 1.45
	copy.position = home
	copy.target = player
	copy.set_meta("boss_id", "raider_captain")
	zone2.coop_copy(copy, {})
	zone2.add_child(copy)
	copy.hp = 1000.0
	await settle(0.3)
	check(copy.brain == null, "a copy has no brain")
	check(count_group("boss_arena") == 1, "but has the arena")
	player.global_position = home + Vector2(-300, 0)
	copy.apply_snapshot([77, home.x, home.y, 900.0, "Idle", 1.0, 256])  # the host's: he is awake
	await settle(0.5)
	check(BossArena.current != null and BossArena.current.sealed, "the ring seals when the host's boss wakes")
	check(zone2._boss_bar.visible, "and his bar shows")
	copy.remote_die()
	await settle(1.5)
	check(BossArena.current == null, "it opens when he dies on the host's game")

	print("boss: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
