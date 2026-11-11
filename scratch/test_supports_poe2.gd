extends Node2D
## PoE2-style supports (POE2_REFERENCE.md): families of tiers (one per family), each restricted to the skills it suits,
## with the trade-offs poe2db.tw states: Multishot (+2 projectiles, less damage and speed), Chain, Rapid Attacks and
## Casting, Controlled Destruction, Magnified Area, Life Leech, the elemental Masteries. Run headless:
##   godot --headless --path . res://scratch/test_supports_poe2.tscn

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


func _arrows(parent: Node) -> int:
	return parent.get_children().filter(func(c): return c is HirelingArrow and not c.is_queued_for_deletion()).size()


func _ready() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player

	# The catalogue
	var ids := ["rune_multishot_1", "rune_multishot_2", "rune_chain_1", "rune_chain_2", "rune_rapid_attacks_1", "rune_rapid_casting_1",
		"rune_controlled_destruction", "rune_magnified_area_1", "rune_life_leech_1", "rune_fire_mastery", "rune_cold_mastery",
		"rune_lightning_mastery", "rune_chaos_mastery"]
	for id in ids:
		var r := RuneDef.DB.get_rune(id)
		check(r != null and r.family != "" and r.tier > 0 and not r.needs.is_empty(), "%s exists with a family, a tier and a restriction" % id)
		check(RuneDef.DB.get_rune(id + "@1") != null, "%s has a rarer version" % id)
	var ms1 := RuneDef.DB.get_rune("rune_multishot_1")
	var ms2 := RuneDef.DB.get_rune("rune_multishot_2")
	check(ms1.extra_projectiles == 2 and is_equal_approx(ms1.more_damage, -0.35) and is_equal_approx(ms1.speed_bonus, -0.20), "Multishot I: +2 projectiles, 35% less damage, 20% less speed")
	check(ms2.extra_projectiles == 2 and is_equal_approx(ms2.more_damage, -0.25), "Multishot II: 25% less damage")
	check(RuneDef.DB.get_rune("rune_chain_1").extra_chains == 1 and is_equal_approx(RuneDef.DB.get_rune("rune_chain_1").more_damage, -0.30), "Chain I: +1 chain, 30% less damage")
	check(RuneDef.DB.get_rune("rune_chain_2").extra_chains == 2 and is_equal_approx(RuneDef.DB.get_rune("rune_chain_2").more_damage, -0.50), "Chain II: +2 chains, 50% less damage")
	check(ms1.stat_lines().contains("2 additional Projectiles") and ms1.stat_lines().contains("35% less Damage") and ms1.stat_lines().contains("Supports: projectile"),
		"the card says what it does and where it goes")

	# Skill tags
	var bow := SkillTree.get_skill("quick_shot").skill_tags()
	check(bow.has("projectile") and bow.has("attack") and bow.has("physical") and not bow.has("spell"), "Quick Shot: a physical projectile attack (%s)" % [bow])
	var arc := SkillTree.get_skill("arc").skill_tags()
	check(arc.has("chaining") and arc.has("spell") and arc.has("lightning"), "Arc: a lightning chaining spell (%s)" % [arc])
	check(not SkillTree.get_skill("thunderstorm").skill_tags().has("chaining"), "Thunderstorm does not chain")
	check(SkillTree.get_skill("cleave").skill_tags().has("melee") and SkillTree.get_skill("cleave").skill_tags().has("area"), "Cleave: a melee area attack")
	check(SkillTree.get_skill("firebolt").skill_tags().has("fire") and SkillTree.get_skill("firebolt").skill_tags(["rune_frost"]).has("cold"), "a conversion support changes the element")

	# Restrictions and families
	var qs := SkillTree.get_skill("quick_shot")
	var fb := SkillTree.get_skill("firebolt")
	var cl := SkillTree.get_skill("cleave")
	check(SkillDef.supports_valid(["rune_multishot_1"], qs), "Multishot goes on a projectile skill")
	check(not SkillDef.supports_valid(["rune_multishot_1"], cl), "but not on Cleave (%s)" % SkillDef.supports_block_reason(["rune_multishot_1"], cl))
	check(not SkillDef.supports_valid(["rune_multishot_1", "rune_multishot_2"], qs), "Multishot I and II do not go together (%s)" % SkillDef.supports_block_reason(["rune_multishot_1", "rune_multishot_2"], qs))
	check(not SkillDef.supports_valid(["rune_multishot_1", "rune_multishot_1@1"], qs), "nor does a rarer copy of the same one")
	check(SkillDef.supports_valid(["rune_multishot_1", "rune_chain_1"], SkillTree.get_skill("arc")) == false, "Arc is not a projectile skill: no Multishot there")
	check(SkillDef.supports_valid(["rune_chain_2"], SkillTree.get_skill("arc")) and not SkillDef.supports_valid(["rune_chain_1"], fb), "Chain needs a chaining skill")
	check(SkillDef.supports_valid(["rune_rapid_attacks_1"], cl) and not SkillDef.supports_valid(["rune_rapid_attacks_1"], fb), "Rapid Attacks: attacks only")
	check(SkillDef.supports_valid(["rune_rapid_casting_1"], fb) and not SkillDef.supports_valid(["rune_rapid_casting_1"], cl), "Rapid Casting: spells only")
	check(SkillDef.supports_valid(["rune_controlled_destruction"], fb) and not SkillDef.supports_valid(["rune_controlled_destruction"], cl), "Controlled Destruction: spells only")
	check(SkillDef.supports_valid(["rune_fire_mastery"], fb) and not SkillDef.supports_valid(["rune_fire_mastery"], SkillTree.get_skill("arc")), "Fire Mastery: Fire skills")
	check(SkillDef.supports_valid(["rune_fire", "rune_fire_mastery"], SkillTree.get_skill("arc")), "a Fire conversion makes Arc a Fire skill")
	check(not SkillDef.supports_valid(["rune_frost", "rune_fire_mastery"], fb), "and Cold conversion takes Firebolt out of Fire")
	check(SkillDef.supports_valid(["rune_life_leech_1"], cl) and not SkillDef.supports_valid(["rune_life_leech_1"], fb), "Life Leech: physical attacks")
	check(SkillDef.supports_valid(["rune_magnified_area_1", "rune_multishot_1"], qs) == false and SkillDef.supports_valid(["rune_magnified_area_1"], cl), "Magnified Area: area skills")
	check(SkillDef.supports_valid(["rune_multishot_1"]), "with no skill given there is no restriction")
	check(SkillDef.supports_valid(["rune_frost", "rune_fire"]) == false, "(the old one-conversion rule stands)")

	# Numbers
	var base_qs := qs.get_effective_damage_mult(1)
	var with_ms := _skill("quick_shot", ["rune_multishot_1"])
	check(is_equal_approx(with_ms.get_effective_damage_mult(1), base_qs * 0.65), "Multishot I: 35%% less damage (%.3f vs %.3f)" % [with_ms.get_effective_damage_mult(1), base_qs])
	check(with_ms.get_extra_projectiles() == 2 and is_equal_approx(with_ms.get_speed_mult(), 0.8), "+2 projectiles, 0.8x speed")
	check(is_equal_approx(_skill("cleave", ["rune_rapid_attacks_1"]).get_speed_mult(), 1.15), "Rapid Attacks I: 15% faster")
	var cd := _skill("firebolt", ["rune_controlled_destruction"])
	check(cd.cannot_crit() and is_equal_approx(cd.get_effective_damage_mult(1), fb.get_effective_damage_mult(1) * 1.25), "Controlled Destruction: 25% more damage, no crits")
	var ch := _skill("arc", ["rune_chain_2"])
	check(ch.get_extra_chains() == 2 and is_equal_approx(ch.get_effective_damage_mult(1), SkillTree.get_skill("arc").get_effective_damage_mult(1) * 0.5), "Chain II: +2 chains, 50% less damage")
	var fm := _skill("firebolt", ["rune_fire_mastery"])
	check(fm.get_level_bonus() == 1 and is_equal_approx(fm.get_effective_damage_mult(4), fb.get_effective_damage_mult(5)), "Fire Mastery: +1 level (rank 4 plays as rank 5)")
	check(_skill("cleave", ["rune_magnified_area_1"]).get_effective_radius() > cl.get_effective_radius() * 1.3, "Magnified Area: bigger")
	check(is_equal_approx(_skill("cleave", ["rune_life_leech_1"]).get_effective_leech(), 0.12), "Life Leech I: 12%")
	check(RuneDef.DB.get_rune("rune_rapid_attacks_1@2").speed_bonus > 0.15 and is_equal_approx(RuneDef.DB.get_rune("rune_multishot_1@2").more_damage, -0.35 * 1.0)
		or RuneDef.DB.get_rune("rune_multishot_1@2").more_damage > -0.35, "a rarer copy is stronger, a penalty is not scaled up")

	# Linking in a slot, with its restrictions
	GameState.level = 40
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	GameState.runes["rune_multishot_1"] = 2
	GameState.runes["rune_chain_1"] = 1
	GameState.skill_slots[0].supports = []
	GameState.skill_slots[1].supports = []
	GameState.grant_skill("quick_shot")
	GameState.grant_skill("cleave")
	GameState.set_slot_skill(0, "quick_shot")
	GameState.set_slot_skill(1, "cleave")
	check(GameState.socket_support(0, 0, "rune_multishot_1"), "Multishot links to Quick Shot")
	check(not GameState.socket_support(1, 0, "rune_multishot_1"), "and not to Cleave")
	check(not GameState.socket_support(0, 1, "rune_chain_1"), "nor Chain to Quick Shot")
	check(not GameState.move_support(0, 0, 1, 0), "a Multishot cannot be dragged onto Cleave")
	check(GameState.slot_supports(0) == ["rune_multishot_1"], "and it stays where it was")

	# A hireling cannot link what is the player's own
	check(SkillDef.supports_not_for_hirelings(["rune_multishot_1"]) and SkillDef.supports_not_for_hirelings(["rune_rapid_casting_1"])
		and not SkillDef.supports_not_for_hirelings(["rune_magnified_area_1"]) and not SkillDef.supports_not_for_hirelings(["rune_life_leech_1"]), "a hireling cannot have the player's casting supports")

	# In play: the shots
	var before := _arrows(main)
	p._cast(SkillTree.get_skill("quick_shot"))
	var plain := _arrows(main) - before
	check(plain == 1, "Quick Shot fires one arrow (%d)" % plain)
	before = _arrows(main)
	p._cast(_skill("quick_shot", ["rune_multishot_1"]))
	var multi := _arrows(main) - before
	check(multi == 3, "with Multishot I it fires three (%d)" % multi)
	before = _arrows(main)
	p._cast(_skill("multishot", ["rune_multishot_2"]))
	var five := _arrows(main) - before
	check(five == 7, "the five-arrow fan gets two more (%d)" % five)
	before = _arrows(main)
	p._cast(_skill("firebolt", ["rune_multishot_1"]))
	check(_arrows(main) - before == 3, "so does a bolt")

	# Chain: more strikes (the arrows above are cleared first, or they hit the dummies)
	for c in main.get_children():
		if c is HirelingArrow:
			c.queue_free()
	await get_tree().process_frame
	var dummies := []
	for k in 6:
		var d := Enemy.new()
		d.max_hp = 1.0e9
		d.speed = 0.0
		d.touch_damage = 0.0
		d.set_kind("zombie")
		main.add_child(d)
		d.global_position = p.global_position + Vector2(60 + 18 * k, 0)
		dummies.append(d)
	await get_tree().process_frame
	GameState.grant_skill("arc")
	p._cast(SkillTree.get_skill("arc"))
	await get_tree().create_timer(0.8).timeout
	var struck := dummies.filter(func(d): return d.hp < 1.0e9).size()
	check(struck == 3, "Arc strikes three enemies (%d)" % struck)
	for d in dummies:
		d.hp = 1.0e9
	p._cast(_skill("arc", ["rune_chain_2"]))
	await get_tree().create_timer(0.9).timeout
	struck = dummies.filter(func(d): return d.hp < 1.0e9).size()
	check(struck == 5, "with Chain II it strikes five (%d)" % struck)

	# No crits
	p.stats.add_mod("crit_chance", StatBlock.ModType.FLAT, 1.0, "test")
	var spell := _skill("firebolt", ["rune_controlled_destruction"])
	var crits := 0
	for k in 5:
		var e = dummies[0]
		e.hp = 1.0e9
		var d: float = p._hit_one(e, spell)
		var d2: float = p._hit_one(e, SkillTree.get_skill("firebolt"))
		crits += 1 if d2 > d * 1.5 else 0
	check(crits >= 3, "Controlled Destruction's hits never crit while the plain spell does (%d of 5 plain hits stronger)" % crits)
	p.stats.remove_source("test")

	print("poe2 supports: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
