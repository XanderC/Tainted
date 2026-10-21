extends Node2D
## Checks hirelings: types opening with the story, hiring (one at a time, paid in orbs), its stats
## growing with its level and gear, gear rules and requirements, its skill gems and the supports
## you link, sharing experience (never past your level), fighting beside you (enemies go for the
## nearer of you), falling and being revived, a new hire handing back the old one's gear and
## supports, and saving. Run headless:
##   godot --headless --path . res://scratch/test_hirelings.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func item(base_id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(base_id)
	it.ilvl = 1
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	GameState.quests = {}
	GameState.level = 10
	GameState.xp = 0.0
	GameState.orbs["transmute"] = 50
	GameState.orbs["alteration"] = 50
	GameState.runes = {"rune_fire": 2, "rune_frost": 1, "rune_vampiric": 1, "rune_echo": 1}
	Hirelings.dismiss(p)

	# Types open with the story
	check(HirelingDB.unlocked("sellsword"), "Sellswords are there from the start")
	check(not HirelingDB.unlocked("scout"), "Desert Scouts wait for Into the Wastes")
	GameState.quests["a1_into_the_wastes"] = {"state": Quests.DONE}
	check(HirelingDB.unlocked("scout"), "and open once it is done")

	# Candidates
	var offers := Hirelings.candidates("sellsword")
	check(offers.size() == HirelingDB.CANDIDATES, "three Sellswords on offer")
	var c: Dictionary = offers[0]
	check(int(c.level) <= GameState.level and int(c.level) >= GameState.level - 2, "near your level, never above (%d)" % int(c.level))
	check((c.skills as Array).size() == 1 + HirelingDB.SKILL_COUNT, "a main attack and %d skills (%s)" % [HirelingDB.SKILL_COUNT, c.skills])
	check(String(c.skills[0]) in HirelingDB.TYPES.sellsword.attacks, "its main attack is a Sellsword attack")
	check(c.has("look") and not c.has("skin"), "a Sellsword is dressed in its own gear")
	var scout: Dictionary = Hirelings.candidates("scout")[0]
	check(scout.has("skin") and String(scout.skills[0]) == "hl_shot", "a Scout is an archer who shoots")
	check(SkillTree.active_skills().all(func(s): return not s.hireling_only), "archer skills are never player gems")

	# Hiring
	var price := HirelingDB.hire_price(int(c.level))
	var before := GameState.orb_count(String(price.keys()[0]))
	check(Hirelings.hire(p, c), "hire a Sellsword")
	check(GameState.orb_count(String(price.keys()[0])) == before - int(price.values()[0]), "paid %s" % [price])
	check(Hirelings.alive() and Hirelings.type_id() == "sellsword", "you have a living Sellsword")
	check(not Hirelings.candidates("sellsword").has(c), "and it is no longer on offer")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var h: Hireling = Hirelings.node
	check(is_instance_valid(h) and h.is_inside_tree(), "it stands in the world beside you")
	check(h.global_position.distance_to(p.global_position) < 200.0, "close to you (%.0f)" % h.global_position.distance_to(p.global_position))
	check(h.skills.size() == 3, "with its three skills")

	# Stats grow with level
	var base := HirelingDB.stats_at("sellsword", int(c.level))
	check(absf(h.stats.get_stat("max_life") - float(base.max_life)) < 0.01, "its life is its type's at its level")
	check(HirelingDB.stats_at("sellsword", 20).max_life > HirelingDB.stats_at("sellsword", 5).max_life, "and grows with level")

	# Gear: its rules and requirements
	var shield := item("wooden_shield")
	var maul := item("war_maul")
	var bow := item("hunting_bow")
	var mail := item("chain_mail")
	var helm := item("iron_helm")
	for it in [shield, maul, bow, mail, helm]:
		p.bag.add(it)
	check(Hirelings.slot_block_reason(maul, "weapon").contains("one-handed"), "a Sellsword won't take a two-hander")
	check(Hirelings.slot_block_reason(bow, "weapon") != "", "nor a bow")
	check(Hirelings.slot_block_reason(helm, "chest") != "", "a helmet doesn't go on its chest")
	var armor0 := h.stats.get_stat("armor")
	check(Hirelings.equip_from_bag(p, shield, "offhand"), "give it a shield")
	check(Hirelings.equip_from_bag(p, mail, "chest"), "and chain mail")
	check(not p.bag.has(shield) and GameState.hireling_gear.get("offhand") == shield, "the shield left your bag for its hand")
	check(h.stats.get_stat("armor") > armor0, "its armour went up (%.0f -> %.0f)" % [armor0, h.stats.get_stat("armor")])
	var strong := item("gilded_aegis")  # needs far more Strength than a level ~10 Sellsword has
	p.bag.add(strong)
	check(Hirelings.slot_block_reason(strong, "offhand").begins_with("Requires"), "its requirements are judged by its own attributes (%s)" % Hirelings.slot_block_reason(strong, "offhand"))
	var at := p.bag.find_free(mail)
	check(Hirelings.unequip_to(p, "chest", at), "take the chain mail back")
	check(p.bag.has(mail) and not GameState.hireling_gear.has("chest"), "it is in your bag again")

	# Supports: from the shared pool, only as many as its links
	check(Hirelings.links() == HirelingDB.links_at(Hirelings.level()), "its links follow its level")
	check(Hirelings.socket_support(0, 0, "rune_fire"), "link a Fire support to its attack")
	check(GameState.rune_count("rune_fire") == 1, "taken from the shared pool")
	check(h.skills[0].get_effective_damage_type() == RuneDef.DamageType.FIRE, "its attack now burns")
	check(not Hirelings.socket_support(0, 1, "rune_frost"), "one elemental support per skill")
	check(Hirelings.unsocket_support(0, 0) and GameState.rune_count("rune_fire") == 2, "unlink it back to the pool")
	check(not Hirelings.socket_support(0, Hirelings.links(), "rune_echo"), "no supports past its open links")

	# Experience: shared, never past your level
	GameState.hireling["level"] = 9
	GameState.hireling["xp"] = 0.0
	Hirelings.add_xp(GameState.xp_to_next(9) * 5.0)
	check(Hirelings.level() == GameState.level, "it levels up to your level (%d)" % Hirelings.level())
	Hirelings.add_xp(GameState.xp_to_next(10) * 5.0)
	check(Hirelings.level() == GameState.level, "but not past it (%d)" % Hirelings.level())

	# Fighting: it goes for enemies near you, and they go for the nearer of you
	p.can_fight = true
	var e := Enemy.new()
	e.target = p
	e.max_hp = 30000.0
	e.touch_damage = 0.0
	e.position = h.global_position + Vector2(260, 0)
	town.add_child(e)
	p.global_position = e.position + Vector2(400, 0)  # within its leash of you
	h.global_position = e.position + Vector2(-80, 0)
	var hp0 := e.hp
	for i in 90:
		await get_tree().physics_frame
	check(e.hp < hp0, "it attacked the enemy (%.0f -> %.0f)" % [hp0, e.hp])
	check(e._foe == h, "the enemy went for the nearer hireling")
	h.global_position = p.global_position + Vector2(700, 0)  # well behind you
	check(e._pick_foe() == p, "and for you when you are nearer")
	e.queue_free()

	# Its own flasks: it drinks them itself
	h = Hirelings.node
	var power := item("small_power_flask")
	var life_f := item("small_life_flask")
	var granite := item("granite_flask")
	for it in [power, life_f, granite]:
		p.bag.add(it)
	check(Hirelings.flask_block_reason(power) != "", "no power flasks: it has no Adrenaline")
	check(not Hirelings.equip_flask_from_bag(p, power, 0), "so one won't go in its slot")
	check(Hirelings.equip_flask_from_bag(p, life_f, 0), "a life flask goes in its first slot")
	check(Hirelings.equip_flask_from_bag(p, granite, 1), "a Granite Flask in its second")
	check(not p.bag.has(life_f) and not p.bag.has(granite), "both left your bag")
	var max_life := h.stats.get_stat("max_life")
	h.hp = max_life * 0.8
	await get_tree().physics_frame
	check(h.flask_cooldown_fraction(0) == 0.0, "it doesn't drink while above half life")
	h.hp = max_life * 0.3
	await get_tree().physics_frame
	check(h.flask_cooldown_fraction(0) > 0.0, "below half it drinks its life flask")
	for i in 120:
		await get_tree().physics_frame
	check(h.hp > max_life * 0.4, "and heals (%.0f of %.0f)" % [h.hp, max_life])
	var e2 := Enemy.new()
	e2.target = p
	e2.max_hp = 30000.0
	e2.touch_damage = 0.0
	e2.position = h.global_position + Vector2(120, 0)
	p.global_position = e2.position + Vector2(200, 0)
	town.add_child(e2)
	var armor_before := h.stats.get_stat("armor")
	for i in 5:
		await get_tree().physics_frame
	check(h.flask_cooldown_fraction(1) > 0.0, "fighting, it drinks its utility flask")
	check(h.stats.get_stat("armor") > armor_before, "and gets its armour (%.0f -> %.0f)" % [armor_before, h.stats.get_stat("armor")])
	e2.queue_free()
	# Your own flasks are yours alone
	p.flasks[0] = item("small_life_flask")
	h.hp = max_life * 0.2
	var hp_before := h.hp
	p.use_flask(0)
	check(absf(h.hp - hp_before) < max_life * 0.05, "your life flask doesn't heal it")
	var saved_f := GameState._hireling_save()
	check((saved_f.flasks as Array)[0] != null and (saved_f.flasks as Array)[1] != null, "its flasks are saved")

	# Falling, then revived
	h = Hirelings.node
	h.take_damage(1.0e9)
	check(h.dead and not Hirelings.alive() and Hirelings.has(), "it falls, and stays yours")
	var rp := Hirelings.revive_price()
	check(Hirelings.revive(p), "revive it for %s" % [rp])
	await get_tree().physics_frame
	check(Hirelings.alive() and is_instance_valid(Hirelings.node), "it stands again")

	# Saving
	var saved := GameState._hireling_save()
	check(saved.has("gear") and (saved.gear as Dictionary).has("offhand"), "its gear is saved")
	var lvl := Hirelings.level()
	GameState._load_hireling(saved)
	check(Hirelings.level() == lvl and GameState.hireling_gear.get("offhand") != null, "and loads back")

	# A new hire: the old one's gear and supports come back
	Hirelings.socket_support(1, 0, "rune_vampiric")
	var shield_now: ItemInstance = GameState.hireling_gear.get("offhand")
	life_f = Hirelings.flask(0)  # loading made new items of them
	var other: Dictionary = Hirelings.candidates("scout")[0]
	check(Hirelings.hire(p, other), "hire a Scout instead")
	check(Hirelings.type_id() == "scout", "only one hireling: now the Scout")
	check(p.bag.has(shield_now) or GameState.stash.has(shield_now), "the Sellsword's shield came back")
	check(p.bag.has(life_f) or GameState.stash.has(life_f), "and its flasks")
	check(Hirelings.flask(0) == null and Hirelings.flask(1) == null, "the new one starts without flasks")
	check(GameState.rune_count("rune_vampiric") == 1, "and its support went back to the pool")

	print("test_hirelings: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
