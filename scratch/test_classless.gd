extends Node2D
## Checks the classless game: characters from before are retired (the stash stays) and new ones are
## all Adventurers; the starting gems (one of each colour) work at once; gems need their attribute
## and some a weapon; Strength skills run on Adrenaline and the others on Mana; Strength scales
## attacks and Energy spells; every new Dexterity, Energy and hybrid skill lands; Arcane Ward, a
## Mana shield and Blood Magic; and the passive tree: four attribute branches, hybrid connectors and
## keystones, all joined up. Run headless:
##   godot --headless --path . res://scratch/test_classless.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	_accounts()
	await _playing()
	_tree()
	print("classless: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _accounts() -> void:
	var files := {
		"account": {"characters": [
			{"id": "old1", "name": "Brom", "class": "warrior", "level": 30},
			{"id": "new1", "name": "Kael", "class": "Ranger", "level": 5, "v": GameState.CHAR_VERSION}],
			"last": "old1", "stash": [], "shared": {"orbs": {"chaos": 4}, "shards": {}, "skill_gems": {}, "runes": {}, "gems": {}}},
		"characters/old1": {"version": 2, "name": "Brom", "class": "warrior", "level": 30},
		"characters/new1": {"version": 2, "name": "Kael", "level": 5},
	}
	GameState.use_online_files(files)
	check(GameState.characters.size() == 1 and GameState.characters[0].id == "new1", "a character from before classes went is retired (%d left)" % GameState.characters.size())
	check(not GameState.online_files.has("characters/old1"), "and its save deleted")
	check(GameState.orb_count("chaos") == 4, "the account's stash and pools stay")
	check(GameState.last_character == "", "the retired one isn't picked any more")
	var id := GameState.create_character("Ash", "", {})
	var info := GameState.character_info(id)
	check(id != "" and GameState.char_class == "adventurer" and int(info.get("v", 0)) == GameState.CHAR_VERSION,
		"a new character: an Adventurer, of this version")
	check(String(info.get("class", "")) == "Adventurer", "listed as an Adventurer until its points say more")
	GameState.char_id = ""  # (play on without saving into the fake account)


func _playing() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	p.global_position = main.maze.random_floor_near(main.maze.start_pos, 100.0, 200.0)
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	p._sync_gear_visuals()
	GameState.level = 1
	GameState.attributes = {}
	GameState.attr_points = 0
	p.refresh_attributes()
	await get_tree().process_frame

	# The starting gems: one of each colour, all usable at level 1 with nothing added
	check(GameState.STARTER_SKILLS == ["cleave", "frenzy", "firebolt"], "the starting gems are a red, a green and a blue one")
	for i in 3:
		check(p.skills[i] != null and p.skill_block_reason(p.skills[i]) == "", "%s works from the start" % GameState.STARTER_SKILLS[i])
	check(p.skills[0].uses_mana() == false and p.skills[1].uses_mana() and p.skills[2].uses_mana(), "red runs on Adrenaline, green and blue on Mana")
	check(SkillTree.get_skill("firebolt").resource_cost == 0.0 and SkillTree.get_skill("frost_nova").resource_cost > 0.0,
		"basic Mana skills cost nothing, the others Mana")

	# Gems need their attribute
	GameState.add_skill_gem("whirlwind", 1)
	check(GameState.gem_attr_block_reason("whirlwind").begins_with("Requires 18 Strength"), "Whirlwind needs 18 Strength (%s)" % GameState.gem_attr_block_reason("whirlwind"))
	check(not GameState.set_slot_skill(3, "whirlwind"), "can't socket it with 15")
	GameState.level = 3  # (it's a core gem: level 3)
	GameState.attr_points = 3
	GameState.add_attribute("str", 3)
	check(GameState.set_slot_skill(3, "whirlwind"), "with 18 Strength it goes in")
	check(SkillTree.gem_attr_req("smite") == {"str": 18, "ene": 13}, "a two-colour gem needs both (%s)" % [SkillTree.gem_attr_req("smite")])

	# Plenty of everything for the rest
	GameState.level = 30
	GameState.attributes = {"str": 80, "dex": 80, "vit": 20, "ene": 80}
	p.refresh_attributes()
	GameState._on_skills_modified()

	# Weapons: a bow for bow skills, a melee weapon (or none) for melee ones
	GameState.add_skill_gem("quick_shot", 1)
	GameState.set_slot_skill(1, "quick_shot")
	check(p.skill_block_reason(p.skills[1]) == "Needs a bow", "Quick Shot needs a bow (%s)" % p.skill_block_reason(p.skills[1]))
	var bow := _item("hunting_bow")
	p.bag.add(bow)
	check(p.can_equip(bow) and p.equip_to(bow, "weapon"), "anyone can wield a bow (no classes)")
	check(p.skill_block_reason(p.skills[1]) == "" and p.skill_block_reason(p.skills[0]) == "Needs a melee weapon",
		"with a bow: Quick Shot works, Cleave doesn't")
	var staff := _item("oak_staff")
	check(p.can_equip(staff) or Attributes.block_reason(staff.base, GameState.attribute_totals()) != "", "staves too")

	# Damage: Strength for attacks, Energy for spells
	var atk := p.damage_for(SkillTree.get_skill("cleave"))
	var spell := p.damage_for(SkillTree.get_skill("firebolt"))
	GameState.attributes["ene"] = 180
	p.refresh_attributes()
	check(p.damage_for(SkillTree.get_skill("firebolt")) > spell * 1.5 and absf(p.damage_for(SkillTree.get_skill("cleave")) - atk) < 0.01,
		"Energy scales spells, not attacks")
	GameState.attributes["ene"] = 80
	p.refresh_attributes()

	# A dummy to hit
	var dummy := Enemy.new()
	dummy.max_hp = 1.0e9
	dummy.speed = 0.0
	dummy.touch_damage = 0.0
	dummy.set_kind("zombie")
	main.add_child(dummy)
	dummy.global_position = p.global_position + Vector2(110, 0)
	await get_tree().process_frame

	# Resources
	p.mana = p.max_mana()
	var res0 := p.resource
	_use(p, "frost_nova")
	check(p.mana < p.max_mana() - 5.0 and absf(p.resource - res0) < 0.01, "a Mana skill spends Mana, not Adrenaline")

	# Every new skill lands on the dummy: [skill, weapon to hold]
	for t in [["quick_shot", "hunting_bow"], ["power_shot", "hunting_bow"], ["multishot", "hunting_bow"], ["arrow_rain", "hunting_bow"],
			["shadow_step", ""], ["fan_of_knives", ""], ["death_blossom", ""], ["firebolt", ""], ["frost_nova", ""], ["arc", ""],
			["meteor", ""], ["holy_nova", ""], ["thunderstorm", ""], ["smite", "rusty_sword"], ["viper_strike", "rusty_sword"],
			["frenzy", "rusty_sword"], ["blade_vortex", ""]]:
		_hold(p, String(t[1]))
		p.global_position = dummy.global_position + Vector2(-110, 0)
		p.facing = Vector2.RIGHT
		p.mana = p.max_mana()
		p.resource = p.max_resource()
		var hp0 := dummy.hp
		_use(p, String(t[0]))
		await get_tree().create_timer(2.2 if t[0] in ["arrow_rain", "meteor", "thunderstorm", "death_blossom"] else 0.8).timeout
		check(dummy.hp < hp0, "%s lands (%.0f damage)" % [t[0], hp0 - dummy.hp])

	# Holy Nova heals
	_hold(p, "")
	p.hp = p.stats.get_stat("max_life") * 0.5
	_use(p, "holy_nova")
	check(p.hp > p.stats.get_stat("max_life") * 0.6, "Holy Nova heals you")

	# Arcane Ward: 40% less damage
	p.hp = p.stats.get_stat("max_life")
	var before := p.hp
	p.take_damage(50.0)
	var plain := before - p.hp
	p.hp = before
	_use(p, "arcane_ward")
	p.take_damage(50.0)
	check(absf((before - p.hp) - plain * Player.WARD_TAKEN) < 0.5, "Arcane Ward takes 40%% of a hit (%.1f vs %.1f)" % [before - p.hp, plain])
	p._ward_t = 0.0

	# A Mana shield (Eldritch Battery) and Blood Magic (keystones, here through item powers)
	p.item_powers["mana_shield"] = 0.3
	p.hp = before
	p.mana = p.max_mana()
	p.take_damage(50.0)
	check(p.mana < p.max_mana() and absf((before - p.hp) - plain * 0.7) < 0.5, "a Mana shield takes 30%% of a hit off Mana")
	p.item_powers.erase("mana_shield")
	if GameState.slot_of("frost_nova") != 1:
		GameState.set_slot_skill(1, "frost_nova")  # (socketing recounts gear powers: socket first)
	p.item_powers["blood_magic"] = 1.0
	p.mana = 0.0
	p.hp = before
	p._cooldowns[1] = 0.0
	p.use_skill(1)
	check(p.hp < before and p.mana < 1.0, "Blood Magic: a Mana skill costs life instead (%.0f life)" % (before - p.hp))
	p.item_powers.erase("blood_magic")

	# The shop's gems: every colour
	var shop := ShopPanel.new()
	shop.player = p
	var wares := shop._wares().filter(func(w): return w.type == "skillgem")
	var colours := {}
	for w in wares:
		colours[SkillTree.get_skill(w.id).main_attribute()] = true
	check(colours.has("str") and colours.has("dex") and colours.has("ene"), "the Merchant sells red, green and blue gems (%d)" % wares.size())
	shop.free()
	await _gear_and_supports(p)
	_main_attributes(p)


## Diablo III's primary stat: every Magic item has one main attribute (Strength, Dexterity or
## Energy) besides its modifiers, every Rare, Legendary and Set item two different ones; orbs keep it so.
func _main_attributes(p: Player) -> void:
	var mains := func(it: ItemInstance) -> Array:
		return it.affixes.filter(func(a): return LootGenerator.is_main_attribute(a)).map(func(a): return String(a.id))
	var ok := {"normal": true, "magic": true, "rare": true}
	for i in 40:
		var n := LootGenerator.roll_item(10, ItemInstance.Rarity.NORMAL, "chest")
		var m := LootGenerator.roll_item(10, ItemInstance.Rarity.MAGIC, "ring")
		var r := LootGenerator.roll_item(10, ItemInstance.Rarity.RARE, "weapon")
		ok.normal = ok.normal and mains.call(n).is_empty()
		ok.magic = ok.magic and mains.call(m).size() == 1 and LootGenerator.stat_affix_count(m) >= 1
		var rm: Array = mains.call(r)
		ok.rare = ok.rare and rm.size() == 2 and rm[0] != rm[1] and LootGenerator.stat_affix_count(r) >= 3
	check(ok.normal, "Normal items have no main attribute")
	check(ok.magic, "every Magic item has one main attribute besides its modifiers")
	check(ok.rare, "every Rare item has two different ones besides its modifiers")
	var leg := UniqueItems.make("windpiercer", 20)
	var lm: Array = mains.call(leg)
	check(lm.size() == 2 and lm[0] == "attr_dex", "a Legendary has two, its own lean first (%s)" % [lm])
	var flask := LootGenerator.roll_item(10, ItemInstance.Rarity.MAGIC, "flask")
	check(mains.call(flask).is_empty(), "flasks have none")
	# Orbs keep it so
	GameState.orbs = {"alteration": 5, "augment": 5, "regal": 2, "annul": 5, "chaos": 3}
	var it := LootGenerator.roll_item(10, ItemInstance.Rarity.MAGIC, "ring")
	while LootGenerator.stat_affix_count(it) > 1:
		it.affixes.erase(it.affixes.filter(func(a): return not LootGenerator.is_main_attribute(a))[0])
	p.bag.add(it)
	Crafting.apply_orb(p, it, "augment")
	check(mains.call(it).size() == 1 and LootGenerator.stat_affix_count(it) == 2, "Augmentation adds a modifier, never a main attribute")
	Crafting.apply_orb(p, it, "alteration")
	check(mains.call(it).size() == 1, "Alteration rerolls it, still with one main attribute")
	Crafting.apply_orb(p, it, "regal")
	check(it.rarity == ItemInstance.Rarity.RARE and mains.call(it).size() == 2, "a Regal Orb makes it Rare: two main attributes")
	var before: Array = mains.call(it)
	for i in 3:
		Crafting.apply_orb(p, it, "annul")
	check(mains.call(it) == before, "Annulment never takes a main attribute")
	Crafting.apply_orb(p, it, "chaos")
	check(mains.call(it).size() == 2 and LootGenerator.stat_affix_count(it) >= 3, "Chaos rerolls a Rare: two main attributes and its modifiers")


## Gear for every build (attribute, spell, Mana and bow modifiers), Legendaries leaning to your
## build, drops you can wield, Dexterity scaling green attacks, and supports on arrows.
func _gear_and_supports(p: Player) -> void:
	_hold(p, "")
	GameState.attributes = {"str": 10, "dex": 10, "vit": 0, "ene": 10}
	p.refresh_attributes()
	var dex0 := GameState.attribute_total("dex")
	var req0: int = GameState.attribute_totals().dex
	var ring := _item("bone_ring")
	ring.affixes.append(LootGenerator.make_entry(LootGenerator.find_affix("attr_dex"), 20.0))
	p.bag.add(ring)
	p.equip_to(ring, "ring")
	check(GameState.attribute_total("dex") == dex0 + 20, "a ring of +20 Dexterity adds 20 (%d -> %d)" % [dex0, GameState.attribute_total("dex")])
	check(int(GameState.attribute_totals().dex) == req0, "but not towards gear requirements (no items holding each other up)")
	var spell0 := p.spell_mult()
	var mana0 := p.max_mana()
	var am := _item("old_amulet")
	am.affixes.append(LootGenerator.make_entry(LootGenerator.find_affix("spell_inc"), 0.2))
	am.affixes.append(LootGenerator.make_entry(LootGenerator.find_affix("mana_flat"), 30.0))
	p.bag.add(am)
	p.equip_to(am, "amulet")
	check(absf(p.spell_mult() - spell0 - 0.2) < 0.001 and absf(p.max_mana() - mana0 - 30.0) < 0.01,
		"an amulet of spell damage and Mana: +20% spells, +30 Mana")
	check(LootGenerator.find_affix("bow_inc").fits(LootGenerator.base_by_id("long_bow"))
		and not LootGenerator.find_affix("bow_inc").fits(LootGenerator.base_by_id("rusty_sword")), "bow damage rolls on bows, not swords")
	p.unequip("ring")
	p.unequip("amulet")
	# Green attacks scale with Dexterity, red with Strength
	GameState.attributes = {"str": 0, "dex": 50, "vit": 0, "ene": 0}
	p.refresh_attributes()
	check(absf(p.attack_mult(SkillTree.get_skill("quick_shot")) - 1.5) < 0.001 and absf(p.attack_mult(SkillTree.get_skill("cleave")) - 1.0) < 0.001,
		"50 Dexterity: +50% to green attacks, nothing to red ones")
	# Legendaries lean to the build
	GameState.attributes = {"str": 0, "dex": 0, "vit": 0, "ene": 80}
	p.refresh_attributes()
	var ene := 0
	for i in 40:
		var u := UniqueItems.roll(20, false, p.class_def)
		if u != null and UniqueItems.attr_of(u.unique_id) == "ene":
			ene += 1
	check(ene >= 18, "an Energy build finds mostly Energy Legendaries (%d of 40)" % ene)
	check(CraftingDB.RECIPES.has("plan_windpiercer") or CraftingDB.RECIPES.keys().any(func(k): return String(k).contains("windpiercer")),
		"and every new one has a plan to forge")
	# Weapons that drop are mostly ones you can wield
	GameState.attributes = {}
	p.refresh_attributes()
	var ok := 0
	for i in 60:
		var w := LootGenerator.roll_item(2, ItemInstance.Rarity.NORMAL, "weapon")
		if Attributes.meets(w.base, GameState.attribute_totals()):
			ok += 1
	check(ok >= 45, "a fresh character's weapon drops are mostly ones it can wield (%d of 60)" % ok)
	# Supports on arrows: Echo looses it again, Nova makes Multishot a ring
	GameState.attributes = {"str": 80, "dex": 80, "vit": 20, "ene": 80}
	p.refresh_attributes()
	_hold(p, "hunting_bow")
	var arrows := [0]
	var count := func(n: Node):
		if n is HirelingArrow:
			arrows[0] += 1
	get_tree().node_added.connect(count)
	_use(p, "quick_shot")
	GameState.skill_slots[1].supports = ["rune_echo"]
	GameState._on_skills_modified()
	arrows[0] = 0
	p._cooldowns[1] = 0.0
	p.use_skill(1)
	await get_tree().create_timer(0.5).timeout
	check(arrows[0] == 2, "with Echo, Quick Shot looses a second arrow (%d)" % arrows[0])
	_use(p, "multishot")
	GameState.skill_slots[1].supports = ["rune_nova"]
	GameState._on_skills_modified()
	arrows[0] = 0
	p._cooldowns[1] = 0.0
	p.mana = p.max_mana()
	p.use_skill(1)
	await get_tree().process_frame
	check(arrows[0] == 8, "with Nova, Multishot is a ring of 8 arrows (%d)" % arrows[0])
	get_tree().node_added.disconnect(count)
	GameState.skill_slots[1].supports = []
	GameState._on_skills_modified()


func _use(p: Player, id: String) -> void:
	if GameState.skill_gem_count(id) <= 0 and GameState.slot_of(id) < 0:
		GameState.add_skill_gem(id, 1)
	if GameState.slot_of(id) != 1:
		GameState.set_slot_skill(1, id)
	p._cooldowns[1] = 0.0
	p.use_skill(1)


func _hold(p: Player, base_id: String) -> void:
	var w: ItemInstance = p.equipment.get("weapon")
	if w != null and w.base.id == base_id:
		return
	if w != null:
		p.unequip("weapon")
	if base_id != "":
		var it := _item(base_id)
		p.bag.add(it)
		p.equip_to(it, "weapon")


func _item(base_id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(base_id)
	it.ilvl = 1
	it.display_name = it.base.display_name
	return it


func _tree() -> void:
	var g := PassiveTree.get_tree()
	var dirs := {"str": Vector2(0, -1), "dex": Vector2(1, 0), "vit": Vector2(0, 1), "ene": Vector2(-1, 0)}
	for k in dirs:
		var n: Dictionary = g.nodes.get(k + "_p0", {})
		check(not n.is_empty() and int(n.stats.get(k, 0)) == 8 and n.pos.normalized().is_equal_approx(dirs[k]),
			"a %s branch leaves the start, its first node +8 %s" % [Attributes.NAMES[k], Attributes.NAMES[k]])
	check(g.nodes.str_c0.stats.has("str") and g.nodes.str_c0.stats.has("dex"), "the Strength-Dexterity connector gives both")
	check(g.nodes.ene_c0.stats.has("ene") and g.nodes.ene_c0.stats.has("str"), "and the Energy-Strength one")
	check(g.nodes.cl7_key.name == "Assassin's Creed" and g.nodes.cl5_key.name == "Templar's Oath", "the Assassin's and Paladin's keystones sit between")
	var seen := {"start": true}
	var queue := ["start"]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for l in g.nodes[cur].links:
			if not seen.has(l):
				seen[l] = true
				queue.append(l)
	check(seen.size() == g.nodes.size(), "every node joins up (%d of %d)" % [seen.size(), g.nodes.size()])
	for nid in g.nodes:
		var t := PassiveTree.stat_text(g.nodes[nid].stats)
		if g.nodes[nid].kind != "start" and t == "":
			check(false, "%s says what it does" % nid)
	# The tree's attribute points count like added ones
	GameState.reset_all_skills()
	GameState.attributes = {}
	GameState.skill_points = 5
	var str0 := GameState.attribute_total("str")
	check(GameState.allocate_node("str_p0"), "take the first Strength node")
	check(GameState.attribute_total("str") == str0 + 8, "+8 Strength (%d -> %d)" % [str0, GameState.attribute_total("str")])
	GameState.allocate_node("str_p1")
	GameState.allocate_node("str_p2")
	check(GameState.build_title() == "Warrior", "16 Strength from the tree: a Warrior (%s)" % GameState.build_title())
	GameState.reset_all_skills()
