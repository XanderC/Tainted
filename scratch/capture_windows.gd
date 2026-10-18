extends Node2D
## Screenshots of every window and panel, to check their spacing and alignment in one go
## (saved as scratch/win_<name>.png). Needs a window; pass a phone's shape:
##   godot --path . --resolution 1600x720 res://scratch/capture_windows.tscn
## Pass `-- only=stats,shop` to capture just those.

var town
var menu: GameMenu
var only: PackedStringArray = []


func item(id: String, rarity := ItemInstance.Rarity.MAGIC) -> ItemInstance:
	var it := LootGenerator.roll_item(12, rarity, "")
	it.base = LootGenerator.base_by_id(id)
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	menu = town.menu
	var p: Player = town.player
	p.bag.clear()
	for id in ["greatsword", "chain_mail", "iron_helm", "tower_shield", "bone_ring", "small_life_flask", "rope_belt", "worn_boots"]:
		p.bag.add(item(id))
	p.equip_to(item("rusty_sword", ItemInstance.Rarity.RARE), "weapon", true)
	p.inventory_changed.emit()

	if _want("details"):
		menu.open("details")
		menu.select(p.inventory[0])
		await _shot("details")
	if _want("skills"):
		menu.open("skills")
		await _shot("skills")
	if _want("gems"):
		menu.open("gems")
		await _shot("gems")
	if _want("stats"):
		menu.open("details")
		menu.toggle_stats()
		await _shot("stats")
	menu.close()

	if _want("stash"):
		menu.open_vendor("stash")
		var stash := menu.current_panel() as StashPanel
		for t in ["items", "currency"]:
			stash.tab = t
			menu.show_panel("stash")
			await _shot("stash_" + t)
		menu.close()
	for v in ["shop", "smith", "jeweler"]:
		if _want(v):
			menu.open_vendor(v)
			await _shot(v)
			menu.close()

	if _want("tree"):
		town.skill_tree_ui.open()
		await _shot("tree")
		town.skill_tree_ui.close()
	if _want("rift"):
		town.rift_ui.open()
		await _shot("rift")
		town.rift_ui.close()
	if _want("upgrade"):
		town.upgrade_popup_ui.prompt_upgrade(item("greatsword", ItemInstance.Rarity.RARE), null)
		await _shot("upgrade")
		town.upgrade_popup_ui.close()
	if _want("talk"):
		for i in get_tree().get_nodes_in_group("interactables"):
			if String(i.prompt).contains("Stash"):
				p.global_position = i.global_position + Vector2(20, 10)
		await _shot("talk")
	if _want("intro"):
		town._show_hub_intro()
		await _shot("intro")
	if _want("charselect"):
		town.queue_free()
		await get_tree().process_frame
		var cl := CanvasLayer.new()  # a Control under a Node2D gets no screen rect to fill
		add_child(cl)
		cl.add_child(load("res://scenes/character_select.tscn").instantiate())
		await _shot("charselect")
	get_tree().quit(0)


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func _shot(n: String) -> void:
	for i in 5:
		await get_tree().process_frame
	await get_tree().create_timer(0.4, true, false, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/win_%s.png" % n))
	print("saved ", n)
