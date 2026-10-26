extends Node2D
## Screenshots of cards shown where something is tapped (scratch/gemtip_<name>.png): skill and
## support gems on the Skills panel, a socket gem and a rune on the Gems tab, an orb at the stash.
##   godot --path . --resolution 1600x720 res://scratch/capture_gem_tips.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: GameMenu = town.menu
	menu.open()
	await get_tree().process_frame
	var panel := menu.current_panel() as SkillGemsPanel
	Input.warp_mouse(Vector2(95, 175))
	panel._select({"type": "skill", "id": GameState.slot_skill(0), "slot": 0})
	await _shot("skill")
	var sup := GameState.slot_supports(0)
	if not sup.is_empty():
		Input.warp_mouse(Vector2(172, 175))
		panel._select({"type": "support", "id": String(sup[0]), "slot": 0})
		await _shot("support")
	menu.show_panel("gems")
	var gp := menu.current_panel() as GemsPanel
	var gem := ""
	var rune := ""
	for gid in GemDef.all_ids():
		if GemDef.info(gid).get("rune", false):
			if rune == "":
				rune = gid
		elif gem == "":
			gem = gid
	Input.warp_mouse(Vector2(300, 300))
	gp.show_gem_tip(gem)
	await _shot("gem")
	gp.show_gem_tip(rune)
	await _shot("rune")
	menu.close()
	menu.open_vendor("stash")
	var st := menu.current_panel() as StashPanel
	st.tab = "currency"
	menu.show_panel("stash")
	Input.warp_mouse(Vector2(200, 560))
	st.show_orb_tip("transmute")
	await _shot("orb")
	get_tree().quit()


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/gemtip_%s.png" % n))
	print("saved ", n)
