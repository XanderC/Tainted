extends Node2D
## Checks the weapon rigs: two-handed swords, axes and mauls put the player (and a hireling dressed in
## its own gear) on the two-handed rig, spears on the spear rig, daggers on the dagger rig, the rest on
## the sword rig, a look doesn't change it, and others are told the style. With a window
## (--shot=<png>) it also saves pictures of figures holding them, idle, walking and mid-attack.
##   godot --headless --path . res://scratch/test_twohand.tscn

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
	var T := RigSprite.TWOHAND_RIG
	check(RigData.load_rig(T) != null, "the two-handed rig loads")
	var rd := RigData.load_rig(T)
	var sword_rd := RigData.load_rig(RigSprite.SWORD_RIG)
	check(rd.animations.keys() == sword_rd.animations.keys(), "it has every animation the sword rig has")
	for id in ["greatsword", "reaver_blade", "battle_axe", "despot_axe", "war_maul", "colossus_mallet"]:
		check(RigSprite.rig_for_weapon(id) == T, "%s is held in both hands" % id)
	for id in ["rusty_sword", "hand_axe", "iron_mace", "oak_staff"]:
		check(RigSprite.rig_for_weapon(id) == RigSprite.SWORD_RIG, "%s is on the sword rig" % id)
	for id in ["wooden_spear", "dragon_spear"]:
		check(RigSprite.rig_for_weapon(id) == RigSprite.SPEAR_RIG, "%s thrusts (the spear rig)" % id)
	for id in ["dagger", "skean"]:
		check(RigSprite.rig_for_weapon(id) == RigSprite.DAGGER_RIG, "%s stabs (the dagger rig)" % id)
	for r in [RigSprite.SPEAR_RIG, RigSprite.DAGGER_RIG]:
		check(RigData.load_rig(r) != null and RigData.load_rig(r).animations.keys() == sword_rd.animations.keys(),
			"%s loads with every animation" % r)
	check(RigSprite.rig_for_weapon("long_bow") == RigSprite.ARCHER_RIG, "a bow is on the archer rig")
	check(RigSprite.rig_for_seen("dagger_6_5", "2h") == T and RigSprite.rig_for_seen("greatsword", "") == RigSprite.SWORD_RIG,
		"another player's rig follows their style, not the look")
	check(RigSprite.rig_for_seen("axe_3_4", "spear") == RigSprite.SPEAR_RIG and RigSprite.rig_for_seen("x", "dagger") == RigSprite.DAGGER_RIG,
		"a spear's and a dagger's style")
	check(RigSprite.rig_for_seen("elf_archer_1_bow", "") == RigSprite.ARCHER_RIG, "a bow look is on the archer rig")

	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	GameState.attributes = {"str": 400, "dex": 400, "vit": 300, "ene": 300}
	p.refresh_attributes()
	var gs := item("greatsword")
	p.bag.clear()
	p.pick_up(gs)
	p.equip_to(gs, "weapon")
	check(p.rig.rig_dir == T, "a greatsword in hand: the two-handed rig")
	check(p.rig.gear_id("weapon") == "greatsword", "holding it")
	check(Net.my_info().gear.weapon == ["greatsword", "2h"], "others are told it's two-handed")
	gs.look = "dagger_6_5"
	p.modify_item(gs, func(): pass)
	check(p.rig.rig_dir == T and p.rig.gear_id("weapon") == "dagger_6_5", "a dagger's look, still in both hands")
	var sw := item("rusty_sword")
	p.pick_up(sw)
	p.equip_to(sw, "weapon")
	check(p.rig.rig_dir == RigSprite.SWORD_RIG, "a one-handed sword: back to the sword rig")
	check(Net.my_info().gear.weapon == ["rusty_sword", ""], "and others are told")
	var sp := item("war_spear")
	p.pick_up(sp)
	p.equip_to(sp, "weapon")
	check(p.rig.rig_dir == RigSprite.SPEAR_RIG and Net.my_info().gear.weapon == ["war_spear", "spear"], "a spear: the spear rig, and others are told")
	var dg := item("stiletto")
	p.pick_up(dg)
	p.equip_to(dg, "weapon")
	check(p.rig.rig_dir == RigSprite.DAGGER_RIG and Net.my_info().gear.weapon == ["stiletto", "dagger"], "a dagger: the dagger rig")

	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot != "":
		town.queue_free()
		await get_tree().process_frame
		RenderingServer.set_default_clear_color(Color(0.36, 0.44, 0.33))
		var row := [["greatsword", "Idle", T], ["battle_axe", "Slashing", T], ["war_maul", "Slashing", T],
			["war_spear", "Idle", RigSprite.SPEAR_RIG], ["dragon_spear", "Slashing", RigSprite.SPEAR_RIG],
			["stiletto", "Idle", RigSprite.DAGGER_RIG], ["skean", "Slashing", RigSprite.DAGGER_RIG]]
		var figs: Array = []
		for i in row.size():
			var r := RigSprite.new()
			r.base_scale = 0.34
			r.weapon_from_gear = true
			r.rig_dir = row[i][2]
			r.position = Vector2(110 + i * 215, 380)
			add_child(r)
			Appearance.apply(r, Appearance.default_look("male" if i % 2 == 0 else "female"))
			r.set_gear("weapon", row[i][0])
			r.set_gear("chest", "battle_plate")
			r.set_gear("gloves", "iron_gauntlets")
			r.play_loop(row[i][1])
			figs.append(r)
		for k in 3:
			for f in 7 + k * 5:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_%d.png" % k))
	print("two-handed: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
