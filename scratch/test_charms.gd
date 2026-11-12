extends Node2D
## Checks charms (Path of Exile 2): slots opened by the belt's item level, use by trigger (a hit of an element, a
## slow, an elite's death), charges, durations, modifiers (prefix and suffix limits), the belt's charm and flask
## modifiers, saving, and the old utility flasks becoming charms. Run headless:
##   godot --headless --path . res://scratch/test_charms.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func item(id: String, rarity := ItemInstance.Rarity.NORMAL, ilvl := 60) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = ilvl
	it.display_name = it.base.display_name
	it.refill()
	return it


func step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		p._process_flasks(0.05)
		t += 0.05


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	p.charms = [null, null, null]

	# --- bases ---
	var charms := LootGenerator.bases.filter(func(b): return b.slot == "charm")
	check(charms.size() == 13, "all thirteen of PoE2's charms (%d)" % charms.size())
	check(item("ruby_charm").grid_size() == Vector2i(1, 1), "a charm takes one cell")
	check(LootGenerator.base_by_id("golden_charm").drop_level == 50 and int(LootGenerator.base_by_id("golden_charm").charm.max_charges) == 80, "Golden: level 50, 80 charges")
	check(ItemInstance.roll_sockets(item("ruby_charm").base, ItemInstance.Rarity.MAGIC) == 0, "no sockets")

	# --- slots come from the belt's item level ---
	check(p.charm_slot_count() == 0, "no belt, no charm slots")
	var belt := item("rope_belt", ItemInstance.Rarity.NORMAL, 10)
	p.bag.add(belt)
	p.equip_to(belt, "belt", true)
	check(p.charm_slot_count() == 1, "a belt below level 30: 1 slot")
	belt.ilvl = 40
	check(p.charm_slot_count() == 2, "below 60: 2")
	belt.ilvl = 60
	check(p.charm_slot_count() == 3, "60 and up: 3")
	belt.ilvl = 10
	var ruby := item("ruby_charm")
	var silver := item("silver_charm")
	p.bag.add(ruby)
	p.bag.add(silver)
	check(p.equip_charm(ruby, 0) and p.charms[0] == ruby and not p.bag.has(ruby), "wear a charm in slot 1")
	check(not p.equip_charm(silver, 1), "slot 2 is closed by a low belt")
	belt.ilvl = 60
	check(p.equip_charm(silver, 1), "and open with a better one")
	check(not p.equip_charm(item("small_life_flask"), 2), "a flask is no charm")

	# --- a fire hit uses the Ruby Charm ---
	var fire0 := p.resistance(RuneDef.DamageType.FIRE)
	check(ruby.charges_now() == 40.0, "full: 40 charges")
	p.take_damage(10.0, RuneDef.DamageType.COLD)
	check(ruby.charges_now() == 40.0 and absf(p.resistance(RuneDef.DamageType.FIRE) - fire0) < 0.001, "a cold hit does not use it")
	p.take_damage(10.0, RuneDef.DamageType.FIRE)
	check(ruby.charges_now() == 20.0, "a fire hit used it: 20 charges (%.0f)" % ruby.charges_now())
	check(absf(p.resistance(RuneDef.DamageType.FIRE) - (fire0 + 0.25)) < 0.001, "+25%% fire resistance (%.2f)" % p.resistance(RuneDef.DamageType.FIRE))
	check(p.charm_flash(0) > 0.9, "the bar flashes")
	p.take_damage(10.0, RuneDef.DamageType.FIRE)
	check(ruby.charges_now() == 20.0, "not again while it is in effect")
	step(p, 4.2)
	check(absf(p.resistance(RuneDef.DamageType.FIRE) - fire0) < 0.001, "gone after 4 seconds")
	p.take_damage(10.0, RuneDef.DamageType.FIRE)
	check(ruby.charges_now() == 0.0, "used again: 0 charges")
	step(p, 4.2)
	p.take_damage(10.0, RuneDef.DamageType.FIRE)
	check(absf(p.resistance(RuneDef.DamageType.FIRE) - fire0) < 0.001, "no charges, no effect")
	p.on_enemy_killed(Vector2.ZERO)
	p.on_enemy_killed(Vector2.ZERO)
	check(absf(ruby.charges_now() - 2.0) < 0.01, "kills give charges to charms too (%.1f)" % ruby.charges_now())
	p.refill_flasks()
	check(ruby.charges_now() == 40.0, "the town and waypoints refill them")

	# --- silver: a slow is ignored ---
	p.apply_slow(3.0)
	check(p._slow_t == 0.0 and silver.charges_now() == 20.0, "a Silver Charm stops a slow (charges %.0f)" % silver.charges_now())
	p.apply_slow(3.0)
	check(p._slow_t == 0.0, "and a second one while it lasts")
	step(p, 3.2)

	# --- golden: elite kills raise the rarity of drops ---
	var golden := item("golden_charm")
	p.bag.add(golden)
	check(p.equip_charm(golden, 2), "wear a Golden Charm")
	check(LootGenerator.rarity_bonus() == 0.0, "no bonus yet")
	p.on_enemy_killed(Vector2.ZERO, 1.0)
	check(golden.charges_now() == 80.0, "a normal kill does not use it")
	p.on_enemy_killed(Vector2.ZERO, 3.0)
	check(absf(LootGenerator.rarity_bonus() - 0.15) < 0.001, "an elite kill: 15%% more rarity (%.2f)" % LootGenerator.rarity_bonus())
	step(p, 3.2)
	check(LootGenerator.rarity_bonus() == 0.0, "it ends")

	# --- modifiers ---
	var rolled_bad := false
	var over := false
	var rare_seen := false
	for k in 300:
		var c := LootGenerator.roll_item(70, ItemInstance.Rarity.RARE if k % 2 else ItemInstance.Rarity.MAGIC, "charm")
		if c.rarity > ItemInstance.Rarity.MAGIC:
			rare_seen = true
		var pre := 0
		var suf := 0
		for a in c.affixes:
			if not AffixDB.families_for(c.base).has(a.family):
				rolled_bad = true
			if AffixDB.is_prefix(a.family):
				pre += 1
			else:
				suf += 1
		if pre > 1 or suf > 1:
			over = true
	check(not rolled_bad and not over and not rare_seen, "charms roll charm modifiers, 1 + 1, never Rare")
	var life_charm := item("ruby_charm", ItemInstance.Rarity.MAGIC)
	life_charm.affixes = [LootGenerator.make_family_entry(life_charm.base, "charm_life", 3, 100.0), LootGenerator.make_family_entry(life_charm.base, "charm_duration", 0, 0.5)]
	check(absf(float(life_charm.flask_effect().duration) - 6.0) < 0.001 and float(life_charm.flask_effect().charm_life) == 100.0, "50%% longer (6s), recovers 100 life")
	p.charms[0] = life_charm
	p.hp = 5.0
	p.take_damage(0.0, RuneDef.DamageType.FIRE)
	check(p.hp >= 104.0, "it recovered life when used (hp %.0f)" % p.hp)
	p.charms[0] = ruby
	check(Crafting.orb_block_reason(item("ruby_charm", ItemInstance.Rarity.MAGIC), "regal") != "", "a charm cannot be made Rare")

	# --- the belt's modifiers ---
	var tuned := item("rope_belt", ItemInstance.Rarity.MAGIC, 60)
	tuned.affixes = [LootGenerator.make_family_entry(tuned.base, "belt_charm_used", 0, 0.5), LootGenerator.make_family_entry(tuned.base, "belt_charm_duration", 0, 0.5)]
	var e := ruby.flask_effect(tuned)
	check(int(e.per_use) == 10 and absf(float(e.duration) - 6.0) < 0.001, "the belt: 50%% reduced charm charges used (10), 50%% longer (6s)")
	var fl := item("small_life_flask")
	var tb := item("rope_belt", ItemInstance.Rarity.MAGIC, 60)
	tb.affixes = [LootGenerator.make_family_entry(tb.base, "belt_flask_gained", 0, 0.5), LootGenerator.make_family_entry(tb.base, "belt_flask_used", 0, 0.3)]
	check(int(fl.flask_effect(tb).per_use) == 7 and absf(float(fl.flask_effect(tb).gain_mult) - 1.5) < 0.001, "the belt's flask modifiers: 7 per use, 50%% more gained")
	var belt_pool := AffixDB.families_for(item("rope_belt").base)
	check(belt_pool.has("belt_charm_used") and belt_pool.has("belt_flask_gained") and belt_pool.has("life"), "belts roll the charm and flask modifiers")
	check(not AffixDB.families_for(item("iron_helm").base).has("belt_charm_used"), "helmets do not")

	# --- saving, and the old utility flasks ---
	var back := ItemInstance.from_dict(golden.to_dict())
	check(back.is_charm() and back.base.id == "golden_charm", "a charm round-trips")
	var old := ItemInstance.from_dict({"base": "quicksilver_flask", "rarity": 2, "ilvl": 20, "affixes": [{"id": "fl_haste", "value": 0.1}]})
	check(old != null and old.is_charm() and old.base.id == "silver_charm" and old.rarity <= ItemInstance.Rarity.MAGIC, "a Quicksilver Flask became a Silver Charm")
	check(ItemInstance.from_dict({"base": "granite_flask"}).base.id == "ruby_charm", "a Granite Flask a Ruby Charm")
	GameState._pending_charms = [ItemInstance.from_dict({"base": "topaz_charm"}).to_dict(), null, null]
	GameState._pending_flasks = [ItemInstance.from_dict({"base": "small_life_flask"}).to_dict(), ItemInstance.from_dict({"base": "small_power_flask"}).to_dict(),
		{"base": "silver_flask"}]
	GameState._pending_loose_flasks.clear()
	var town2 = load("res://scenes/town.tscn").instantiate()
	add_child(town2)
	await get_tree().process_frame
	await get_tree().process_frame
	var p2: Player = town2.player
	check(p2.charms[0] != null and p2.charms[0].base.id == "topaz_charm", "the saved charm is back in its slot")
	check(p2.charms[1] != null and p2.charms[1].base.id == "sapphire_charm", "the old Silver Flask is a Sapphire Charm in a free slot")

	print("charms: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
