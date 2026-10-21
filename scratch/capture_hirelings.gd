extends Node2D
## Screenshots of hirelings and attributes (saved as scratch/hl_<name>.png): the Captain in town,
## the hiring window, the inventory's Hireling tab at the stash, the attributes on the stats
## screen, a hireling fighting, and an archer. Needs a window; pass a phone's shape:
##   godot --path . --resolution 1600x720 res://scratch/capture_hirelings.tscn

var town
var menu: GameMenu


func item(id: String, rarity := ItemInstance.Rarity.MAGIC) -> ItemInstance:
	var it := LootGenerator.roll_item(12, rarity, "")
	it.base = LootGenerator.base_by_id(id)
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	GameState.level = 14
	GameState.attributes = {}
	GameState._fix_attribute_points()
	GameState.add_attribute("str", 8)
	GameState.quests["a1_into_the_wastes"] = {"state": Quests.DONE}
	GameState.orbs["transmute"] = 40
	GameState.orbs["alteration"] = 40
	GameState.runes = {"rune_fire": 2, "rune_frost": 1, "rune_vampiric": 1, "rune_echo": 1, "rune_nova": 1}
	town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	menu = town.menu
	var p: Player = town.player
	p.bag.clear()
	for id in ["broad_sword", "kite_shield", "chain_mail", "iron_helm", "long_bow", "leather_gloves", "medium_life_flask", "granite_flask"]:
		p.bag.add(item(id))
	p.inventory_changed.emit()

	# The Captain in town
	p.global_position = town.CAPTAIN + Vector2(-120, 60)
	await _shot("captain")

	# Hiring
	town.hire_ui.open()
	await _shot("hire")
	var c: Dictionary = Hirelings.candidates("sellsword")[0]
	Hirelings.hire(p, c)
	town.hire_ui._refresh()
	await _shot("hired")
	town.hire_ui.close()
	for slot in ["weapon", "offhand", "chest", "helmet"]:
		for it in p.inventory:
			if it.base.slot == slot and Hirelings.slot_block_reason(it, slot) == "":
				Hirelings.equip_from_bag(p, it, slot)
				break
	for it in p.inventory.duplicate():
		if it.is_flask():
			Hirelings.equip_flask_from_bag(p, it, 0 if Hirelings.flask(0) == null else 1)
	Hirelings.socket_support(0, 0, "rune_fire")
	Hirelings.socket_support(1, 0, "rune_vampiric")

	# The Hireling tab, at the stash (supports can be linked there)
	menu.open_vendor("stash")
	menu.show_panel("hireling")
	await _shot("panel")
	menu.close()
	menu.open("details")
	menu.toggle_stats()
	await _shot("stats")
	menu.close()

	# The portrait at the top left, and tapping it
	await _shot("portrait")
	for c2 in town.get_children():
		if c2 is CanvasLayer:
			for n in c2.find_children("*", "HirelingPortrait", true, false):
				n.on_open.call()
	await _shot("portrait_tap")
	var hp_panel := menu.current_panel() as HirelingPanel
	Input.warp_mouse(Vector2(1150, 520))  # where a finger would tap in the bag
	for it in p.inventory:
		if it.base.weapon_type == "bow":
			menu.select(it)
			break
	await _shot("tip_bag")
	Input.warp_mouse(Vector2(200, 300))
	hp_panel._show_gear_tip("weapon")
	await _shot("tip_gear")
	hp_panel._item_tip.close()
	hp_panel._stats_mode = true
	Hirelings.add_attribute("str", 6)
	hp_panel.refresh()
	await _shot("hl_stats")
	hp_panel._stats_mode = false
	menu.close()
	menu.open_vendor("stash")
	menu.show_panel("hireling")
	await _shot("panel_stash")
	menu.back()
	await _shot("back_to_stash")
	menu.close()

	# Fighting beside you
	await get_tree().physics_frame
	p.can_fight = true
	p.global_position = Vector2(0, 360)
	if is_instance_valid(Hirelings.node):
		Hirelings.node.global_position = p.global_position + Vector2(-60, 30)
	for i in 5:
		var e := Enemy.new()
		e.target = p
		e.max_hp = 4000.0
		e.touch_damage = 2.0
		e.set_kind(["zombie", "skeleton", "goblin"][i % 3])
		e.position = p.global_position + Vector2(160 + i * 30, -60 + i * 40)
		town.add_child(e)
	for i in 40:
		await get_tree().physics_frame
	await _shot("fight")

	# An archer
	Hirelings.hire(p, Hirelings.candidates("scout")[0])
	await get_tree().physics_frame
	for it in p.inventory:
		if it.base.weapon_type == "bow":
			Hirelings.equip_from_bag(p, it, "weapon")
			break
	for i in 50:
		await get_tree().physics_frame
	await _shot("archer")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 5:
		await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/hl_%s.png" % n))
	print("saved ", n)
