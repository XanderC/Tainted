extends Node2D
## Checks flasks and belts: bases and sizes, flask slots from belts, flask-only modifiers with
## prefix/suffix limits, recovery and buffs, cooldowns, Warding, equipping and swapping, pickup,
## old potions becoming flasks, saving, and crafting rules. Run headless:
##   godot --headless --path . res://scratch/test_flasks.tscn

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
	it.ilvl = 10
	it.display_name = it.base.display_name
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
	p.flasks = [null, null, null, null, null]

	# --- bases and sizes ---
	check(item("small_life_flask").grid_size() == Vector2i(1, 2), "flask 1x2")
	check(item("rope_belt").grid_size() == Vector2i(2, 1), "belt 2x1")
	check(item("chain_belt").base.flask_slots == 5, "chain belt opens 5")

	# --- belts open flask slots ---
	check(p.flask_slot_count() == 1, "no belt: 1 flask slot (got %d)" % p.flask_slot_count())
	var heavy := item("heavy_belt")
	check(p.equip_to(heavy, "belt", true), "wear a heavy belt")
	check(p.flask_slot_count() == 4, "heavy belt: 4 slots (got %d)" % p.flask_slot_count())

	# --- modifiers: flasks only roll flask mods, gear never does; prefix/suffix limits ---
	var bad_gear := false
	var bad_flask := false
	var over := false
	for k in 300:
		var g := LootGenerator.roll_item(20, ItemInstance.Rarity.RARE, "chest")
		if g.affixes.any(func(a): return String(a.stat).begins_with("flask_")):
			bad_gear = true
		var f := LootGenerator.roll_item(20, ItemInstance.Rarity.RARE if k % 2 else ItemInstance.Rarity.MAGIC, "flask")
		var pre := 0
		var suf := 0
		for a in f.affixes:
			var def := LootGenerator.find_affix(String(a.id))
			if not String(a.stat).begins_with("flask_"):
				bad_flask = true
			if def.prefix:
				pre += 1
			else:
				suf += 1
		var cap := 2 if f.rarity == ItemInstance.Rarity.RARE else 1
		if pre > cap or suf > cap:
			over = true
		if f.base.flask.kind == "utility" and f.affixes.any(func(a): return a.stat in ["flask_amount", "flask_instant"]):
			bad_flask = true
	check(not bad_gear, "gear never rolls flask modifiers")
	check(not bad_flask, "flasks only roll flask modifiers that suit their kind")
	check(not over, "at most 1 prefix + 1 suffix (Magic), 2 + 2 (Rare)")

	# --- a Magic flask is named PoE style ---
	var named := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	named.affixes = [LootGenerator.make_entry(LootGenerator.find_affix("fl_ample"), 0.2),
		LootGenerator.make_entry(LootGenerator.find_affix("fl_haste"), 0.1)]
	LootGenerator.rename(named)
	check(named.display_name == "Ample Small Life Flask of Haste", "magic name (got %s)" % named.display_name)

	# --- life flask recovers over its duration, then waits for its cooldown ---
	var life := item("small_life_flask")
	p.flasks[0] = life
	var max_life := p.stats.get_stat("max_life")
	p.hp = 1.0
	check(p.use_flask(0), "drink the life flask")
	check(p.hp < 2.0, "not instant: nothing yet")
	step(p, 3.2)
	check(absf(p.hp - (1.0 + max_life * 0.30)) < 2.0, "30%% of max life over 3s (hp %.1f of %.1f)" % [p.hp, max_life])
	check(not p.use_flask(0), "on cooldown")
	step(p, 5.0)
	check(p.use_flask(0), "usable again after its 8s cooldown")

	# --- Seething: instant, less ---
	var seething := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	seething.affixes = [LootGenerator.make_entry(LootGenerator.find_affix("fl_seething"), 0.25)]
	p.flasks[1] = seething
	p.hp = 1.0
	check(p.use_flask(1), "drink the seething flask")
	check(absf(p.hp - (1.0 + max_life * 0.30 * 0.75)) < 1.0, "instant, 25%% less (hp %.1f)" % p.hp)

	# --- utility buff and a during-effect suffix, both gone afterwards ---
	var armor_before := p.stats.get_stat("armor")
	var move_before := p.stats.get_stat("move_speed")
	var granite := item("granite_flask", ItemInstance.Rarity.MAGIC)
	granite.affixes = [LootGenerator.make_entry(LootGenerator.find_affix("fl_haste"), 0.10)]
	p.flasks[2] = granite
	check(p.use_flask(2), "drink the granite flask")
	check(absf(p.stats.get_stat("armor") - (armor_before + 50.0)) < 0.5, "granite: +50 armour (%.1f)" % p.stats.get_stat("armor"))
	check(p.stats.get_stat("move_speed") > move_before, "haste suffix: faster during effect")
	step(p, 5.2)
	check(absf(p.stats.get_stat("armor") - armor_before) < 0.5 and absf(p.stats.get_stat("move_speed") - move_before) < 0.5,
		"buffs gone when the effect ends")

	# --- Warding clears and blocks slows ---
	var ward := item("quicksilver_flask", ItemInstance.Rarity.MAGIC)
	ward.affixes = [LootGenerator.make_entry(LootGenerator.find_affix("fl_warding"), 1)]
	p.flasks[3] = ward
	p.apply_slow(3.0)
	check(p._slow_t > 0.0, "slowed")
	check(p.use_flask(3), "drink the warding flask")
	check(p._slow_t == 0.0, "warding removes the slow")
	p.apply_slow(3.0)
	check(p._slow_t == 0.0, "and prevents a new one")

	# --- a slot the belt doesn't open can't be drunk ---
	p.flasks[4] = item("small_power_flask")
	check(not p.use_flask(4), "slot 5 is locked with a heavy belt")

	# --- equipping, swapping, unequipping ---
	p.bag.clear()
	var spare := item("medium_life_flask")
	p.bag.place(spare, Vector2i(3, 1))
	var was: ItemInstance = p.flasks[0]
	check(p.equip_flask(spare, 0), "equip a flask from the bag")
	check(p.flasks[0] == spare and p.bag.has(was) and p.bag.position_of(was) == Vector2i(3, 1),
		"the old flask took its place in the bag")
	check(not p.equip_flask(item("iron_helm"), 0), "a helmet is no flask")
	check(p.can_unequip_flask_to(0, Vector2i(0, 0)), "flask can come off into space")
	check(p.unequip_flask_to(0, Vector2i(0, 0)) and p.flasks[0] == null and p.bag.position_of(spare) == Vector2i(0, 0),
		"unequipped into the bag")
	check(p.equip_flask(p.flasks[1], 0) and p.flasks[1] == null, "move a flask between slots")

	# --- picking one up fills an empty open slot ---
	p.flasks = [null, null, null, null, null]
	var found := item("large_life_flask")
	check(p.pick_up(found) and p.flasks[0] == found, "picked-up flask goes into an empty slot")

	# --- old potions become flasks ---
	GameState._flasks_from_potions({"health_2": 4, "power_1": 2, "health_1": 0}, "health_2")
	check(GameState._pending_flasks.size() == 1 and ItemInstance.from_dict(GameState._pending_flasks[0]).base.id == "medium_life_flask",
		"the slotted Greater Health Potion is now a worn Medium Life Flask")
	check(GameState._pending_loose_flasks.size() == 1 and GameState._pending_loose_flasks[0].base.id == "small_power_flask",
		"the other potion type is a flask in the bag")
	GameState._pending_loose_flasks.clear()

	# --- saving keeps flasks with their modifiers ---
	var magic := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	magic.affixes = [LootGenerator.make_entry(LootGenerator.find_affix("fl_chemist"), 0.2)]
	var back := ItemInstance.from_dict(magic.to_dict())
	check(back.is_flask() and absf(float(back.flask_effect().cooldown) - 6.4) < 0.01, "a saved flask keeps its 20%% faster cooldown")

	# --- crafting ---
	check(Crafting.orb_block_reason(item("rope_belt"), "jeweller") != "", "no sockets on belts")
	var full := item("small_life_flask", ItemInstance.Rarity.MAGIC)
	full.affixes = [LootGenerator.make_entry(LootGenerator.find_affix("fl_ample"), 0.2),
		LootGenerator.make_entry(LootGenerator.find_affix("fl_haste"), 0.1)]
	check(Crafting.orb_block_reason(full, "augment") == "Item is full", "a Magic flask with a prefix and suffix is full")
	check(ItemInstance.roll_sockets("flask", ItemInstance.Rarity.RARE) == 0, "flasks roll no sockets")

	print("flasks: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
