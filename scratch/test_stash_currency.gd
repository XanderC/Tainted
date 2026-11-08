extends Node2D
## The stash's Currency tab lays every orb out in a fixed place, in groups, like Path of Exile's: each orb
## in CraftingDB.STASH_LAYOUT exactly once (and any forgotten one still shows), the ones you have none of
## faint, counts at the top left. Takes scratch/stash_currency_layout.png.
##   godot --path . --resolution 1600x720 res://scratch/test_stash_currency.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	# The layout covers every orb once
	var seen := {}
	for g in CraftingDB.stash_groups():
		for id in g[1]:
			check(CraftingDB.ORBS.has(id), "%s is an orb" % id)
			check(not seen.has(id), "%s is in one place only" % id)
			seen[id] = true
		check(g[1].size() > 0, "group %s has orbs" % g[0])
	check(seen.size() == CraftingDB.ORBS.size(), "every orb has a place (%d of %d)" % [seen.size(), CraftingDB.ORBS.size()])

	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	for id in CraftingDB.ORBS:
		GameState.orbs[id] = 0
		GameState.shards[id] = 0
	GameState.add_orb("chaos", 12)
	GameState.add_orb("transmute", 87)
	GameState.add_orb("divine", 1)
	GameState.add_shards("alchemy", 7)
	town.menu.open_vendor("stash")
	var stash := town.menu.current_panel() as StashPanel
	stash.tab = "currency"
	town.menu.refresh()
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var cells := stash.find_children("*", "DragSlot", true, false).filter(func(c): return c.custom_minimum_size.x < 100.0 and c.custom_minimum_size.x > 30.0)
	check(cells.size() == CraftingDB.ORBS.size(), "one cell per orb (%d)" % cells.size())
	var first: Control = cells[0]
	var second: Control = cells[1]
	check(first.global_position.y == second.global_position.y and second.global_position.x > first.global_position.x, "a group lies along a row")
	var xs := {}
	var ys := {}
	for c in cells:
		xs[snappedf(c.global_position.x, 1.0)] = true
		ys[snappedf(c.global_position.y, 1.0)] = true
	check(ys.size() == 2, "the groups stand side by side, two rows deep (%d)" % ys.size())
	check(xs.size() == CraftingDB.stash_groups().size() * CraftingDB.STASH_COLS, "%d columns in all (%d)" % [CraftingDB.stash_groups().size() * CraftingDB.STASH_COLS, xs.size()])
	check(first.size.x >= 56.0, "the cells are big (%d px)" % first.size.x)
	var vis := get_viewport().get_visible_rect()
	for c in cells:
		check(vis.encloses(Rect2(c.global_position, c.size)), "a cell is on screen")
		break
	var faint := 0
	for c in cells:
		if c.modulate.a < 0.35:
			faint += 1
	check(faint == CraftingDB.ORBS.size() - 4, "orbs you have none of are faint (%d)" % faint)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/stash_currency_layout.png"))
	print("stash currency: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
