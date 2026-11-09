extends Node
## Act I's pacing: a new character should finish it on levels 12 to 17 (its quests, bosses and monsters add up to that), and its bosses
## should last (a character of the level the story has brought you to, doing about 90 damage a second a level, with some of it lost to dodging,
## takes about half a minute for the first boss and two and a half for Lord Malaphax). Also that the numbers are really used: a boss has the
## life BossDB gives it, and gives the experience it names. Run:
##   godot --headless --path . res://scratch/test_pacing.tscn

const ZONES := ["dune_wastes", "weeping_hollow", "sunken_fen", "ashen_verge", "grand_ossuary_1", "grand_ossuary_2", "sepulcher_of_mourning"]
## The level a typical character has reached when it meets each boss (the quests and bosses before it, and 70% of the monsters)
const BOSSES := ["briar_alpha", "matron_vhol", "grave_warden", "rift_golem", "herald_oren", "herald_sable", "herald_morrow", "lord_malaphax"]
const AT_LEVEL := {"briar_alpha": 3.5, "matron_vhol": 5.5, "grave_warden": 8.5, "rift_golem": 9.3, "herald_oren": 10.5, "herald_sable": 11.2,
	"herald_morrow": 12.6, "lord_malaphax": 13.7}

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func xp_for_level(level: float) -> float:
	var total := 0.0
	for l in range(1, int(level)):
		total += GameState.xp_to_next(l)
	return total + (level - floorf(level)) * GameState.xp_to_next(int(level))


func level_at(total: float) -> float:
	var xp := total
	var l := 1
	while xp >= GameState.xp_to_next(l):
		xp -= GameState.xp_to_next(l)
		l += 1
	return float(l) + xp / GameState.xp_to_next(l)


## What a zone's monsters give if you kill them all (the packs it really makes).
func trash(id: String) -> float:
	var z := ActDB.zone(id)
	var lvl := int(z.area_level)
	var maze := MazeMap.new()
	maze.setup(String(z.map))
	var pool: Array = z.get("kinds", MonsterKinds.pool(lvl))
	var base := 25.0 * DungeonRun.hp_mult(lvl)
	var xp := 0.0
	for o in PackSpots.for_map(maze, 10.0):
		var n := (int(o.get("min", 3)) + int(o.get("max", 5))) / 2.0
		var kind := String(o.get("kind", ""))
		var hpk := 0.0
		if MonsterKinds.KINDS.has(kind):
			hpk = float(MonsterKinds.KINDS[kind].get("hp", 1.0))
		else:
			for k in pool:
				hpk += float(MonsterKinds.KINDS[k].get("hp", 1.0)) / pool.size()
		var lead := 0.0
		for t in 200:
			var tier := MonsterAffix.roll_tier(lvl)
			lead += float(MonsterAffix.TIERS[tier].hp) if tier != MonsterAffix.Tier.NORMAL else 1.0
		xp += 0.4 * base * hpk * ((n - 1.0) + lead / 200.0) * float(z.get("xp_scale", 1.0))
	maze.free()
	return xp


func _ready() -> void:
	seed(7)
	var quests := 0.0
	var main_quests := 0.0
	for id in QuestDB.QUESTS:
		var q: Dictionary = QuestDB.quest(id)
		if int(q.get("act", 0)) != 1:
			continue
		var x: float = 0.0
		if q.get("rewards", {}).has("xp"):
			x = float(q.rewards.xp)
		else:
			for c in q.get("rewards", {}).get("choose", []):
				x = maxf(x, float(c.get("xp", 0.0)))
		quests += x
		if q.get("kind", "") == "main":
			main_quests += x
	var bosses := 0.0
	for b in BOSSES:
		var d := BossDB.def(b)
		check(d.has("life") and d.has("xp") and d.has("power"), "%s has its life, xp and power set" % b)
		bosses += float(d.get("xp", 0.0))
	var mobs := 0.0
	for id in ZONES:
		check(ActDB.zone(id).has("xp_scale"), "%s has an xp_scale" % id)
		mobs += trash(id)

	# The level the act ends on
	var floor_xp := main_quests + bosses  # the main story and its bosses, no other monster
	var typical := quests + bosses + mobs * 0.7
	var ceiling := quests + bosses + mobs * 1.1 + 1500.0  # everything, and the events and mini-dungeons (about 1500)
	print("pacing: main story + bosses %.0f xp = level %.1f; typical %.0f = %.1f; everything %.0f = %.1f (monsters %.0f)" % [
		floor_xp, level_at(floor_xp), typical, level_at(typical), ceiling, level_at(ceiling), mobs])
	check(level_at(floor_xp) >= 12.0, "a player who does only the main story ends on level 12 or more (%.1f)" % level_at(floor_xp))
	check(level_at(ceiling) <= 17.0, "one who does everything ends on level 17 or less (%.1f)" % level_at(ceiling))
	check(level_at(typical) >= 13.5 and level_at(typical) <= 16.0, "a typical player ends in the middle of it (%.1f)" % level_at(typical))

	# The bosses last
	for b in BOSSES:
		var d := BossDB.def(b)
		var dps := 0.6 * 90.0 * float(AT_LEVEL[b])
		var seconds := float(d.life) / dps
		var lo := 15.0 if b != "lord_malaphax" else 120.0
		var hi := 70.0 if b != "lord_malaphax" else 200.0
		print("  %-14s life %6.0f at level %4.1f: about %3.0f s" % [b, d.life, AT_LEVEL[b], seconds])
		check(seconds >= lo and seconds <= hi, "%s lasts %.0f s (%.0f to %.0f)" % [b, seconds, lo, hi])

	# The numbers are used
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.quests = {"a1_first_incursion": {"state": "done", "step": 5, "count": 0}, "a1_poisoning_the_well": {"state": "done", "step": 4, "count": 0}}
	GameState.current_zone = "ashen_verge"
	GameState.zone_entry = "start"
	var zone: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await get_tree().create_timer(0.5).timeout
	var any := false
	for b in zone._bosses:
		var id := String(b.get_meta("boss_id"))
		any = true
		check(absf(b.max_hp - float(BossDB.def(id).life)) < 1.0, "%s is spawned with %.0f life (%.0f)" % [id, BossDB.def(id).life, b.max_hp])
		check(b.xp_override == float(BossDB.def(id).xp), "and gives %.0f experience" % BossDB.def(id).xp)
		check(b.touch_damage > 8.0 * 1.4 * float(BossDB.def(id).power) * 0.99, "and hits %.1fx as hard" % BossDB.def(id).power)
	check(any, "the Verge has its bosses")
	var xp0 := GameState.xp
	var lvl0 := GameState.level
	GameState.xp = 0.0
	GameState.level = 5
	var w: Enemy = zone._bosses[0]
	var before := GameState.xp
	w._shield_t = 0.0
	w.take_damage(w.max_hp * 100.0)
	await get_tree().create_timer(0.3).timeout
	var got := GameState.xp
	for l in range(5, GameState.level):
		got += GameState.xp_to_next(l)
	check(absf(got - float(w.xp_override)) < 1.0, "killing it pays its experience (%.0f of %.0f)" % [got, w.xp_override])
	var mob := zone._spawn_enemy(zone.player.global_position + Vector2(300, 0), "t", "skeleton", MonsterAffix.Tier.NORMAL)
	check(is_equal_approx(mob.xp_scale, 0.076), "an ordinary monster there gives %.3f of the usual" % mob.xp_scale)
	GameState.xp = xp0
	GameState.level = lvl0
	print("pacing: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
