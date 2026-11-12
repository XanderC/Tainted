extends Node2D
## Checks the last four PoE2 additions: accuracy (a share of hits miss, Accuracy Rating cuts it), Spirit (what meta supports
## reserve), "+N to Level of all ... Skills" (gem levels from gear) and the hybrid modifiers (two stats in one). Run headless:
##   godot --headless --path . res://scratch/test_features.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func make(id: String, rarity := ItemInstance.Rarity.RARE, ilvl := 80) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = ilvl
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()

	# --- which gear rolls what ---
	for pair in [["iron_helm", "accuracy"], ["linen_robe", "spirit"], ["old_amulet", "spirit"], ["old_amulet", "accuracy"], ["hunting_bow", "accuracy"],
			["hunting_bow", "lvl_projectile"], ["rusty_sword", "lvl_melee"], ["oak_staff", "lvl_fire"], ["oak_staff", "lvl_spell"], ["old_amulet", "lvl_projectile"],
			["linen_robe", "armour_pct_life"], ["linen_robe", "es_flat_pct"], ["iron_helm", "armour_pct_mana"], ["oak_staff", "spell_mana"], ["rusty_sword", "phys_acc"],
			["kite_shield", "armour_pct_stun"]]:
		check(AffixDB.families_for(make(pair[0]).base).has(pair[1]), "%s can roll %s" % [pair[0], pair[1]])
	check(not AffixDB.families_for(make("rusty_sword").base).has("lvl_projectile"), "a sword does not give projectile levels")
	check(not AffixDB.families_for(make("iron_helm").base).has("spirit"), "a helmet has no Spirit")

	# --- accuracy ---
	var base_miss := p.miss_chance()
	check(absf(base_miss - Player.MISS_BASE) < 0.001, "with no Accuracy Rating 12%% of hits miss (%.3f)" % base_miss)
	p.stats.add_mod("accuracy", StatBlock.ModType.FLAT, Player.ACCURACY_K, "test")
	check(absf(p.miss_chance() - Player.MISS_BASE * 0.5) < 0.001, "300 Accuracy Rating halves the misses")
	p.stats.remove_source("test")
	var dummy := Enemy.new()
	dummy.max_hp = 1.0e9
	dummy.speed = 0.0
	dummy.touch_damage = 0.0
	dummy.set_kind("zombie")
	main.add_child(dummy)
	dummy.global_position = p.global_position + Vector2(90, 0)
	await get_tree().process_frame
	var s0: SkillDef = p.skills[0]
	var landed := 0
	for i in 600:
		if p._hit_one(dummy, s0) > 0.0:
			landed += 1
	check(landed > 600 * 0.80 and landed < 600 * 0.95, "about 88%% of hits land (%d of 600)" % landed)
	p.stats.add_mod("accuracy", StatBlock.ModType.FLAT, 100000.0, "test")
	landed = 0
	for i in 600:
		if p._hit_one(dummy, s0) > 0.0:
			landed += 1
	p.stats.remove_source("test")
	check(landed > 590, "a lot of Accuracy Rating hits nearly always (%d of 600)" % landed)

	# --- skill levels from gear ---
	var cleave: SkillDef = SkillTree.get_skill("cleave")
	var lvl0 := cleave.get_effective_damage_mult(1)
	p.stats.add_mod("lvl_melee", StatBlock.ModType.FLAT, 3.0, "test")
	check(absf(cleave.get_effective_damage_mult(1) - lvl0 * 1.3 / 1.0) < 0.02 or cleave.get_effective_damage_mult(1) > lvl0 * 1.25, "+3 to Level of all Melee Skills: +30%% damage (%.2f vs %.2f)" % [cleave.get_effective_damage_mult(1), lvl0])
	var shot: SkillDef = SkillTree.get_skill("quick_shot")
	var shot0 := shot.get_effective_damage_mult(1)
	check(absf(shot.get_effective_damage_mult(1) - shot0) < 0.001, "melee levels do not touch a bow skill")
	p.stats.remove_source("test")
	p.stats.add_mod("lvl_projectile", StatBlock.ModType.FLAT, 2.0, "test")
	check(shot.get_effective_damage_mult(1) > shot0 * 1.15, "projectile levels do (%.2f vs %.2f)" % [shot.get_effective_damage_mult(1), shot0])
	p.stats.remove_source("test")
	check(absf(cleave.get_effective_damage_mult(1) - lvl0) < 0.001, "and it ends when the item comes off")

	# --- hybrid modifiers ---
	var robe := make("linen_robe")
	var seen := 0
	for i in 400:
		var r := make("linen_robe")
		LootGenerator.roll_affixes(r, 6)
		for e in r.affixes:
			if AffixDB.is_hybrid(String(e.family)):
				seen += 1
				if not (e.has("stat2") and float(e.value2) > 0.0 and String(e.text).contains("\n")):
					check(false, "a hybrid carries both stats and two lines (%s)" % e.family)
	check(seen > 20, "hybrids drop (%d in 400 robes)" % seen)
	var hyb := LootGenerator.make_family_entry(robe.base, "armour_pct_life", 2, 0.2, 40.0)
	check(hyb.stat == "armor" and hyb.stat2 == "max_life" and hyb.text == "20% increased Armour\n+40 to maximum Life", "text: %s" % str(hyb.text).replace("\n", " / "))
	robe.affixes = [hyb]
	var life0 := p.stats.get_stat("max_life")
	var arm0 := p.stats.get_stat("armor")
	robe.apply_to(p.stats)
	check(absf(p.stats.get_stat("max_life") - life0 - 40.0) < 0.01, "worn: +40 life")
	check(p.stats.get_stat("armor") >= arm0, "and the armour")
	robe.remove_from(p.stats)
	check(absf(p.stats.get_stat("max_life") - life0) < 0.01, "both come off")
	var back := ItemInstance.from_dict(robe.to_dict())
	check(back.affixes.size() == 1 and back.affixes[0].family == "armour_pct_life" and absf(float(back.affixes[0].value2) - 40.0) < 0.01 and back.affixes[0].text == hyb.text,
		"a hybrid saves and loads with both values")
	LootGenerator.reroll_values(robe)
	check(robe.affixes[0].tier == 2 and robe.affixes[0].has("value2"), "a Divine keeps its tier and rerolls both")
	var tiers_ok := true
	for i in 200:
		var r := make("linen_robe", ItemInstance.Rarity.RARE, 30)
		LootGenerator.roll_affixes(r, 6)
		for e in r.affixes:
			var t: Array = AffixDB.tiers_for(r.base, String(e.family))[int(e.tier)]
			if int(t[0]) > 30:
				tiers_ok = false
	check(tiers_ok, "hybrid tiers need their item level too")

	# --- spirit ---
	GameState.level = 40
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	p.refresh_attributes()
	GameState.grant_skill("iron_skin")
	GameState.runes["rune_cast_crit"] = 2
	GameState.runes["rune_cast_hurt"] = 2
	for i in 2:
		GameState.skill_slots[i].supports = []
	GameState.set_slot_skill(0, "cleave")
	GameState.set_slot_skill(1, "frenzy")
	check(GameState.socket_support(0, 0, "rune_cast_crit") and GameState.socket_support(1, 0, "rune_cast_hurt"), "two metas linked")
	check(GameState.set_slot_trigger(0, "iron_skin") and GameState.set_slot_trigger(1, "iron_skin"), "both have a skill chosen")
	check(GameState.spirit_total() == 100 and GameState.spirit_wanted() == 200, "you have 100 Spirit and they ask for 200")
	check(GameState.meta_has_spirit(0) and not GameState.meta_has_spirit(1), "the first is covered, the second is not")
	var amulet := make("old_amulet")
	amulet.affixes = [LootGenerator.make_family_entry(amulet.base, "spirit", 2, 100.0)]
	p.bag.add(amulet)
	p.equip_to(amulet, "amulet", true)
	check(GameState.spirit_total() == 200 and GameState.meta_has_spirit(1), "+100 to Spirit on gear covers it")
	p.unequip("amulet")
	check(not GameState.meta_has_spirit(1), "and not once it is off")

	print("features: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
