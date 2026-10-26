extends Node2D
## Checks socketing without the Gems tab's sockets section: a gem dragged onto an item (the character
## panel's drop) goes into its next free socket, the item's card at the stash has "Take gems out",
## which puts them back in the shared gems, a runeword's card hasn't, and away from the stash no card
## has it. With a window (--shot=<png>) it saves the stash's Gems tab and the card.
##   godot --headless --path . res://scratch/test_gem_sockets.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var menu: GameMenu = town.menu
	p.bag.clear()
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id("chain_mail")
	it.display_name = "Chain Mail"
	it.sockets = 3
	p.pick_up(it)
	GameState.gems["ruby_1"] = 3
	menu.open_vendor("stash")
	await get_tree().process_frame
	check(GameState.gem_station, "the stash is a gem station")
	# The Gems tab: no sockets section
	var gp := GemsPanel.new()
	gp.menu = menu
	gp.player = p
	add_child(gp)
	gp.refresh()
	var texts: Array = gp.get_children().filter(func(c): return c is Label).map(func(c): return c.text)
	check(not gp.has_method("_add_sockets"), "no sockets section")
	gp.queue_free()
	# Dropped onto the item: into its next free socket
	GemsPanel.socket_into(menu, it, it.gems.size(), "ruby_1")
	GemsPanel.socket_into(menu, it, it.gems.size(), "ruby_1")
	check(it.gems == ["ruby_1", "ruby_1"] and GameState.gem_count("ruby_1") == 1, "two rubies socketed")
	# Its card: Take gems out
	menu.show_item_tip(it)
	await get_tree().process_frame
	var btn: Button = _find_button(menu.item_tip(), "Take all 2 gems out")
	check(btn != null, "its card has Take all 2 gems out")
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot != "":
		for f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	if btn != null:
		btn.pressed.emit()
	check(it.gems.is_empty() and GameState.gem_count("ruby_1") == 3, "taken out: back with the shared gems")
	await get_tree().process_frame
	check(_find_button(menu.item_tip(), "out") == null, "an empty item's card has no button")
	# Away from the stash
	menu.close()
	GemsPanel.socket_into(menu, it, 0, "ruby_1")
	GameState.gem_station = false
	menu.show_item_tip(it)
	await get_tree().process_frame
	check(_find_button(menu.item_tip(), "out") == null, "away from the stash: no button")
	print("gem sockets: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _find_button(n: Node, text: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if c.visible and text in c.text:
			return c
	return null
