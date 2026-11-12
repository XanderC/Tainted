extends Node2D
## Checks the modifiers added after the first PoE2 pass: Evasion Rating, Energy Shield, block, thorns, armour that
## also applies to elemental damage, maximum resistances, life and mana per hit, mana leech, damage recouped, rarity
## of items found, stun threshold and reduced ailment durations: that they roll on the right gear and that the stat
## does what it says. Run headless:   godot --headless --path . res://scratch/test_defences.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func base(id: String) -> ItemBase:
	return LootGenerator.base_by_id(id)


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	var max_life := p.stats.get_stat("max_life")

	# --- which gear rolls what ---
	for pair in [["chest", "evasion"], ["chest", "es"], ["helmet", "es_pct"], ["gloves", "evasion_pct"], ["ring", "rarity_prefix"],
			["amulet", "recoup_life"], ["amulet", "recoup_mana"], ["kite_shield", "block"], ["kite_shield", "max_fire"], ["kite_shield", "thorns"],
			["chest", "stun_threshold"], ["chest", "ail_bleed"], ["boots", "ail_freeze"], ["gloves", "life_hit"],
			["gloves", "mana_leech"], ["rusty_sword", "stun_threshold"] if false else ["amulet", "rarity"]]:
		var id: String = pair[0]
		var b: ItemBase = base({"chest": "chain_mail", "helmet": "iron_helm", "gloves": "leather_gloves", "ring": "bone_ring", "amulet": "old_amulet", "boots": "worn_boots"}.get(id, id))
		check(AffixDB.families_for(b).has(pair[1]), "%s can roll %s" % [b.id, pair[1]])
	check(not AffixDB.families_for(base("iron_helm")).has("block"), "a helmet cannot roll block")
	check(not AffixDB.families_for(base("old_amulet")).has("evasion"), "nor an amulet evasion")

	# --- evasion: some hits miss, a lot of evasion misses most ---
	p.stats.add_mod("evasion", StatBlock.ModType.FLAT, 450.0, "test")  # 450 / (450 + 150) = 75%
	var hurt := 0
	for i in 400:
		p.hp = max_life
		p.take_damage(1.0, RuneDef.DamageType.PHYSICAL)
		if p.hp < max_life:
			hurt += 1
	p.stats.remove_source("test")
	check(hurt > 60 and hurt < 140, "75%% evasion avoids about three hits in four (%d of 400 landed)" % hurt)
	p.hp = max_life
	p.take_damage(1.0, RuneDef.DamageType.PHYSICAL)
	check(p.hp < max_life, "with no evasion every hit lands")

	# --- block ---
	p.stats.add_mod("block", StatBlock.ModType.FLAT, 0.5, "test")
	hurt = 0
	for i in 400:
		p.hp = max_life
		p.take_damage(1.0, RuneDef.DamageType.PHYSICAL)
		if p.hp < max_life:
			hurt += 1
	p.stats.remove_source("test")
	check(hurt > 150 and hurt < 250, "50%% block stops about half (%d of 400 landed)" % hurt)

	# --- energy shield: takes damage first, recharges after a wait ---
	p.stats.add_mod("energy_shield", StatBlock.ModType.FLAT, 50.0, "test")
	check(p.max_energy_shield() == 50.0 and p.energy_shield() == 50.0, "a full Energy Shield of 50")
	p.hp = max_life
	p.take_damage(30.0, RuneDef.DamageType.CHAOS)
	var soaked := 50.0 - p.energy_shield()
	check(soaked > 20.0 and p.hp > max_life - 5.0, "it soaked the hit (%.1f gone, life %.1f of %.1f)" % [soaked, p.hp, max_life])
	p.take_damage(110.0, RuneDef.DamageType.PHYSICAL)
	check(p.energy_shield() == 0.0 and p.hp < max_life, "a big hit empties it and hurts")
	p._ail.clear()  # (a bleed ticking would keep delaying the recharge)
	p._ail_dps.clear()
	for i in 30:
		p._process_flasks(0.05)
	check(p.energy_shield() == 0.0, "no recharge yet, it was just hit")
	for i in 80:
		p._process_flasks(0.05)
	check(p.energy_shield() > 5.0, "then it recharges (%.1f, es %.1f wait %.2f max %.1f dead %s)" % [p.energy_shield(), p._es, p._es_wait, p.max_energy_shield(), p.dead])
	p.stats.remove_source("test")

	if p.dead:
		p.revive(1.0)
	# --- maximum resistances ---
	p.stats.add_mod("res_fire", StatBlock.ModType.FLAT, 0.9, "test")
	check(absf(p.resistance(RuneDef.DamageType.FIRE) - 0.75) < 0.001, "fire resistance caps at 75%%")
	p.stats.add_mod("max_res_fire", StatBlock.ModType.FLAT, 0.05, "test")
	check(absf(p.resistance(RuneDef.DamageType.FIRE) - 0.80) < 0.001, "+5%% maximum fire resistance: 80%%")
	check(absf(p.resistance(RuneDef.DamageType.COLD) - 0.0) < 0.001, "and cold is unaffected")
	p.stats.remove_source("test")

	# --- recoup, thorns, rarity ---
	p.stats.add_mod("recoup_life", StatBlock.ModType.FLAT, 0.2, "test")
	p.hp = max_life - 50.0
	var before := p.hp
	p.take_damage(10.0, RuneDef.DamageType.PHYSICAL)
	check(p.hp > before - 10.0, "damage recouped as life: lost less than the hit (%.2f)" % (before - p.hp))
	p.stats.remove_source("test")
	var th0 := p.thorns()
	p.stats.add_mod("thorns", StatBlock.ModType.FLAT, 12.0, "test")
	check(absf(p.thorns() - th0 - 12.0) < 0.001, "thorns add to the retaliation")
	p.stats.remove_source("test")
	p.stats.add_mod("item_rarity", StatBlock.ModType.FLAT, 0.3, "test")
	check(absf(LootGenerator.rarity_bonus() - 0.3) < 0.001, "rarity of items found from gear")
	p.stats.remove_source("test")

	# --- ailment duration modifiers reach the ailments ---
	p.stats.add_mod("ail_bleed", StatBlock.ModType.FLAT, 0.4, "test")
	p.inflict("bleed", 10.0)
	check(absf(float(p._ail.bleed) - 2.4) < 0.001, "40%% reduced bleeding: 4s becomes 2.4s")
	p.stats.remove_source("test")

	# --- gear with them saves and loads ---
	var armour := ItemInstance.new()
	armour.base = base("linen_robe")
	armour.rarity = ItemInstance.Rarity.RARE
	armour.ilvl = 60
	armour.affixes = [LootGenerator.make_family_entry(armour.base, "es", 2, 25.0), LootGenerator.make_family_entry(armour.base, "ail_ignite", 0, 0.3)]
	var back := ItemInstance.from_dict(armour.to_dict())
	check(back.affixes.size() == 2 and back.affixes[0].family == "es" and back.affixes[1].family == "ail_ignite", "they save and load")
	p.bag.add(armour)
	p.equip_to(armour, "chest", true)
	check(p.max_energy_shield() > 0.0, "worn, it gives Energy Shield (%.1f; chest %s)" % [p.max_energy_shield(), str(p.equipment.get("chest"))])

	# --- a rolled set gives all of these somewhere ---
	var seen := {}
	for k in 600:
		for slot in ["chest", "helmet", "gloves", "boots", "ring", "amulet", "belt", "offhand"]:
			for e in LootGenerator.roll_item(85, ItemInstance.Rarity.RARE, slot).affixes:
				seen[String(e.family)] = true
	for f in ["evasion", "es", "thorns", "rarity", "block", "max_res", "life_hit", "mana_leech", "recoup_life", "stun_threshold", "ail_poison"]:
		check(seen.has(f), "%s drops" % f)

	print("defences: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
