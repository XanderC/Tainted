extends Node2D
## Checks the ailments monsters can give you (stun, freeze, bleed, poison, ignite, shock, curse), what each does,
## "reduced duration", and that the matching charm stops each one. Run headless:
##   godot --headless --path . res://scratch/test_ailments.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func step(p: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		p._process_flasks(0.05)
		t += 0.05


func charm(id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.ilvl = 60
	it.display_name = it.base.display_name
	it.refill()
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	p.charms = [null, null, null]
	var max_life := p.stats.get_stat("max_life")
	p.hp = max_life

	# --- stun and freeze: you can neither move nor use a skill ---
	check(not p.is_helpless(), "free to begin with")
	check(p.inflict("stun"), "a stun lands")
	check(p.has_ailment("stun") and p.is_helpless(), "stunned: helpless")
	var cd0: float = p._cooldowns[0]
	p.use_skill(0)
	check(p._cooldowns[0] == cd0, "no skill while stunned")
	step(p, 0.8)
	check(not p.has_ailment("stun") and not p.is_helpless(), "the stun passes (0.7s)")
	check(not p.inflict("freeze"), "no freeze straight after a stun: a moment's grace")
	step(p, 2.1)
	check(p.inflict("freeze") and p.is_helpless(), "frozen: helpless")
	step(p, 1.2)
	check(not p.is_helpless(), "the freeze passes (1.1s)")

	# --- a big hit stuns ---
	step(p, 2.1)
	p.hp = max_life
	p.take_damage(max_life * 0.3, RuneDef.DamageType.PHYSICAL)
	check(p.has_ailment("stun"), "a hit of 30%% of your life stuns")
	step(p, 1.0)
	p.stats.add_mod("stun_threshold", StatBlock.ModType.FLAT, max_life, "test")
	p.hp = max_life
	p.take_damage(max_life * 0.3, RuneDef.DamageType.PHYSICAL)
	check(not p.has_ailment("stun"), "stun threshold keeps it from stunning")
	p.stats.remove_source("test")

	# --- damage over time: bleed, poison, ignite ---
	for pair in [["bleed", RuneDef.DamageType.PHYSICAL], ["poison", RuneDef.DamageType.CHAOS], ["ignite", RuneDef.DamageType.FIRE]]:
		p.hp = max_life
		p._ail.clear()
		p._ail_dps.clear()
		check(p.inflict(pair[0], 100.0), "%s lands" % pair[0])
		var before := p.hp
		step(p, 6.0)
		var share: float = Player.DOT_SHARE[pair[0]] * 100.0
		check(absf((before - p.hp) - share) < 3.0, "%s deals %.0f%% of the hit over its time (%.1f of %.1f)" % [pair[0], Player.DOT_SHARE[pair[0]] * 100.0, before - p.hp, share])
		check(not p.has_ailment(pair[0]), "%s ends" % pair[0])
	p.stats.add_mod("armor", StatBlock.ModType.FLAT, 400.0, "test")
	p.hp = max_life
	p.inflict("bleed", 100.0)
	step(p, 5.0)
	check(max_life - p.hp > 37.0, "armour does not stop a bleed (%.1f)" % (max_life - p.hp))
	p.stats.remove_source("test")
	p._ail.clear()
	p._ail_dps.clear()

	# --- fire resistance helps against a burn ---
	p.stats.add_mod("res_fire", StatBlock.ModType.FLAT, 0.5, "test")
	p.hp = max_life
	p.inflict("ignite", 100.0)
	step(p, 5.0)
	check(max_life - p.hp < 17.0, "50%% fire resistance halves an ignite (%.1f)" % (max_life - p.hp))
	p.stats.remove_source("test")
	p._ail.clear()

	# --- shock: more damage taken ---
	p.hp = max_life
	p.take_damage(10.0, RuneDef.DamageType.PHYSICAL)
	var plain := max_life - p.hp
	p.hp = max_life
	p._ail.clear()
	p.inflict("shock")
	p.take_damage(10.0, RuneDef.DamageType.PHYSICAL)
	var shocked := max_life - p.hp
	check(absf(shocked / plain - 1.2) < 0.05, "shocked: 20%% more damage (%.2f)" % (shocked / plain))
	step(p, 4.2)
	check(not p.has_ailment("shock"), "shock ends")

	# --- curse: you deal less ---
	var dmg0 := p.stats.get_stat("damage")
	p.inflict("curse")
	check(absf(p.stats.get_stat("damage") - dmg0 * 0.8) < 0.01, "cursed: 20%% less damage (%.1f)" % p.stats.get_stat("damage"))
	step(p, 5.2)
	check(absf(p.stats.get_stat("damage") - dmg0) < 0.01, "and back after 5s")

	# --- reduced duration ---
	p.stats.add_mod("ail_freeze", StatBlock.ModType.FLAT, 0.5, "test")
	p.inflict("freeze")
	check(absf(float(p._ail.freeze) - 0.55) < 0.001, "50%% reduced freeze duration (%.2f)" % float(p._ail.freeze))
	p.stats.remove_source("test")
	step(p, 1.0)

	# --- a charm for each stops it ---
	var pairs := [["stone_charm", "stun"], ["thawing_charm", "freeze"], ["staunching_charm", "bleed"], ["antidote_charm", "poison"],
		["dousing_charm", "ignite"], ["grounding_charm", "shock"], ["cleansing_charm", "curse"]]
	var belt := ItemInstance.new()
	belt.base = LootGenerator.base_by_id("rope_belt")
	belt.ilvl = 60
	p.equip_to(belt, "belt", true)
	for pr in pairs:
		p._ail.clear()
		p._ail_dps.clear()
		var c := charm(pr[0])
		p.charms = [c, null, null]
		p._ail_grace = 0.0
		check(not p.inflict(pr[1], 50.0) and not p.has_ailment(pr[1]), "%s stops %s" % [pr[0], pr[1]])
		check(c.charges_now() < float(c.max_charges()), "and spent its charges")
		check(not p.inflict(pr[1], 50.0), "and keeps it off while it lasts")
		step(p, 3.2)
		c.charges = 0.0
		p._ail_grace = 0.0
		check(p.inflict(pr[1], 50.0), "with no charges left %s lands" % pr[1])
		p._ail.clear()
		p._ail_dps.clear()
		step(p, 0.1)

	# --- monsters that curse ---
	check(bool(MonsterKinds.KINDS["veil_cultist"].get("curses", false)), "Veil Cultists curse")
	check(not bool(MonsterKinds.KINDS["zombie"].get("curses", false)) if MonsterKinds.KINDS.has("zombie") else true, "zombies do not")

	print("ailments: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
