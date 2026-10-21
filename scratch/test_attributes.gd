extends Node2D
## Checks attributes and gear requirements: points per level, what a point adds, requirements from
## a base's kind and drop level, gear that can't be put on short of them, worn gear that stops
## giving stats when they are taken back, and older saves getting their points. Run headless:
##   godot --headless --path . res://scratch/test_attributes.tscn

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
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	p._sync_gear_visuals()
	GameState.level = 1
	GameState.xp = 0.0
	GameState.attributes = {}
	GameState.attr_points = 0
	p.refresh_attributes()

	# Points per level
	GameState.add_xp(GameState.xp_to_next(1) + GameState.xp_to_next(2) + 1.0)
	check(GameState.level == 3, "two levels gained (%d)" % GameState.level)
	check(GameState.attr_points == 10, "5 attribute points a level (%d)" % GameState.attr_points)
	check(GameState.attribute_total("str") == 25, "a warrior starts with 25 Strength")

	# What a point adds
	var dmg0 := p.stats.get_stat("damage")
	var life0 := p.stats.get_stat("max_life")
	var res0 := p.max_resource()
	check(GameState.add_attribute("str", 2), "add two Strength")
	check(absf(p.stats.get_stat("damage") - dmg0 * 1.02) < 0.01, "2 Strength = +2%% damage (%.2f -> %.2f)" % [dmg0, p.stats.get_stat("damage")])
	check(GameState.add_attribute("vit"), "add a Vitality")
	check(absf(p.stats.get_stat("max_life") - (life0 + 4.0)) < 0.01, "a Vitality = +4 life")
	check(GameState.add_attribute("ene"), "add an Energy")
	check(absf(p.max_resource() - (res0 + 1.0)) < 0.01, "an Energy = +1 Adrenaline")
	check(GameState.attr_points == 6, "4 of 10 points spent (%d left)" % GameState.attr_points)
	check(not GameState.add_attribute("dex", 7), "can't add more points than you have")
	GameState.reset_attributes()
	check(GameState.attr_points == 10 and GameState.attribute_points_spent() == 0, "reset gives every point back")
	check(absf(p.stats.get_stat("damage") - dmg0) < 0.01, "and their bonuses go")

	# Requirements from the base
	var req := Attributes.requirements(LootGenerator.base_by_id("chain_mail"))
	check(req.get("str", 0) == 26 and not req.has("dex"), "Chain Mail needs 26 Strength (%s)" % [req])
	check(Attributes.requirements(LootGenerator.base_by_id("leather_cap")).is_empty(), "a Leather Cap needs nothing")
	check(Attributes.requirements(LootGenerator.base_by_id("bone_ring")).is_empty(), "rings need nothing")
	var dagger := Attributes.requirements(LootGenerator.base_by_id("stiletto"))
	check(dagger.has("dex") and not dagger.has("str"), "daggers want Dexterity (%s)" % [dagger])
	var high := Attributes.requirements(LootGenerator.base_by_id("despot_axe"))
	var low := Attributes.requirements(LootGenerator.base_by_id("battle_axe"))
	check(int(high.get("str", 0)) > int(low.get("str", 0)), "deeper bases need more (%s vs %s)" % [high, low])
	var staff := Attributes.requirements(LootGenerator.base_by_id("void_staff"))
	check(staff.has("ene"), "staves want Energy (%s)" % [staff])

	# Can't put on gear you fall short of
	var mail := item("chain_mail")
	p.bag.add(mail)
	check(not p.can_equip(mail), "25 Strength can't wear Chain Mail")
	check(p.equip_block_reason(mail).begins_with("Requires 26 Strength"), "says why (%s)" % p.equip_block_reason(mail))
	check(not p.equip_to(mail, "chest"), "equipping it fails")
	check(GameState.add_attribute("str"), "add a Strength")
	check(p.can_equip(mail), "26 Strength can")
	var armor0 := p.stats.get_stat("armor")
	check(p.equip_to(mail, "chest"), "put it on")
	var armor1 := p.stats.get_stat("armor")
	check(armor1 > armor0, "its armour counts (%.0f -> %.0f)" % [armor0, armor1])

	# Worn gear falls short: it stays on but gives nothing, then works again
	GameState.reset_attributes()
	check(p.equipment.get("chest") == mail, "taking the point back leaves it worn")
	check(not p.gear_active(mail), "but inactive")
	check(absf(p.stats.get_stat("armor") - armor0) < 0.01, "giving no armour (%.0f)" % p.stats.get_stat("armor"))
	GameState.add_attribute("str")
	check(p.gear_active(mail) and absf(p.stats.get_stat("armor") - armor1) < 0.01, "a point back and it works again")
	GameState.add_attribute("str")
	GameState.reset_attributes()
	GameState.add_attribute("str")
	check(absf(p.stats.get_stat("armor") - armor1) < 0.01, "on and off again never counts it twice (%.0f)" % p.stats.get_stat("armor"))
	GameState.reset_attributes()
	p.modify_item(mail, func(): mail.quality = 5)
	check(absf(p.stats.get_stat("armor") - armor0) < 0.01, "changing an inactive item doesn't switch it back on")
	check(p.unequip("chest"), "take it off")
	check(absf(p.stats.get_stat("armor") - armor0) < 0.01, "and nothing of it is left")

	# Older saves: every point a level brought, none added yet
	GameState.level = 12
	GameState.attributes = {}
	GameState._fix_attribute_points()
	check(GameState.attr_points == 55, "a level 12 save from before attributes gets 55 points (%d)" % GameState.attr_points)
	GameState.attributes = {"str": 500}
	GameState._fix_attribute_points()
	check(GameState.attribute_points_spent() == 0 and GameState.attr_points == 55, "more than the level allows is reset")

	print("test_attributes: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
