extends Node2D
## Checks the PoE2-style modifiers: prefix and suffix limits by rarity, one per family, tiers gated by item
## level, class pools, the orbs (Transmutation 1, Augmentation, Regal, Alchemy 4, Exalted, Chaos swaps one,
## Annulment), saves round-tripping and old saves converting. Run headless:
##   godot --headless --path . res://scratch/test_modifiers.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func make(id: String, rarity: int, ilvl: int) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = ilvl
	it.display_name = it.base.display_name
	return it


func sides(it: ItemInstance) -> Vector2i:
	var p := 0
	var s := 0
	for e in it.affixes:
		if LootGenerator.entry_is_prefix(e):
			p += 1
		else:
			s += 1
	return Vector2i(p, s)


func _ready() -> void:
	await get_tree().process_frame
	var R := ItemInstance.Rarity
	var ids := ["iron_helm", "chain_mail", "leather_gloves", "worn_boots", "kite_shield", "bone_ring", "old_amulet", "heavy_belt",
		"rusty_sword", "greatsword", "dagger", "oak_staff", "hunting_bow", "hunting_crossbow", "hand_axe", "laced_bracers"]

	# --- limits by rarity, one per family, tier gating, and the right pool for every base ---
	var broke_limit := false
	var broke_family := false
	var broke_tier := false
	var broke_pool := false
	var counts := {R.MAGIC: [0, 0], R.RARE: [0, 0]}
	for id in ids:
		for ilvl in [1, 12, 30, 55]:
			for rarity in [R.MAGIC, R.RARE]:
				for n in 40:
					var it := make(id, rarity, ilvl)
					LootGenerator.roll_affixes(it, 6)
					var sd := sides(it)
					var cap := 1 if rarity == R.MAGIC else 3
					if sd.x > cap or sd.y > cap:
						broke_limit = true
					var fams := it.affixes.map(func(e): return e.family)
					if fams.size() != Array(fams).filter(func(f): return fams.count(f) == 1).size():
						broke_family = true
					var allowed := AffixDB.families_for(it.base)
					for e in it.affixes:
						var tiers := AffixDB.tiers_for(it.base, e.family)
						if int(tiers[int(e.tier)][0]) > ilvl:
							broke_tier = true
						if not allowed.has(e.family):
							broke_pool = true
					counts[rarity][0] += it.affixes.size()
					counts[rarity][1] += 1
	check(not broke_limit, "Magic never passes 1 prefix + 1 suffix, Rare never 3 + 3")
	check(not broke_family, "one modifier per family")
	check(not broke_tier, "a tier needs its item level")
	check(not broke_pool, "every modifier is one its item class has")
	check(float(counts[R.RARE][0]) / counts[R.RARE][1] > 4.5, "Rare gear fills up (avg %.1f)" % (float(counts[R.RARE][0]) / counts[R.RARE][1]))

	# --- class pools ---
	var helm := make("iron_helm", R.RARE, 40)
	check(not AffixDB.families_for(helm.base).has("spell_dmg"), "no spell damage on a helmet")
	check(AffixDB.families_for(make("oak_staff", R.RARE, 40).base).has("spell_dmg"), "spell damage on a staff")
	check(AffixDB.families_for(make("hunting_bow", R.RARE, 40).base).has("phys_pct"), "physical damage % on a bow")
	check(not AffixDB.families_for(make("hunting_bow", R.RARE, 40).base).has("armour"), "no armour on a bow")
	check(AffixDB.families_for(make("worn_boots", R.RARE, 40).base).has("move_speed"), "movement speed on boots")
	check(not AffixDB.families_for(make("iron_helm", R.RARE, 40).base).has("move_speed"), "none on a helmet")
	# Level 1 items only reach the first tier of a family
	var low := make("bone_ring", R.RARE, 1)
	var open := AffixDB.open_tiers(low.base, "life", 1)
	check(open.size() == 1, "a level 1 ring has life tier 1 only (%d)" % open.size())
	check(AffixDB.open_tiers(low.base, "life", 60).size() == 8, "a level 60 ring has all 8 life tiers")
	check(AffixDB.open_tiers(low.base, "res_all", 5).is_empty(), "all-resistances starts at level 12")

	# --- no guaranteed attributes any more ---
	var strs := 0
	for n in 200:
		var it := LootGenerator.roll_item(20, R.MAGIC)
		for e in it.affixes:
			if e.get("family", "") in ["str", "dex", "vit", "ene"]:
				strs += 1
	check(strs < 200, "attributes are ordinary suffixes now (%d of 200 Magic items)" % strs)
	var none_normal := true
	for n in 50:
		none_normal = none_normal and LootGenerator.roll_item(20, R.NORMAL).affixes.is_empty()
	check(none_normal, "Normal items have none")

	# --- orbs ---
	var item := make("iron_helm", R.NORMAL, 30)
	GameState.orbs["transmute"] = 50
	GameState.orbs["augment"] = 50
	GameState.orbs["regal"] = 50
	GameState.orbs["alchemy"] = 50
	GameState.orbs["chaos"] = 50
	GameState.orbs["exalt"] = 50
	GameState.orbs["annul"] = 50
	GameState.orbs["divine"] = 50
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	check(Crafting.apply_orb(p, item, "transmute")["ok"] and item.rarity == R.MAGIC and item.affixes.size() == 1, "Transmutation: Magic with 1 modifier")
	check(Crafting.apply_orb(p, item, "augment")["ok"] and item.affixes.size() == 2, "Augmentation adds the second")
	check(not Crafting.apply_orb(p, item, "augment")["ok"], "a full Magic item takes no more")
	check(Crafting.apply_orb(p, item, "regal")["ok"] and item.rarity == R.RARE and item.affixes.size() == 3, "Regal: Rare, +1")
	var kept := item.affixes.size()
	var before := item.affixes.map(func(e): return e.text)
	check(Crafting.apply_orb(p, item, "chaos")["ok"] and item.affixes.size() == kept, "Chaos keeps the count")
	var changed := item.affixes.map(func(e): return e.text).filter(func(t): return not before.has(t)).size()
	check(changed <= 1, "Chaos replaces one modifier (%d new)" % changed)
	check(Crafting.apply_orb(p, item, "exalt")["ok"] and item.affixes.size() == kept + 1, "Exalted adds one")
	check(Crafting.apply_orb(p, item, "annul")["ok"] and item.affixes.size() == kept, "Annulment removes one")
	var alch := make("kite_shield", R.NORMAL, 40)
	check(Crafting.apply_orb(p, alch, "alchemy")["ok"] and alch.rarity == R.RARE and alch.affixes.size() == 4, "Alchemy: Rare with 4")
	var full := make("kite_shield", R.RARE, 60)
	LootGenerator.roll_affixes(full, 6)
	var sd := sides(full)
	check((Crafting.orb_block_reason(full, "exalt") == "") == (sd.x < 3 or sd.y < 3), "a Rare takes an Exalted Orb only while a side has room (%d + %d)" % [sd.x, sd.y])
	check(not CraftingDB.ORBS.has("alteration") and not CraftingDB.ORBS.has("scour"), "no Alteration or Scouring orb")

	# Divine keeps tiers, rerolls values inside them
	var div := make("chain_mail", R.RARE, 50)
	LootGenerator.roll_affixes(div, 5)
	var tiers_before := div.affixes.map(func(e): return e.tier)
	LootGenerator.reroll_values(div)
	check(div.affixes.map(func(e): return e.tier) == tiers_before, "Divine keeps the tiers")

	# --- saves ---
	var rare := make("heavy_belt", R.RARE, 45)
	LootGenerator.roll_affixes(rare, 6)
	var back := ItemInstance.from_dict(rare.to_dict())
	check(back != null and back.affixes.size() == rare.affixes.size(), "a Rare round-trips")
	var same := true
	for i in rare.affixes.size():
		same = same and back.affixes[i].family == rare.affixes[i].family and back.affixes[i].tier == rare.affixes[i].tier \
			and absf(float(back.affixes[i].value) - float(rare.affixes[i].value)) < 0.0001 and back.affixes[i].text == rare.affixes[i].text
	check(same, "families, tiers, values and text survive saving")

	# --- old saves ---
	var old := {"base": "iron_helm", "rarity": 2, "ilvl": 30, "name": "Grim Iron Helm of Woe", "sockets": 0, "gems": [],
		"affixes": [{"id": "life_flat", "value": 55.0}, {"id": "attr_str", "value": 9.0}, {"id": "res_fire", "value": 0.18},
			{"id": "spell_inc", "value": 0.2}, {"id": "bow_inc", "value": 0.2}, {"id": "armor_flat", "value": 20.0}]}
	var conv := ItemInstance.from_dict(old)
	var fams := conv.affixes.map(func(e): return e.family)
	check(fams.has("life") and fams.has("str") and fams.has("res_fire") and fams.has("armour"), "old modifiers become families (%s)" % str(fams))
	check(not fams.has("spell_dmg") and not fams.has("phys_pct"), "ones a helmet can't have are dropped")
	var ok := true
	for e in conv.affixes:
		var tiers := AffixDB.tiers_for(conv.base, e.family)
		var t: Array = tiers[int(e.tier)]
		ok = ok and int(t[0]) <= 30 and float(e.value) >= AffixDB.round_value(e.family, float(t[1])) - 0.0001 \
			and float(e.value) <= AffixDB.round_value(e.family, float(t[2])) + 0.0001
	check(ok, "converted values sit inside their tier at the item's level")
	var twice := ItemInstance.from_dict(conv.to_dict())
	check(twice.affixes.size() == conv.affixes.size() and twice.affixes[0].tier == conv.affixes[0].tier, "converting is stable")

	# --- the stats they give ---
	var ring := make("bone_ring", R.RARE, 30)
	ring.affixes = [LootGenerator.make_family_entry(ring.base, "all_attr", 0, 3.0), LootGenerator.make_family_entry(ring.base, "life_kill", 0, 4.0),
		LootGenerator.make_family_entry(ring.base, "fire_add", 0, 5.0)]
	var str_before := GameState.attribute_bonus("str")
	p.equip_to(ring, "ring", true)
	check(GameState.attribute_bonus("str") == str_before + 3, "+3 to all Attributes adds to Strength")
	p.hp = 10.0
	p.on_enemy_killed(Vector2.ZERO)
	check(p.hp >= 14.0 - 0.01, "life per kill heals (hp %.1f)" % p.hp)
	check(p.stats.get_stat("dmg_fire") >= 5.0, "added fire damage reaches the stat block")

	print("modifiers: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
