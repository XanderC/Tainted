extends Node2D
## PoE2-style supports, second set (POE2_REFERENCE.md): Pierce I-III, Fork, Fire / Cold / Lightning Penetration and
## Exposure. Run headless:
##   godot --headless --path . res://scratch/test_supports_poe2b.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _skill(id: String, runes: Array) -> SkillDef:
	var s := SkillTree.get_skill(id)
	for r in runes:
		s.socketed_runes.append(String(r))
	return s


func _dummy(main: Node, at: Vector2, affix := "") -> Enemy:
	var d := Enemy.new()
	d.max_hp = 1.0e9
	d.speed = 0.0
	d.touch_damage = 0.0
	d.set_kind("zombie")
	if affix != "":
		d.affixes.append(affix)
	main.add_child(d)
	d.global_position = at
	return d


func _clear(main: Node) -> void:
	for c in main.get_children():
		if c is HirelingArrow or c is Enemy:
			c.queue_free()


func _lost(d: Enemy) -> float:
	return 1.0e9 - d.hp


func _ready() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	p.stats.add_mod("crit_chance", StatBlock.ModType.FLAT, -5.0, "test")  # no crits: the numbers are exact
	_clear(main)
	await get_tree().process_frame

	# The catalogue
	var ids := ["rune_pierce_1", "rune_pierce_2", "rune_pierce_3", "rune_fork", "rune_fire_penetration_1", "rune_fire_penetration_2",
		"rune_cold_penetration", "rune_lightning_penetration", "rune_fire_exposure", "rune_cold_exposure", "rune_lightning_exposure"]
	for id in ids:
		var r := RuneDef.DB.get_rune(id)
		check(r != null and r.family != "" and r.tier > 0 and not r.needs.is_empty() and r.player_only, "%s exists with a family, a tier and a restriction" % id)
		check(RuneDef.DB.get_rune(id + "@1") != null, "%s has a rarer version" % id)
	var p3 := RuneDef.DB.get_rune("rune_pierce_3")
	check(p3.pierce >= 99 and is_equal_approx(p3.pierce_less, 0.2), "Pierce III: all enemies, 20% less damage each")
	var fk := RuneDef.DB.get_rune("rune_fork")
	check(fk.forks == 2 and is_equal_approx(fk.fork_less, 0.3) and is_equal_approx(fk.cost_mult, 1.1), "Fork: two forks, 30% less damage, costs 1.1x")
	check(is_equal_approx(RuneDef.DB.get_rune("rune_fire_penetration_1").penetration, 0.3) and RuneDef.DB.get_rune("rune_fire_penetration_1").cost_mult == 1.2, "Fire Penetration I: 30%, costs 1.2x")
	check(RuneDef.DB.get_rune("rune_fire_penetration_2").penetration >= 1.0, "Fire Penetration II ignores it")
	check(p3.stat_lines().contains("pierce all enemies") and fk.stat_lines().contains("fork into 2") and RuneDef.DB.get_rune("rune_fire_exposure").stat_lines().contains("-20% fire resistance"),
		"the cards say what they do")

	# Restrictions and families
	var qs := SkillTree.get_skill("quick_shot")
	var cl := SkillTree.get_skill("cleave")
	var fb := SkillTree.get_skill("firebolt")
	check(SkillDef.supports_valid(["rune_pierce_1", "rune_fork"], qs), "Pierce and Fork go together on a projectile skill")
	check(not SkillDef.supports_valid(["rune_pierce_1"], cl) and not SkillDef.supports_valid(["rune_fork"], cl), "neither goes on Cleave")
	check(not SkillDef.supports_valid(["rune_pierce_1", "rune_pierce_3"], qs), "Pierce I and III do not go together")
	check(SkillDef.supports_valid(["rune_fire_penetration_1", "rune_cold_penetration"], fb), "Penetrations of two elements go together")
	check(not SkillDef.supports_valid(["rune_fire_penetration_1", "rune_fire_penetration_2"], fb), "Fire Penetration I and II do not")
	check(SkillDef.supports_valid(["rune_fire_penetration_1"], cl), "Penetration goes on any skill that hits")
	check(SkillDef.supports_not_for_hirelings(["rune_pierce_1"]) and SkillDef.supports_not_for_hirelings(["rune_fire_exposure"]), "a hireling cannot link them")

	# Penetration against a resisting monster
	var fireproof := _dummy(main, p.global_position + Vector2(900, 0), "fire_res")
	var plain := _dummy(main, p.global_position + Vector2(900, 80))
	await get_tree().process_frame
	check(is_equal_approx(fireproof.resist_mult(RuneDef.DamageType.FIRE), 0.3), "a Fireproof monster lets 30% of fire through")
	var base := SkillTree.get_skill("firebolt")
	var d0: float = p._hit_one(fireproof, base)
	fireproof.hp = 1.0e9
	var d1: float = p._hit_one(fireproof, _skill("firebolt", ["rune_fire_penetration_1"]))
	fireproof.hp = 1.0e9
	var d2: float = p._hit_one(fireproof, _skill("firebolt", ["rune_fire_penetration_2"]))
	check(absf(d1 / d0 - 2.0) < 0.01 or absf(p._penetration_scale(fireproof, _skill("firebolt", ["rune_fire_penetration_1"]), RuneDef.DamageType.FIRE) - 2.0) < 0.001,
		"Fire Penetration I: 0.3 -> 0.6 through (twice the damage)")
	check(absf(p._penetration_scale(fireproof, _skill("firebolt", ["rune_fire_penetration_2"]), RuneDef.DamageType.FIRE) - 1.0 / 0.3) < 0.001, "Fire Penetration II: all of it")
	check(p._penetration_scale(fireproof, _skill("firebolt", ["rune_cold_penetration"]), RuneDef.DamageType.FIRE) == 1.0, "Cold Penetration does nothing to a fire hit")
	check(is_equal_approx(p._penetration_scale(plain, _skill("firebolt", ["rune_fire_penetration_1"]), RuneDef.DamageType.FIRE), 1.0 + Player.PENETRATION_UNRESISTED),
		"against an unresisting monster it adds a little")
	check(d2 > d1 and d1 > d0, "the hits grow with it (%.1f %.1f %.1f)" % [d0, d1, d2])

	# Exposure
	var target := _dummy(main, p.global_position + Vector2(900, 160))
	check(p._exposing(_skill("firebolt", ["rune_fire_exposure"]), RuneDef.DamageType.FIRE, "burn", false) == "burn+exp", "an igniting fire hit exposes")
	check(p._exposing(_skill("firebolt", ["rune_fire_exposure"]), RuneDef.DamageType.FIRE, "", false) == "", "a fire hit that does not ignite does not")
	check(p._exposing(base, RuneDef.DamageType.FIRE, "burn", false) == "burn", "no support, no exposure")
	check(p._exposing(_skill("firebolt", ["rune_cold_exposure"]), RuneDef.DamageType.COLD, "chill", true) == "chill+exp" and p._exposing(_skill("firebolt", ["rune_cold_exposure"]), RuneDef.DamageType.COLD, "chill", false) == "chill",
		"cold exposes on a critical hit only")
	check(p._exposing(_skill("firebolt", ["rune_lightning_exposure"]), RuneDef.DamageType.LIGHTNING, "shock", false) == "shock+exp", "a shocking lightning hit exposes")
	p._hit_one(target, _skill("firebolt", ["rune_fire_exposure"]))
	check(target._exposed.has(RuneDef.DamageType.FIRE) and is_equal_approx(target.resist_mult(RuneDef.DamageType.FIRE), 1.2), "the target is exposed: 1.2 of a fire hit gets through")
	check(is_equal_approx(target.resist_mult(RuneDef.DamageType.COLD), 1.0), "only to fire")
	target.take_damage(1.0)
	var hp0: float = target.hp
	target.take_damage(100.0, false, RuneDef.DamageType.FIRE)
	check(absf((hp0 - target.hp) - 120.0 / PartyScale.life()) < 0.01, "and a fire hit does 20%% more (%.2f)" % (hp0 - target.hp))
	target._exposed[RuneDef.DamageType.FIRE] = 0.01
	await get_tree().create_timer(0.3).timeout
	check(not target._exposed.has(RuneDef.DamageType.FIRE), "exposure wears off")
	fireproof.hp = 1.0e9
	fireproof.take_damage(1.0, false, RuneDef.DamageType.FIRE, "burn+exp")
	check(is_equal_approx(fireproof.resist_mult(RuneDef.DamageType.FIRE), 0.5), "exposure on a Fireproof monster: 0.3 -> 0.5")

	# Pierce: shots along a line
	_clear(main)
	await get_tree().process_frame
	var line := []
	for k in 5:
		line.append(_dummy(main, p.global_position + Vector2(90 + 70 * k, -10)))
	await get_tree().process_frame
	p.facing = Vector2.RIGHT
	p._shoot(qs, Vector2.RIGHT, false, "arrow")
	await get_tree().create_timer(0.7).timeout
	var struck := line.filter(func(d): return d.hp < 1.0e9).size()
	check(struck == 1, "a plain arrow stops at the first enemy (%d)" % struck)
	for d in line:
		d.hp = 1.0e9
	p._shoot(_skill("quick_shot", ["rune_pierce_2"]), Vector2.RIGHT, false, "arrow")
	await get_tree().create_timer(0.7).timeout
	struck = line.filter(func(d): return d.hp < 1.0e9).size()
	check(struck == 4, "with Pierce II it goes through three and stops at the fourth (%d)" % struck)
	var l0: float = _lost(line[0])
	check(absf(_lost(line[1]) / l0 - 0.8) < 0.01 and absf(_lost(line[2]) / l0 - 0.64) < 0.01, "each pierce costs 20%% (%.2f, %.2f)" % [_lost(line[1]) / l0, _lost(line[2]) / l0])
	for d in line:
		d.hp = 1.0e9
	p._shoot(_skill("quick_shot", ["rune_pierce_3"]), Vector2.RIGHT, false, "arrow")
	await get_tree().create_timer(0.7).timeout
	struck = line.filter(func(d): return d.hp < 1.0e9).size()
	check(struck == 5, "Pierce III goes through them all (%d)" % struck)
	for d in line:
		d.hp = 1.0e9
	p._shoot(_skill("quick_shot", ["rune_pierce_1"]), Vector2.RIGHT, false, "arrow")
	await get_tree().create_timer(0.7).timeout
	struck = line.filter(func(d): return d.hp < 1.0e9).size()
	check(struck == 2, "Pierce I goes through one (%d)" % struck)

	# Fork: the arrow splits where it stops
	_clear(main)
	await get_tree().process_frame
	var first := _dummy(main, p.global_position + Vector2(100, -10))
	var up := _dummy(main, first.global_position + Vector2(150, 0).rotated(deg_to_rad(-28)))
	var down := _dummy(main, first.global_position + Vector2(150, 0).rotated(deg_to_rad(28)))
	var off := _dummy(main, first.global_position + Vector2(150, 0))
	await get_tree().process_frame
	p._shoot(_skill("quick_shot", ["rune_fork"]), Vector2.RIGHT, false, "arrow")
	await get_tree().create_timer(0.9).timeout
	check(first.hp < 1.0e9 and up.hp < 1.0e9 and down.hp < 1.0e9, "Fork: the arrow hits the first enemy and splits to two more")
	check(off.hp == 1.0e9, "the forks go either side, not straight on")
	check(absf(_lost(up) / _lost(first) - 0.7) < 0.01 and absf(_lost(down) / _lost(first) - 0.7) < 0.01, "the forks deal 30%% less (%.2f)" % (_lost(up) / _lost(first)))

	p.stats.remove_source("test")
	print("poe2 supports (2): ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
