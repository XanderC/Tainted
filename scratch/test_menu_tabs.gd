extends Node2D
## Checks the menu's left side: opened as the inventory it is the bag alone (no left window, no tabs);
## the hireling's portrait opens its page and Back returns to the bag alone; Stats show the left
## window; the Skills tab is only at the Jeweler; the stash has Items, Currency, Gems and Hireling; the
## merchant and blacksmith only their own.
## With a window (--out=<folder>) it saves menu_bag.png and menu_jeweler.png.
##   godot --headless --path . res://scratch/test_menu_tabs.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _tabs(menu: GameMenu) -> Array:
	return menu._tabs_row.get_children().filter(func(c): return c.visible).map(func(c): return c.text)


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: GameMenu = town.menu
	menu.open()
	await get_tree().process_frame
	check(menu.is_open() and not menu._left_frame.visible, "the bag opens alone")
	check(menu.current_panel() == null, "with no left panel")
	if out != "":
		for f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "menu_bag.png")
	menu.toggle_stats()
	check(menu._left_frame.visible and menu._stats_popup.visible, "Stats show the left window")
	menu.toggle_stats()
	check(not menu._left_frame.visible, "and it goes again")
	menu.close()
	menu.open("hireling")
	check(menu._left_frame.visible and menu.current_panel() is HirelingPanel, "the portrait opens the hireling's page")
	menu.back()
	check(not menu._left_frame.visible, "Back: the bag alone")
	menu.close()
	menu.open_vendor("stash")
	await get_tree().process_frame
	var st := _tabs(menu)
	check(st.size() == 3 and not st.any(func(t): return "Skills" in t or "Hireling" in t), "the stash: Items, Currency, Gems (%s)" % [st])
	menu.close()
	menu.open_vendor("shop")
	await get_tree().process_frame
	check(_tabs(menu).size() == 1, "the merchant has only its own tab (%s)" % [_tabs(menu)])
	menu.close()
	menu.open_vendor("smith")
	await get_tree().process_frame
	check(_tabs(menu).size() == 1, "and the blacksmith (%s)" % [_tabs(menu)])
	menu.close()
	menu.open_vendor("jeweler")
	await get_tree().process_frame
	var jt := _tabs(menu)
	check(jt.size() == 2 and jt.any(func(t): return "Skills" in t), "the Jeweler: its own tab and Skills (%s)" % [jt])
	if out != "":
		menu.show_panel("skills")
		for f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "menu_jeweler.png")
	menu.close()
	print("menu tabs: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
