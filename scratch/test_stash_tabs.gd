extends Node2D
## The stash's tabs (GameState.stash_tabs): the usual four to start; add, rename, retype, reorder and delete them, with
## the rules (a Uniques tab takes Legendary and Set gear only, one Currency / Gems / Runes tab, the main stash stays
## put, a deleted tab's gear goes to the others); gear dragged in and out of a tab's grid; saved and loaded; the
## editing dialog and the tab row. Run headless:
##   godot --headless --path . res://scratch/test_stash_tabs.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func names() -> Array:
	return GameState.stash_tabs.map(func(t): return t.name)


func types() -> Array:
	return GameState.stash_tabs.map(func(t): return t.type)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var gs := GameState
	var p: Player = town.player
	# Stashing Legendary gear unlocks its look and saves the account: put the account file back as it was at the end
	var acc_backup := FileAccess.get_file_as_string(gs.ACCOUNT_PATH) if FileAccess.file_exists(gs.ACCOUNT_PATH) else ""
	var tabs0 = gs.stash_tabs.duplicate()
	var stash0: ItemGrid = gs.stash

	# The usual four
	gs.stash_tabs = gs._default_stash_tabs()
	check(types() == ["items", "currency", "gems", "runes"] and names() == ["Stash", "Currency", "Gems", "Runes"], "four tabs to start (%s)" % [names()])
	check(gs.stash_grid(0) == gs.stash and gs.stash_grid(1) == null, "the first is the main stash, the others hold no items")

	# Adding
	check(gs.add_stash_tab("Weapons", "items") == "" and gs.stash_tabs.size() == 5, "an Items tab is added")
	check(gs.add_stash_tab("Best", "unique") == "" and gs.stash_tabs.size() == 6, "and a Uniques tab")
	check(gs.add_stash_tab("More", "currency") != "", "a second Currency tab is refused (%s)" % gs.add_stash_tab("More", "currency"))
	check(gs.add_stash_tab("x", "nonsense") != "", "an unknown type is refused")
	check(gs.stash_grid(4) != null and gs.stash_grid(5) != null and gs.stash_grid(4) != gs.stash_grid(5), "each has its own grid")
	check(gs.stash_grid(4).cols == gs.STASH_COLS and gs.stash_grid(4).rows == gs.STASH_ROWS, "as big as the stash")
	while gs.stash_tabs.size() < gs.MAX_STASH_TABS:
		gs.add_stash_tab("t", "items")
	check(gs.add_stash_tab("one too many", "items") != "", "at most %d tabs" % gs.MAX_STASH_TABS)
	while gs.stash_tabs.size() > 6:
		gs.remove_stash_tab(gs.stash_tabs.size() - 1)

	# Naming
	gs.rename_stash_tab(4, "  Swords and other very long names  ")
	check(String(gs.stash_tabs[4].name).length() <= gs.TAB_NAME_MAX and not String(gs.stash_tabs[4].name).begins_with(" "), "a long name is cut (%s)" % gs.stash_tabs[4].name)
	gs.rename_stash_tab(4, "   ")
	check(gs.stash_tabs[4].name == "Items", "a blank name is the type's")
	gs.rename_stash_tab(4, "Weapons")
	gs.rename_stash_tab(0, "Main")
	check(gs.stash_tabs[0].name == "Main", "the main stash can be renamed")

	# Retyping
	check(gs.set_stash_tab_type(0, "unique") != "", "the main stash stays an Items tab")
	check(gs.set_stash_tab_type(4, "currency") != "", "not into a second Currency tab")
	check(gs.set_stash_tab_type(4, "unique") == "" and gs.stash_tabs[4].type == "unique" and gs.stash_grid(4) != null, "an empty Items tab becomes a Uniques tab")
	check(gs.set_stash_tab_type(4, "items") == "" and gs.stash_tabs[4].type == "items", "and back")
	check(gs.stash_tabs[4].name == "Weapons", "a name of your own stays through it")

	# Gear: what a Uniques tab takes
	var rare := LootGenerator.roll_item(5, ItemInstance.Rarity.RARE)
	var uniq := UniqueItems.roll(10, false, null)
	check(uniq != null and uniq.is_unique() and not rare.is_unique(), "(a Rare and a Legendary to use)")
	var uniq_grid := gs.stash_grid(5)
	check(gs.tab_accepts(0, rare) and gs.tab_accepts(0, uniq), "the main stash takes both")
	check(not gs.tab_accepts(5, rare) and gs.tab_accepts(5, uniq), "a Uniques tab takes only the Legendary")
	check(not gs.tab_accepts(1, uniq), "a Currency tab takes no gear")
	p.bag.clear()
	p.bag.add(rare)
	p.bag.add(uniq)
	check(not gs.can_bag_to_stash(rare, Vector2i(0, 0), uniq_grid), "a Rare cannot be dragged into a Uniques tab")
	check(gs.can_bag_to_stash(uniq, Vector2i(0, 0), uniq_grid) and gs.bag_to_stash(uniq, Vector2i(0, 0), uniq_grid) and uniq_grid.has(uniq) and not p.bag.has(uniq),
		"a Legendary can")
	check(gs.stash_grid_of(uniq) == uniq_grid and gs.stash_count() >= 1, "and is found there")
	check(not gs.can_stash_to_bag(uniq, Vector2i(0, 0)), "but not dragged onto the Rare in the bag: the Rare would have to swap into the Uniques tab")
	var free := p.bag.find_free(uniq)
	check(gs.can_stash_to_bag(uniq, free) and gs.stash_to_bag(uniq, free) and p.bag.has(uniq) and not uniq_grid.has(uniq), "and can be taken out to the bag (%s)" % free)
	check(gs.bag_to_stash(rare, Vector2i(1, 1), gs.stash_grid(4)) and gs.stash_grid(4).has(rare), "a Rare goes in an Items tab")
	check(gs.move_in_stash(rare, Vector2i(3, 2), gs.stash_grid(4)) and gs.stash_grid(4).position_of(rare) == Vector2i(3, 2), "and moves within it")
	gs.stash_grid(4).remove(rare)
	# Putting gear away goes to the right place
	check(gs.stash_item(uniq) and uniq_grid.has(uniq), "a Legendary put away goes to the Uniques tab")
	p.bag.add(rare)
	check(gs.stash_item(rare) and gs.stash.has(rare), "a Rare to the main stash")
	check(gs.set_stash_tab_type(5, "items") == "" and gs.set_stash_tab_type(5, "unique") == "", "a Uniques tab holding only Legendary gear can stay one")
	gs.stash.remove(rare)
	gs.stash_grid(4).add(rare)
	check(gs.set_stash_tab_type(4, "unique") != "", "an Items tab with a Rare cannot become a Uniques tab")
	check(gs.set_stash_tab_type(4, "gems") != "", "nor a Gems tab while it holds gear (%s)" % gs.set_stash_tab_type(4, "gems"))
	check(gs.all_stash_items().has(rare) and gs.all_stash_items().has(uniq), "every tab's gear counts")

	# Order
	check(not gs.move_stash_tab(0, 1) and not gs.move_stash_tab(1, -1), "the main stash stays first, nothing moves in front of it")
	var before := names()
	check(gs.move_stash_tab(4, 1) and names()[5] == before[4] and names()[4] == before[5], "a tab moves down")
	check(gs.move_stash_tab(5, -1) and names() == before, "and back up")
	check(not gs.move_stash_tab(5, 1), "not past the end")

	# Saved and loaded
	var saved: Array = JSON.parse_string(JSON.stringify(gs._stash_tabs_to_array()))
	check(saved.size() == 6 and not saved[0].has("items") and saved[4].has("items") and saved[5].has("items"), "saved: the main stash's gear stays under 'stash'")
	check(saved[4].items.size() == 1, "(the Rare is in the Weapons tab's save)")
	var want := names()
	var overflow_before := gs.stash_overflow.size()
	gs._load_stash_tabs(saved)
	check(names() == want and types() == ["items", "currency", "gems", "runes", "items", "unique"], "loaded: the same tabs (%s)" % [names()])
	check(gs.stash_grid(4).count() == 1 and gs.stash_grid(5).count() == 1 and gs.stash_grid(0) == gs.stash, "and their gear")
	check(gs.stash_overflow.size() == overflow_before, "nothing lost to the overflow")
	var damaged := saved.duplicate(true)
	damaged[4]["type"] = "unique"  # a Rare in a Uniques tab
	damaged.append({"name": "Second", "type": "currency"})
	damaged.append("junk")
	gs._load_stash_tabs(damaged)
	check(types().count("currency") == 1 and types().size() == 6, "a damaged save: a second Currency tab and junk are dropped (%s)" % [types()])
	check(gs.stash_grid(4).items().all(func(it): return it.is_unique()) and gs.all_stash_items().size() + gs.stash_overflow.size() >= 2,
		"and a Rare in a Uniques tab is kept elsewhere, not lost")
	gs._load_stash_tabs([])
	check(types() == ["items", "currency", "gems", "runes"], "an old account (no tabs saved) has the usual four")
	check(gs.stash_grid(0) == gs.stash, "(and the main stash is still the same grid)")

	# Deleting a tab with gear
	gs.stash_tabs = gs._default_stash_tabs()
	gs.add_stash_tab("Temp", "items")
	var spare := LootGenerator.roll_item(5, ItemInstance.Rarity.MAGIC)
	gs.stash_grid(4).add(spare)
	check(not gs.remove_stash_tab(0), "the main stash cannot be deleted")
	check(gs.remove_stash_tab(4) and gs.stash_tabs.size() == 4, "a tab is deleted")
	check(gs.stash.has(spare) or gs.stash_overflow.has(spare), "and its gear went to the main stash")
	gs.stash.remove(spare)

	# The dialog and the tab row
	gs.stash_tabs = gs._default_stash_tabs()
	town.menu.open_vendor("stash")
	await get_tree().process_frame
	var row: Control = town.menu._tabs_row
	check(row.get_child_count() == 5 and row.get_children().any(func(c): return c is Button and c.text == "✎"), "the tab row: four tabs and the edit button (%d)" % row.get_child_count())
	var dlg := StashTabsDialog.open(town.menu)
	await get_tree().process_frame
	check(dlg.find_children("Tab_*", "HBoxContainer", true, false).size() == 4, "the dialog lists the tabs")
	(dlg.find_child("AddTab", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(gs.stash_tabs.size() == 5 and row.get_child_count() == 6, "adding one: the row has it too (%d)" % row.get_child_count())
	var row4 := dlg.find_child("Tab_4", true, false)
	var kind := row4.find_child("Kind", true, false) as OptionButton
	kind.item_selected.emit(1)  # Uniques
	await get_tree().process_frame
	check(gs.stash_tabs[4].type == "unique", "choosing Uniques in the dialog retypes it")
	kind = dlg.find_child("Tab_4", true, false).find_child("Kind", true, false) as OptionButton
	kind.item_selected.emit(2)  # Currency: already there
	await get_tree().process_frame
	check(gs.stash_tabs[4].type == "unique" and dlg._note.text != "", "an impossible change is refused, and says why (%s)" % dlg._note.text)
	var name_edit := dlg.find_child("Tab_4", true, false).find_child("Name", true, false) as LineEdit
	name_edit.text = "Chase items"
	name_edit.text_submitted.emit("Chase items")
	await get_tree().process_frame
	check(gs.stash_tabs[4].name == "Chase items", "renaming in the dialog")
	# open that tab and see its grid
	var stash_panel := town.menu._get_panel("stash") as StashPanel
	stash_panel.select_tab(4)
	town.menu.show_panel("stash")
	await get_tree().process_frame
	check(stash_panel.grid_tab == 4 and stash_panel.find_children("*", "Label", true, false).any(func(l): return "CHASE ITEMS" in l.text),
		"selecting the tab shows its own title")
	check(stash_panel.find_children("*", "Label", true, false).any(func(l): return "Legendary and Set gear only" in l.text), "and what a Uniques tab takes")
	(dlg.find_child("Tab_4", true, false).find_child("Delete", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(gs.stash_tabs.size() == 4 and stash_panel.grid_tab == 0, "deleting the open tab returns to the main stash")
	if DisplayServer.get_name() != "headless":
		gs.add_stash_tab("Chase items", "unique")
		gs.add_stash_tab("Weapons", "items")
		dlg.queue_free()
		await get_tree().process_frame
		stash_panel.select_tab(4)
		town.menu.refresh()
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/stash_tabs.png"))
		var d2 := StashTabsDialog.open(town.menu)
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/stash_tabs_dialog.png"))
		d2.queue_free()
	gs.stash_tabs = tabs0
	gs.stash = stash0
	if acc_backup != "":
		var f := FileAccess.open(gs.ACCOUNT_PATH, FileAccess.WRITE)
		f.store_string(acc_backup)
		f.close()
	print("stash tabs: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
