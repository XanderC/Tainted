extends Node2D
## The stash's Gems and Runes tabs lay everything out in fixed places, like Path of Exile's: a row per gem type with
## its tiers along it (Chipped first), the rune ladder El to Zod in rows of eleven; what you don't own is faint,
## counts at the top left, and the Jeweler shows both. Takes scratch/stash_gems_layout.png / stash_runes_layout.png.
##   godot --path . --resolution 1600x720 res://scratch/test_stash_gems_runes.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _slots(panel: Node) -> Array:
	return panel.find_children("*", "DragSlot", true, false)


func _settle() -> void:
	for i in 5:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.gems = {"ruby_1": 5, "ruby_3": 2, "diamond_8": 1, "topaz_2": 12, "srune_el": 40, "srune_ber": 1}
	var menu: GameMenu = town.menu
	menu.open_vendor("stash")
	await _settle()

	# Gems tab
	menu.show_panel("gems")
	await _settle()
	var gp := menu.current_panel() as GemsPanel
	check(gp != null and gp.kind == "gems", "the Gems tab is the gems only")
	var cells := _slots(gp)
	check(cells.size() == GemDef.TYPES.size() * GemDef.MAX_TIER, "a place for every gem: %d (%d)" % [GemDef.TYPES.size() * GemDef.MAX_TIER, cells.size()])
	var ys := {}
	var xs := {}
	for c in cells:
		ys[snappedf(c.global_position.y, 1.0)] = true
		xs[snappedf(c.global_position.x, 1.0)] = true
	check(ys.size() == GemDef.TYPES.size(), "a row for each gem type (%d)" % ys.size())
	check(xs.size() == GemDef.MAX_TIER, "its tiers along it (%d)" % xs.size())
	var faint := cells.filter(func(c): return c.modulate.a < 0.35).size()
	check(faint == cells.size() - 4, "the 36 you don't own are faint (%d of %d)" % [faint, cells.size()])
	var owned := cells.filter(func(c): return not c.payload.is_empty())
	check(owned.size() == 4 and owned.all(func(c): return c.payload.get("from", "") == "pouch"), "only the owned ones can be dragged (%d)" % owned.size())
	check(cells[0].payload.get("gem_id", "") == "ruby_1" and cells[2].payload.get("gem_id", "") == "ruby_3", "Chipped Ruby first, then along the tiers")
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/stash_gems_layout.png"))

	# Runes tab
	menu.show_panel("runes")
	await _settle()
	var rp := menu.current_panel() as GemsPanel
	check(rp != null and rp.kind == "runes" and rp != gp, "the Runes tab is its own panel")
	var rcells := _slots(rp)
	check(rcells.size() == SocketRune.LADDER.size(), "a place for every rune: %d" % rcells.size())
	var rys := {}
	for c in rcells:
		rys[snappedf(c.global_position.y, 1.0)] = true
	check(rys.size() == ceili(float(SocketRune.LADDER.size()) / GemsPanel.RUNE_COLS), "rows of %d (%d rows)" % [GemsPanel.RUNE_COLS, rys.size()])
	check(rcells[0].tooltip_text.begins_with("El") and rcells[rcells.size() - 1].tooltip_text.begins_with("Zod"), "El first, Zod last (%s .. %s)" % [rcells[0].tooltip_text, rcells[rcells.size() - 1].tooltip_text])
	var rowned := rcells.filter(func(c): return not c.payload.is_empty())
	check(rowned.size() == 2, "two runes owned (%d)" % rowned.size())
	check(rp.panel_title() == "🔷 Runes (41)" and gp.panel_title() == "💎 Gems (20)", "tab titles count their own (%s, %s)" % [rp.panel_title(), gp.panel_title()])
	var vis := get_viewport().get_visible_rect()
	check(vis.encloses(Rect2(rcells[0].global_position, rcells[0].size)), "the runes are on screen")
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/stash_runes_layout.png"))
	menu.close()

	# The Jeweler shows both, and combining still works from a gem
	menu.open_vendor("jeweler")
	await _settle()
	var jp := menu.current_panel() as GemsPanel
	check(jp != null and jp.jeweler and jp.kind == "", "the Jeweler is the both-pools panel")
	check(_slots(jp).filter(func(c): return c.custom_minimum_size.x < 100.0).size() >= GemDef.TYPES.size() * GemDef.MAX_TIER + SocketRune.LADDER.size(), "with the gems and the runes")
	menu.close()
	print("stash gems and runes: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
