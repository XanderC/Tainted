extends Node2D
## Checks flasks the Path of Exile 2 way: two slots (life, then mana), charges spent per drink and refilled by
## kills, seconds, waypoints and the town, the nine tiers, flask modifiers (prefix and suffix limits, Normal or
## Magic only), recovery over time and instantly, equipping, saving and converting saves of the five-slot build.
## Run headless:   godot --headless --path . res://scratch/test_flasks.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func item(id: String, rarity := ItemInstance.Rarity.NORMAL) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = 60
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
	p.flasks = [null, null]

	# --- bases: nine tiers of each kind, PoE2's levels, durations and charges ---
	check(Player.FLASK_SLOTS == 2 and p.flask_slot_count() == 2, "two flask slots")
	check(item("small_life_flask").grid_size() == Vector2i(1, 2), "flask 1x2")
	var lifes := LootGenerator.bases.filter(func(b): return b.slot == "flask" and b.flask.kind == "life")
	var manas := LootGenerator.bases.filter(func(b): return b.slot == "flask" and b.flask.kind == "power")
	check(lifes.size() == 9 and manas.size() == 9, "nine life and nine mana flasks (%d, %d)" % [lifes.size(), manas.size()])
	var big := LootGenerator.base_by_id("ultimate_life_flask")
	check(big.drop_level == 60 and int(big.flask.max_charges) == 75 and int(big.flask.charges_per_use) == 10, "Ultimate: level 60, 75 charges, 10 per use")
	check(int(LootGenerator.base_by_id("small_life_flask").flask.max_charges) == 60 and LootGenerator.base_by_id("small_life_flask").drop_level == 1,
		"Lesser: level 1, 60 charges")
	var low_only := true
	for n in 60:
		low_only = low_only and LootGenerator.roll_item(1, ItemInstance.Rarity.NORMAL, "flask").base.drop_level <= 3
	check(low_only, "a level 1 drop is only a low tier")
	check(LootGenerator.base_by_id("granite_flask").weight == 0, "the old utility flasks no longer drop")

	# --- slot kinds ---
	var l1 := item("small_life_flask")
	var m1 := item("small_power_flask")
	p.bag.add(l1)
	p.bag.add(m1)
	check(not p.equip_flask(m1, 0) and not p.equip_flask(l1, 1), "a mana flask does not go in the life slot, nor a life flask in the mana slot")
	check(p.equip_flask(l1, 0) and p.equip_flask(m1, 1) and p.flasks[0] == l1 and p.flasks[1] == m1, "life in slot 1, mana in slot 2")
	check(not p.equip_flask(item("iron_helm"), 0), "a helmet is no flask")

	# --- drinking spends charges and recovers over the duration ---
	var max_life := p.stats.get_stat("max_life")
	p.hp = 1.0
	check(l1.charges_now() == 60.0, "a new flask is full (%.0f)" % l1.charges_now())
	check(p.use_flask(0), "drink the life flask")
	check(not p.use_flask(0), "not again at once: a short wait")
	check(l1.charges_now() == 50.0, "it spent 10 charges (%.0f)" % l1.charges_now())
	check(p.hp < 2.0, "not instant: nothing yet")
	step(p, 3.2)
	check(absf(p.hp - (1.0 + max_life * 0.30)) < 2.0, "30%% of max life over 3s (hp %.1f of %.1f)" % [p.hp, max_life])
	for k in 5:
		step(p, 0.6)
		p.use_flask(0)
	check(l1.charges_now() == 0.0 and not p.flask_ready(0), "six drinks empty a 60 charge flask (%.0f)" % l1.charges_now())
	step(p, 0.6)
	check(not p.use_flask(0), "an empty flask cannot be drunk")

	# --- kills, seconds, waypoints and the town refill it ---
	p.on_enemy_killed(Vector2.ZERO)
	check(absf(l1.charges_now() - 1.0) < 0.01, "a normal kill gives 1 charge (%.1f)" % l1.charges_now())
	p.on_enemy_killed(Vector2.ZERO, 3.0)
	p.on_enemy_killed(Vector2.ZERO, 10.0)
	check(absf(l1.charges_now() - 14.0) < 0.01 and p.flask_ready(0), "an elite 3, a boss 10: enough for a drink (%.1f)" % l1.charges_now())
	check(absf(p.flask_charge_fraction(0) - 14.0 / 60.0) < 0.001, "the fill is 14 of 60")
	p.refill_flasks()
	check(l1.charges_now() == 60.0 and m1.charges_now() == float(m1.max_charges()), "refilling fills both")
	l1.charges = 0.0
	var per_sec := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	per_sec.affixes = [LootGenerator.make_family_entry(per_sec.base, "flask_per_second", 1, 0.2)]
	p.flasks[0] = per_sec
	per_sec.charges = 0.0
	step(p, 10.0)
	check(absf(per_sec.charges_now() - 2.0) < 0.2, "0.2 charges per second is 2 in ten seconds (%.2f)" % per_sec.charges_now())
	p.flasks[0] = l1

	# --- flask modifiers ---
	var bad_pool := false
	var over := false
	var rare_seen := false
	for k in 300:
		var f := LootGenerator.roll_item(60, ItemInstance.Rarity.RARE if k % 2 else ItemInstance.Rarity.MAGIC, "flask")
		if f.rarity > ItemInstance.Rarity.MAGIC:
			rare_seen = true
		var pre := 0
		var suf := 0
		for a in f.affixes:
			if not String(a.family).begins_with("flask_"):
				bad_pool = true
			if AffixDB.is_prefix(a.family):
				pre += 1
			else:
				suf += 1
		if pre > 1 or suf > 1:
			over = true
	check(not bad_pool, "flasks only roll flask modifiers")
	check(not over and not rare_seen, "at most 1 prefix + 1 suffix, and never Rare")
	var gear_bad := false
	for k in 100:
		var g := LootGenerator.roll_item(40, ItemInstance.Rarity.RARE, "chest")
		if g.affixes.any(func(a): return String(a.stat).begins_with("flask_")):
			gear_bad = true
	check(not gear_bad, "gear never rolls flask modifiers")

	var tuned := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	tuned.affixes = [LootGenerator.make_family_entry(tuned.base, "flask_amount", 0, 0.5), LootGenerator.make_family_entry(tuned.base, "flask_charges", 0, 0.5)]
	var e := tuned.flask_effect()
	check(absf(float(e.amount) - 0.45) < 0.001 and int(e.max_charges) == 90, "50%% more amount and charges (%.2f, %d)" % [e.amount, e.max_charges])
	var thrifty := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	thrifty.affixes = [LootGenerator.make_family_entry(thrifty.base, "flask_used", 0, 0.3), LootGenerator.make_family_entry(thrifty.base, "flask_gained", 0, 0.5)]
	check(int(thrifty.flask_effect().per_use) == 7 and absf(float(thrifty.flask_effect().gain_mult) - 1.5) < 0.001, "30%% reduced charges per use (7), 50%% more gained")
	thrifty.charges = 0.0
	p.flasks[0] = thrifty
	p.on_enemy_killed(Vector2.ZERO)
	check(absf(thrifty.charges_now() - 1.5) < 0.01, "charges gained are multiplied (%.2f)" % thrifty.charges_now())
	p.flasks[0] = l1
	var quick := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	quick.affixes = [LootGenerator.make_family_entry(quick.base, "flask_speed", 0, 0.5)]
	check(absf(float(quick.flask_effect().duration) - 2.0) < 0.001, "50%% increased recovery rate: 3s becomes 2s")

	# --- instant part ---
	var inst := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	inst.affixes = [LootGenerator.make_family_entry(inst.base, "flask_instant_part", 0, 0.25)]
	p.flasks[0] = inst
	p.hp = 1.0
	check(p.use_flask(0), "drink the flask with an instant part")
	check(absf(p.hp - (1.0 + max_life * 0.30 * 0.25)) < 1.0, "a quarter at once (hp %.1f)" % p.hp)
	step(p, 3.2)
	check(absf(p.hp - (1.0 + max_life * 0.30)) < 2.0, "the rest over time (hp %.1f)" % p.hp)
	p.flasks[0] = l1
	p.refill_flasks()

	# --- mana ---
	p.mana = 0.0
	check(p.use_flask(1), "drink the mana flask")
	step(p, 3.5)
	check(p.mana > 20.0, "it restored mana (%.1f)" % p.mana)

	# --- unequipping and the bag ---
	p.bag.clear()
	var spare := item("medium_life_flask")
	p.bag.place(spare, Vector2i(3, 1))
	var was: ItemInstance = p.flasks[0]
	check(p.equip_flask(spare, 0) and p.flasks[0] == spare and p.bag.has(was) and p.bag.position_of(was) == Vector2i(3, 1), "equip from the bag; the old flask takes its place")
	check(p.can_unequip_flask_to(0, Vector2i(0, 0)) and p.unequip_flask_to(0, Vector2i(0, 0)) and p.flasks[0] == null, "unequipped into the bag")
	var found := item("large_life_flask")
	check(p.pick_up(found) and p.bag.has(found) and p.flasks[0] == null, "a picked-up flask goes into the bag")

	# --- saving keeps charges and modifiers ---
	var magic := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	magic.affixes = [LootGenerator.make_family_entry(magic.base, "flask_charges", 1, 0.4)]
	magic.charges = 33.0
	var back := ItemInstance.from_dict(magic.to_dict())
	check(back.is_flask() and back.charges == 33.0 and int(back.flask_effect().max_charges) == 84, "a saved flask keeps its charges and modifiers (%.0f / %d)" % [back.charges, back.flask_effect().max_charges])

	# --- saves of the five-slot build ---
	var old_rare := {"base": "medium_life_flask", "rarity": 2, "ilvl": 20, "name": "Grim Medium Life Flask of Woe", "sockets": 0, "gems": [],
		"affixes": [{"id": "fl_ample", "value": 0.2}, {"id": "fl_chemist", "value": 0.2}, {"id": "fl_enduring", "value": 0.3},
			{"id": "fl_haste", "value": 0.1}, {"id": "fl_fury", "value": 0.1}]}
	var conv := ItemInstance.from_dict(old_rare)
	var pre2 := conv.affixes.filter(func(a): return AffixDB.is_prefix(a.family)).size()
	var suf2 := conv.affixes.filter(func(a): return not AffixDB.is_prefix(a.family)).size()
	check(conv.rarity == ItemInstance.Rarity.MAGIC and pre2 <= 1 and suf2 <= 1 and conv.affixes.size() >= 1, "a Rare flask becomes Magic with 1 + 1 (%d + %d)" % [pre2, suf2])
	GameState._pending_flasks = [ItemInstance.from_dict({"base": "large_life_flask"}).to_dict(), ItemInstance.from_dict({"base": "small_life_flask"}).to_dict(),
		ItemInstance.from_dict({"base": "medium_power_flask"}).to_dict(), ItemInstance.from_dict({"base": "granite_flask"}).to_dict(),
		ItemInstance.from_dict({"base": "small_power_flask"}).to_dict()]
	GameState._pending_loose_flasks.clear()
	GameState._pending_flasks = GameState._pending_flasks.duplicate()
	var town2 = load("res://scenes/town.tscn").instantiate()
	add_child(town2)
	await get_tree().process_frame
	await get_tree().process_frame
	var p2: Player = town2.player
	check(p2.flasks[0] != null and p2.flasks[0].base.id == "large_life_flask" and p2.flasks[1] != null and p2.flasks[1].base.id == "medium_power_flask",
		"the first life and first mana flask fill the two slots")
	var in_bag := p2.bag.items().filter(func(i): return i.is_flask()).size()
	check(in_bag >= 2, "the other flasks went to the bag (%d)" % in_bag)
	check(p2.charms.any(func(c): return c != null and c.base.id == "ruby_charm"), "the old Granite Flask came back as a Ruby Charm")

	# --- crafting ---
	check(Crafting.orb_block_reason(item("rope_belt"), "jeweller") != "", "no sockets on belts")
	var full := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	full.affixes = [LootGenerator.make_family_entry(full.base, "flask_amount", 0, 0.4), LootGenerator.make_family_entry(full.base, "flask_gained", 0, 0.3)]
	check(Crafting.orb_block_reason(full, "augment") == "Item is full", "a Magic flask with a prefix and suffix is full")
	check(Crafting.orb_block_reason(item("small_life_flask", ItemInstance.Rarity.MAGIC), "regal") != "", "a flask cannot be made Rare")
	check(Crafting.orb_block_reason(item("small_life_flask"), "alchemy") != "", "nor by Alchemy")
	check(ItemInstance.roll_sockets(item("small_life_flask").base, ItemInstance.Rarity.RARE) == 0, "flasks roll no sockets")

	print("flasks: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
