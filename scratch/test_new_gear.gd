extends Node2D
## Checks the hand crossbows and the shoulder slot: the bases exist with their art; a hand crossbow
## is one-handed (a shield fits beside it), needs Dexterity, is held on the hand crossbow rig, can use
## bow skills, others are told its style, a Scout can't take it, and its looks are its own group;
## shoulders go in their own paperdoll slot, are drawn on both arms on every rig, give armour, can
## be dyed and restyled, and are sent to others. With a window (--out=<folder>) it saves
## new_gear.png: figures wearing shoulders and holding hand crossbows on each rig.
##   godot --headless --path . res://scratch/test_new_gear.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func item(id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.ilvl = 1
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	var xbows := ["hand_crossbow", "iron_hand_crossbow", "bone_hand_crossbow", "horn_hand_crossbow", "gilded_hand_crossbow", "jade_hand_crossbow"]
	for id in xbows:
		var b := LootGenerator.base_by_id(id)
		check(b != null and b.weapon_type == "crossbow" and not b.two_handed, "%s is a one-handed crossbow" % id)
		check(b != null and b.bag_size() == Vector2i(2, 2) and b.icon != null and ResourceLoader.exists("res://assets/gear/weapon/%s/Sword.png" % id),
			"%s has its art and takes 2 x 2" % id)
	var shoulders := LootGenerator.SHOULDER_BASES.map(func(r): return r[0])
	check(shoulders.size() == 12, "12 shoulder pieces")
	for id in shoulders:
		var b := LootGenerator.base_by_id(id)
		check(b != null and b.slot == "shoulders" and b.implicit_stat == "armor" and b.icon != null, "%s is shoulder armour" % id)
		check(ResourceLoader.exists("res://assets/gear/shoulders/%s/Right Arm.png" % id) and ResourceLoader.exists("res://assets/gear/shoulders/%s/Left Arm.png" % id),
			"%s has its art for both arms" % id)
	check(Attributes.requirements(LootGenerator.base_by_id("jade_hand_crossbow")).has("dex"), "a hand crossbow needs Dexterity")
	check(Attributes.requirements(LootGenerator.base_by_id("void_spaulders")).has("str"), "heavy shoulders need Strength")
	check(RigSprite.weapon_style(LootGenerator.base_by_id("hand_crossbow")) == "handxbow" and RigSprite.weapon_style(LootGenerator.base_by_id("arbalest")) == "bow",
		"a hand crossbow's style is its own; a two-handed one stays a bow's")
	check(RigSprite.rig_for_weapon("hand_crossbow") == RigSprite.HANDXBOW_RIG, "held on the hand crossbow rig")
	check(RigSprite.rig_for_seen("anything", "handxbow") == RigSprite.HANDXBOW_RIG, "and others draw it there")
	check(Wardrobe.group_of_base(LootGenerator.base_by_id("hand_crossbow")) == "handxbow" and Wardrobe.exists("handxbow", "jade_hand_crossbow")
		and not Wardrobe.exists("bow", "jade_hand_crossbow") and not Wardrobe.exists("handxbow", "long_bow"), "hand crossbow looks are their own group")
	check(Wardrobe.exists("shoulders", "frost_spaulders") and Wardrobe.group(item("frost_spaulders")) == "shoulders", "shoulders have looks")

	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	GameState.level = 50
	GameState.attributes = {"str": 400, "dex": 400, "vit": 300, "ene": 300}
	p.refresh_attributes()
	p.bag.clear()
	var xb := item("gilded_hand_crossbow")
	p.pick_up(xb)
	p.equip_to(xb, "weapon")
	check(p.rig.rig_dir == RigSprite.HANDXBOW_RIG, "equipped: the hand crossbow rig")
	check(p.main_weapon_type() == "crossbow" and p.skill_block_reason(SkillTree.get_skill("power_shot")) == "", "bow skills work with it")
	check(Net.my_info().gear.weapon == ["gilded_hand_crossbow", "handxbow"], "others are told its style")
	var sh := item("buckler")
	p.pick_up(sh)
	p.equip_to(sh, "offhand")
	check(p.equipment.get("offhand") == sh and p.equipment.get("weapon") == xb, "a shield fits beside it")
	var armor0 := p.stats.get_stat("armor")
	var pd := item("frost_spaulders")
	p.pick_up(pd)
	check(p.equip_slot_for(pd) == "shoulders", "shoulders go in the shoulder slot")
	p.equip_to(pd, "shoulders")
	check(p.equipment.get("shoulders") == pd and p.stats.get_stat("armor") > armor0, "worn: more armour")
	check(p.rig.overlay_count("shoulders") == 2, "drawn on both arms")
	check(Net.my_info().gear.shoulders[0] == "frost_spaulders", "others are told")
	check(CharacterPanel.DOLL.has("shoulders"), "a paperdoll slot")
	check(pd.can_dye(), "they can be dyed")
	var had: Dictionary = GameState.hireling.duplicate(true)
	GameState.hireling = {"type": "scout", "name": "Test", "level": 50, "skin": "archer_1"}
	check(Hirelings.slot_block_reason(item("hand_crossbow"), "weapon") != "", "a Scout can't take a hand crossbow")
	check(Hirelings.slot_block_reason(item("arbalest"), "weapon") == "" or "Strength" in Hirelings.slot_block_reason(item("arbalest"), "weapon")
		or "Dexterity" in Hirelings.slot_block_reason(item("arbalest"), "weapon"), "but takes a two-handed one")
	GameState.hireling = had
	var saved := pd.to_dict()
	check(ItemInstance.from_dict(saved).base.slot == "shoulders", "saved and loaded")

	if out != "":
		town.queue_free()
		await get_tree().process_frame
		RenderingServer.set_default_clear_color(Color(0.36, 0.44, 0.33))
		var row := [["", RigSprite.SWORD_RIG, "iron_pauldrons", "Idle"], ["rusty_sword", RigSprite.SWORD_RIG, "gilded_pauldrons", "Slashing"],
			["hand_crossbow", RigSprite.HANDXBOW_RIG, "skull_pauldron", "Idle"], ["jade_hand_crossbow", RigSprite.HANDXBOW_RIG, "leaf_mantle", "Slashing"],
			["iron_hand_crossbow", RigSprite.HANDXBOW_RIG, "frost_spaulders", "Walking"], ["greatsword", RigSprite.TWOHAND_RIG, "warlord_pauldrons", "Slashing"],
			["war_spear", RigSprite.SPEAR_RIG, "void_spaulders", "Idle"], ["long_bow", RigSprite.ARCHER_RIG, "horned_skull_pauldron", "Idle"]]
		for i in row.size():
			var r := RigSprite.new()
			r.base_scale = 0.34
			r.weapon_from_gear = true
			r.rig_dir = row[i][1]
			r.position = Vector2(100 + i * 195, 390)
			add_child(r)
			Appearance.apply(r, Appearance.default_look("male" if i % 2 == 0 else "female"))
			r.set_gear("weapon", row[i][0])
			r.set_gear("chest", "chain_mail")
			r.set_gear("shoulders", row[i][2])
			r.play_loop(row[i][3])
		for k in 2:
			for f in 8 + k * 9:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out + "new_gear_%d.png" % k)
	print("new gear: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
