extends Node2D
## Checks the Wardrobe (armour, weapon and shield looks): picking up a piece unlocks its look, a
## unique's own look (once identified), giving a piece another look at the Dyer and putting it back,
## weapons keeping to their group (a bow looks like a bow), the look on the worn figure and in what
## others are sent, stats unchanged, and saving and loading. Run headless:
##   godot --headless --path . res://scratch/test_wardrobe.tscn
## With a window (--shot=<file>) it also saves a picture of the Dyer's Appearance tab.

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
	var ui: DyeUI = town.dye_ui
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	p.refresh_attributes()
	p.bag.clear()
	for slot in p.equipment.keys():
		p.unequip(slot)
	GameState.wardrobe = {}

	# The art behind the looks
	var sizes := {}
	for grp in Wardrobe.GROUPS:
		var n := Wardrobe.catalog(Wardrobe.folder(grp)).keys().filter(func(id): return Wardrobe.exists(grp, id)).size()
		sizes[grp] = n
		check(n >= {"shoulders": 12, "handxbow": 6}.get(grp, 20), "%s has its library of looks (%d)" % [grp, n])
	print("looks by group: ", sizes)
	check(Wardrobe.exists("helmet", "iron_helm") and Wardrobe.exists("chest", "chain_mail"), "armour bases are looks")
	check(Wardrobe.exists("melee", "rusty_sword") and Wardrobe.exists("bow", "long_bow") and Wardrobe.exists("shield", "buckler"),
		"weapon and shield bases are looks")
	check(not Wardrobe.exists("bow", "rusty_sword") and not Wardrobe.exists("melee", "long_bow"), "a bow and a sword can't swap looks")
	check(Wardrobe.exists("bow", "hunting_crossbow"), "a crossbow is in the bows' group")
	check(Wardrobe.group(item("bone_ring")) == "" and not Wardrobe.can_restyle(item("bone_ring")), "jewellery has no looks")
	var uniques := 0
	for uid in UniqueItems.LEGENDARIES.keys() + UniqueItems.SET_ITEMS.keys():
		var b := LootGenerator.base_by_id(String(UniqueItems.info_of(uid).base))
		var grp := Wardrobe.group_of_base(b)
		if grp != "":
			uniques += 1
			check(UniqueItems.look_of(uid) == "u_" + uid, "%s has its own look" % uid)
			check(Wardrobe.icon(grp, "u_" + uid) != null, "%s's look has its icon" % uid)
		else:
			check(UniqueItems.look_of(uid) == "", "%s (jewellery) has no look" % uid)
	check(uniques == 46, "46 uniques with looks (%d)" % uniques)
	check(Wardrobe.is_bow_art("u_windpiercer") and not Wardrobe.is_bow_art("u_maelstrom_edge"), "a unique bow's look is a bow")
	check(Wardrobe.look_name("helmet", "u_crown_of_wrath") == "Crown of Wrath", "a unique look goes by its name")
	check(Wardrobe.look_name("helmet", "iron_helm") == "Iron Helm", "a base look goes by the base's name")

	# Picking up unlocks
	var helm := item("iron_helm")
	var cap := item("leather_cap")
	check(not Wardrobe.has("helmet", "iron_helm"), "nothing unlocked yet")
	var said: Array = []
	GameState.looks_unlocked.connect(func(l): said.append_array(l))
	p.pick_up(helm)
	check(Wardrobe.has("helmet", "iron_helm"), "picking up a helmet unlocks its look")
	check(said.size() == 1 and said[0] == ["helmet", "iron_helm"], "and says so")
	p.pick_up(item("iron_helm"))
	check(Wardrobe.unlocked("helmet").count("iron_helm") == 1 and said.size() == 1, "a second one unlocks nothing new")
	p.pick_up(item("rusty_sword"))
	check(not GameState.wardrobe.has("weapon"), "weapons unlock nothing")

	# A unique: its own look once identified
	var crown := UniqueItems.make("crown_of_wrath", 30)
	crown.identified = false
	check(Wardrobe.own_look(crown) == "iron_helm", "an unidentified unique looks like its base")
	p.pick_up(crown)
	check(not Wardrobe.has("helmet", "u_crown_of_wrath"), "and doesn't give away its look")
	crown.identify()
	p.inventory_changed.emit()
	check(Wardrobe.has("helmet", "u_crown_of_wrath"), "identified, it unlocks its own look")
	check(Wardrobe.look_of(crown) == "u_crown_of_wrath", "and wears it")

	# Giving the cap another look
	p.pick_up(cap)
	p.equip_to(cap, "helmet")
	var armor_before := p.stats.get_stat("armor")
	ui.open()
	ui._mode = "look"
	ui._item = cap
	ui._where = "worn"
	ui._refresh()
	var shown := ui._looks.get_children().filter(func(c): return c.visible).size()  # (cleared ones go next frame)
	check(shown == Wardrobe.unlocked("helmet").size(),
		"the Appearance tab lists every unlocked helmet look (%d of %s)" % [shown, Wardrobe.unlocked("helmet")])
	ui._look = "u_crown_of_wrath"
	ui._apply_look()
	check(cap.look == "u_crown_of_wrath", "the cap now looks like the Crown of Wrath")
	check(is_equal_approx(p.stats.get_stat("armor"), armor_before), "its stats are the cap's own")
	check(p.rig.gear_id("helmet") == "u_crown_of_wrath", "the figure wears the crown")
	check(Net.my_info().gear.helmet[0] == "u_crown_of_wrath", "others are sent the crown's art")
	check(cap.get_tooltip().contains("Looks like Crown of Wrath"), "its card says what it looks like")
	ui._own_look()
	check(cap.look == "" and p.rig.gear_id("helmet") == "leather_cap", "back to its own look")
	ui._look = "iron_helm"
	ui._apply_look()
	ui._look = "leather_cap"
	ui._apply_look()
	check(cap.look == "", "picking its own look keeps none")
	ui._look = "iron_helm"
	ui._apply_look()

	# Saving and loading
	var d := cap.to_dict()
	check(String(d.get("look", "")) == "iron_helm", "the look is saved with the item")
	var back := ItemInstance.from_dict(d)
	check(back.look == "iron_helm", "and loaded")
	d["look"] = "no_such_thing"
	check(ItemInstance.from_dict(d).look == "", "an unknown look is dropped")
	var sw := item("rusty_sword").to_dict()
	sw["look"] = "iron_helm"
	check(ItemInstance.from_dict(sw).look == "", "a weapon can't look like a helmet")
	sw["look"] = "axe_3_4"
	check(ItemInstance.from_dict(sw).look == "axe_3_4", "but can like another weapon")
	# Weapons and shields
	var sword := item("rusty_sword")
	p.pick_up(sword)
	check(Wardrobe.has("melee", "rusty_sword"), "picking up a sword unlocks its look")
	var bow := item("long_bow")
	p.pick_up(bow)
	p.pick_up(item("hunting_crossbow"))
	check(Wardrobe.has("bow", "long_bow") and Wardrobe.has("bow", "hunting_crossbow"), "and a bow and crossbow theirs")
	p.pick_up(item("buckler"))
	check(Wardrobe.has("shield", "buckler"), "and a shield its")
	GameState.wardrobe["melee"].append("axe_3_4")
	GameState.wardrobe["bow"].append("elf_archer_1_bow")
	p.equip_to(sword, "weapon")
	var dmg := p.stats.get_stat("damage")
	ui._mode = "look"
	ui._refresh()
	check(ui._dyeable().any(func(e): return e.item == sword), "the Appearance tab lists the worn sword")
	ui._mode = "dye"
	check(not ui._dyeable().any(func(e): return e.item == sword), "the Dye tab doesn't")
	ui._mode = "look"
	ui._item = sword
	ui._where = "worn"
	ui._look = "axe_3_4"
	ui._apply_look()
	check(sword.look == "axe_3_4" and p.rig.gear_id("weapon") == "axe_3_4", "the sword now looks like an axe")
	check(is_equal_approx(p.stats.get_stat("damage"), dmg), "and still hits like the sword")
	check(Net.my_info().gear.weapon[0] == "axe_3_4", "others are sent the axe")
	p.equip_to(bow, "weapon")
	check(p.rig.rig_dir == RigSprite.ARCHER_RIG, "a bow in hand: the archer rig")
	ui._item = bow
	ui._look = "elf_archer_1_bow"
	ui._apply_look()
	check(p.rig.gear_id("weapon") == "elf_archer_1_bow" and p.rig.rig_dir == RigSprite.ARCHER_RIG, "the bow takes another bow's look")
	check(RigSprite.rig_for_weapon("elf_archer_1_bow") == RigSprite.ARCHER_RIG, "others draw that look on the archer rig too")
	check(RigSprite.rig_for_weapon("axe_3_4") == RigSprite.SWORD_RIG, "and a melee look on the sword rig")
	var looks_now := ui._looks.get_children().filter(func(c): return c.visible).size()
	check(looks_now == Wardrobe.unlocked("bow").size(), "the bow's looks are bows only (%d)" % looks_now)

	var saved := GameState.wardrobe.duplicate(true)
	check(Wardrobe.sanitize(saved).helmet == saved.helmet, "the wardrobe survives saving")
	var clean := Wardrobe.sanitize({"helmet": ["iron_helm", "bogus", 5], "melee": ["long_bow", "axe_3_4"], "weapon": ["x"]})
	check(clean.helmet == ["iron_helm"] and clean.melee == ["axe_3_4"] and not clean.has("weapon"), "a bad wardrobe is cleaned")

	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot != "":
		ui._mode = "look"
		ui._item = sword
		ui._look = "u_maelstrom_edge"
		GameState.wardrobe["melee"].append_array(["u_maelstrom_edge", "u_emberheart", "sword_7_5", "staff_7_5", "dagger_6_5"])
		ui._refresh()
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	ui.close()
	print("wardrobe: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
