extends Node
## Where the experience of Act I comes from, to see what level a new character ends it on: each zone's monsters (the packs the zone
## really makes: PackSpots, the zone's kinds, a lead's chance to be elite) and bosses at the experience Enemy gives (max life x 0.4, a
## boss's x 0.6), the quests' rewards, and the level that total reaches. Prints a table.
##   godot --headless --path . res://scratch/measure_xp.tscn

const ZONES := ["dune_wastes", "weeping_hollow", "sunken_fen", "ashen_verge", "grand_ossuary_1", "grand_ossuary_2", "sepulcher_of_mourning"]


func level_at(total: float) -> float:
	var xp := total
	var l := 1
	while xp >= GameState.xp_to_next(l):
		xp -= GameState.xp_to_next(l)
		l += 1
	return float(l) + xp / GameState.xp_to_next(l)


func _ready() -> void:
	seed(99)
	var all_monsters := 0.0
	var all_bosses := 0.0
	print("%-22s %5s %8s %8s %8s" % ["zone", "packs", "mobs XP", "boss XP", "mobs"])
	for id in ZONES:
		var z := ActDB.zone(id)
		var lvl := int(z.area_level)
		var maze := MazeMap.new()
		maze.setup(String(z.map))
		var spots := PackSpots.for_map(maze, 10.0)  # Zone.CELLS_PER_PACK
		var pool: Array = z.get("kinds", MonsterKinds.pool(lvl))
		var mobs := 0.0
		var xp := 0.0
		var base := 25.0 * DungeonRun.hp_mult(lvl)
		for o in spots:
			var kind := String(o.get("kind", ""))
			var n := (int(o.get("min", 3)) + int(o.get("max", 5))) / 2.0
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
			lead /= 200.0
			xp += 0.4 * base * hpk * ((n - 1.0) + lead) * float(z.get("xp_scale", 1.0))
			mobs += n
		var bxp := 0.0
		for o in MapData.objects_of(maze.data, "boss"):
			var d := BossDB.def(String(o.id))
			bxp += float(d.xp) if d.has("xp") else 0.6 * base * float(o.get("hp", 8.0)) * float(d.get("hp", 1.0)) * float(z.get("xp_scale", 1.0))
		all_monsters += xp
		all_bosses += bxp
		print("%-22s %5d %8.0f %8.0f %8.0f" % [id, spots.size(), xp, bxp, mobs])
		maze.free()
	var quests := 0.0
	var main_quests := 0.0
	for id in QuestDB.QUESTS:
		var q: Dictionary = QuestDB.quest(id)
		if int(q.get("act", 0)) != 1:
			continue
		var x: float = float(q.get("rewards", {}).get("xp", 0.0))
		if x <= 0.0:
			for c in q.get("rewards", {}).get("choose", []):
				x = maxf(x, float(c.get("xp", 0.0)))
		quests += x
		if q.get("kind", "") == "main":
			main_quests += x
		print("  quest %-26s %-5s %6.0f" % [id, q.get("kind", ""), x])
	print("monsters %.0f   bosses %.0f   quests %.0f (main %.0f)" % [all_monsters, all_bosses, quests, main_quests])
	for share in [0.4, 0.6, 0.8, 1.0]:
		var tot: float = (all_monsters + all_bosses) * share + quests
		print("  all quests + %3.0f%% of the monsters and bosses: %7.0f xp = level %.1f" % [share * 100.0, tot, level_at(tot)])
	print("  main quests only + bosses + 40%% of monsters: level %.1f" % level_at(main_quests + all_bosses + all_monsters * 0.4))
	for L in [10, 12, 14, 15, 17, 18]:
		var need := 0.0
		for l in range(1, L):
			need += GameState.xp_to_next(l)
		print("  reaching level %d takes %.0f xp" % [L, need])
	get_tree().quit()
