extends Node2D
## Checks dyeing: which gear can be dyed, the Dyer's price, the dye on a worn piece, in the bag and on
## the hireling's gear, taking it off, saving and loading, and a bad dye id being ignored. Run headless:
##   godot --headless --path . res://scratch/test_dye.tscn

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
	GameState.attributes = {"str": 300, "dex": 300}
	p.refresh_attributes()
	p.bag.clear()
	GameState.orbs["transmute"] = 10
	Hirelings.dismiss(p)

	# The palette
	check(DyeDB.PALETTE.size() == 30 and DyeDB.ids().size() == 30, "30 dyes")
	check(DyeDB.PALETTE.all(func(d): return DyeDB.icon(d[0]) != null), "each has its paint icon")
	check(DyeDB.PALETTE.size() % DyeDB.COLUMNS == 0, "rows of ten")
	check(DyeDB.has("crimson") and not DyeDB.has("") and not DyeDB.has("nonsense"), "dye ids")

	# What can be dyed
	var helm := item("iron_helm")
	var mail := item("chain_mail")
	var sword := item("rusty_sword")
	var ring := item("bone_ring")
	var boots := item("worn_boots")
	check(helm.can_dye() and mail.can_dye(), "helmets and body armour can be dyed")
	check(not sword.can_dye() and not ring.can_dye() and not boots.can_dye(), "weapons, rings and boots can't (you can't see them)")

	# The Dyer's window lists them: worn, then the bag
	p.bag.add(helm)
	p.bag.add(mail)
	p.bag.add(sword)
	var worn_helm := item("knights_helm")
	p.bag.add(worn_helm)
	check(p.equip_to(worn_helm, "helmet"), "wear a helmet")
	var listed := ui._dyeable().map(func(e): return e.item)
	check(listed.has(worn_helm) and listed.has(helm) and listed.has(mail) and not listed.has(sword), "the Dyer lists the helmets and armour (%d)" % listed.size())
	check(ui._dyeable()[0].where == "worn", "worn gear first")

	# Dyeing a piece in the bag, through the window
	ui.open()
	ui._item = mail
	ui._where = "bag"
	ui._paint = "emerald"
	var orbs0 := GameState.orb_count("transmute")
	ui._apply()
	check(mail.dye == "emerald", "the armour in the bag is dyed Emerald")
	check(GameState.orb_count("transmute") == orbs0 - 1, "it cost an Orb of Transmutation")
	check(mail.get_tooltip().contains("Dyed Emerald"), "its tooltip says so")
	ui._paint = "emerald"
	ui._refresh()
	check(ui._dye_btn.disabled, "the same dye again is not offered")
	GameState.orbs["transmute"] = 0
	ui._paint = "crimson"
	ui._refresh()
	check(ui._dye_btn.disabled, "and without an orb you can't dye")
	GameState.orbs["transmute"] = 5

	# A worn piece: the character is redrawn in the dye
	ui._item = worn_helm
	ui._where = "worn"
	ui._paint = "crimson"
	ui._apply()
	check(worn_helm.dye == "crimson", "the worn helmet is dyed")
	check(p.rig.gear_dye("helmet") == "crimson", "and the character wears it dyed")
	check(p.rig.overlay_count("helmet") > 0, "the helmet is still drawn")
	var sprite_dyed := false
	for ch in p.rig.get_children():
		if ch is Sprite2D and ch.material is ShaderMaterial and (ch.material as ShaderMaterial).get_shader_parameter("dye") == DyeDB.color("crimson"):
			sprite_dyed = true
	check(sprite_dyed, "its sprite has the dye's recolour")
	var chest_item := item("chain_mail")
	p.bag.add(chest_item)
	check(p.equip_to(chest_item, "chest"), "wear armour")
	ui._item = chest_item
	ui._where = "worn"
	ui._paint = "sapphire"
	ui._apply()
	check(p.rig.gear_dye("chest") == "sapphire" and p.rig.overlay_count("chest") >= 3, "armour: body and both arms dyed")
	var dyed_parts := 0
	for ch in p.rig.get_children():
		if ch is Sprite2D and ch.material is ShaderMaterial:
			dyed_parts += 1
	check(dyed_parts >= 4, "helmet and armour sprites carry the recolour (%d)" % dyed_parts)

	# Taking it off is free
	var o := GameState.orb_count("transmute")
	ui._item = worn_helm
	ui._where = "worn"
	ui._remove()
	check(worn_helm.dye == "" and p.rig.gear_dye("helmet") == "", "taking the dye off restores its own colours")
	check(GameState.orb_count("transmute") == o, "and it is free")

	# The dye stays with the item through saving, and a bad one is dropped
	var d := mail.to_dict()
	check(String(d.dye) == "emerald", "saved with the item")
	check(ItemInstance.from_dict(d).dye == "emerald", "and loaded back")
	d["dye"] = "nonsense"
	check(ItemInstance.from_dict(d).dye == "", "an unknown dye is ignored")
	var sd := sword.to_dict()
	sd["dye"] = "crimson"
	check(ItemInstance.from_dict(sd).dye == "", "a weapon can't carry a dye")
	check(ItemInstance.from_dict(item("iron_helm").to_dict()).dye == "", "undyed items load undyed")

	# The recolour keeps the art's own brightness: a dark piece and a bright one both come out as the dye
	var l_leather := DyeDB.mean_lum(LootGenerator.base_by_id("leather_cap").icon)
	var l_steel := DyeDB.mean_lum(LootGenerator.base_by_id("iron_helm").icon)
	check(l_leather > 0.0 and l_steel > 0.0 and absf(l_steel - l_leather) > 0.02, "each piece's own brightness is measured (%.2f, %.2f)" % [l_leather, l_steel])

	# Your hireling's gear
	var hire: Dictionary = Hirelings.candidates("sellsword")[0]
	GameState.orbs["transmute"] = 20
	check(Hirelings.hire(p, hire), "hire a Sellsword")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hh := item("horned_cap")
	p.bag.add(hh)
	GameState.attributes = {"str": 300}
	check(Hirelings.equip_from_bag(p, hh, "helmet"), "it wears a helmet")
	check(ui._dyeable().any(func(e): return e.item == hh and e.where == "hireling"), "the Dyer lists its helmet too")
	ui._item = hh
	ui._where = "hireling"
	ui._paint = "amber"
	ui._apply()
	check(hh.dye == "amber", "its helmet is dyed")
	await get_tree().physics_frame
	check(Hirelings.node.rig.gear_dye("helmet") == "amber", "and it wears it dyed")
	var saved := GameState._hireling_save()
	check(String(saved.gear.helmet.dye) == "amber", "saved with its gear")

	print("test_dye: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
