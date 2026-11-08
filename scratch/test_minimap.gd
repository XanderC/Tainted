extends Node2D
## The top-right of the screen: the minimap in the corner, the bag and options as icons left of it, then
## passives and the town portal scroll (the character screen in town), none of them on another and all on
## screen; the minimap shows what has been explored (kept with the scene), grows when tapped, and the party list
## stands on the left under the hireling's portrait, pushing the zone title and quest tracker down.
## Takes scratch/minimap_*.png.
##   godot --path . --resolution 1600x720 res://scratch/test_minimap.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.3) -> void:
	await get_tree().create_timer(seconds).timeout


func shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + name_))


func find_all(from: Node, type_: String) -> Array:
	return from.find_children("*", type_, true, false)


func button_with(from: Node, text_part: String) -> Button:
	for c in find_all(from, "Button"):
		if (c as Button).text.begins_with(text_part):
			return c
	return null


func check_row(label: String, controls: Dictionary) -> void:
	var screen := get_viewport().get_visible_rect()
	var names: Array = controls.keys()
	for n in names:
		var c: Control = controls[n]
		check(c != null and c.visible, "%s: %s is there" % [label, n])
		if c == null:
			return
		check(screen.encloses(c.get_global_rect()), "%s: %s is on screen %s" % [label, n, str(c.get_global_rect())])
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(not (controls[names[i]] as Control).get_global_rect().intersects((controls[names[j]] as Control).get_global_rect()),
				"%s: %s and %s do not overlap" % [label, names[i], names[j]])


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	# A party list, to see where it stands (offline there is none: it gets three rows by hand)
	var pu := PartyUI.new()
	Net.party_ui = pu
	get_tree().root.add_child.call_deferred(pu)
	await settle(0.2)

	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await settle(0.6)

	# --- the row ---
	var mm: Minimap = null
	for c in find_all(zone, "Control"):
		if c is Minimap:
			mm = c
	check(mm != null, "the zone has a minimap")
	var row := {
		"minimap": mm,
		"bag": button_with(zone.menu, "🎒"),
		"options": button_with(zone.menu, "⚙"),
		"passives": button_with(zone.skill_tree_ui, "✦"),
		"scroll": button_with(zone, "🌀"),
	}
	check_row("zone", row)
	var bag: Control = row.bag
	var opts: Control = row.options
	check(bag != null and opts != null and mm != null and bag.get_global_rect().end.x <= mm.get_global_rect().position.x, "the bag is left of the minimap")
	check(bag != null and (bag as Button).text == "🎒" and (opts as Button).text == "⚙", "the bag and options are icons only")
	check(opts != null and bag != null and opts.get_global_rect().end.x <= bag.get_global_rect().position.x, "options is left of the bag")
	check(mm.get_global_rect().end.x > get_viewport().get_visible_rect().end.x - 20.0 and mm.get_global_rect().position.y < 20.0, "the minimap is in the top right corner")

	# --- exploring ---
	var mem: Minimap.Memory = zone.get_meta("minimap", null)
	check(mem != null, "what is seen is kept with the zone")
	var seen0 := 0
	for b in mem.seen:
		seen0 += int(b)
	check(seen0 > 100, "the surroundings are explored at the start (%d cells)" % seen0)
	zone.player.global_position = zone.maze.start_pos + Vector2(1800, 600)
	await settle(0.4)
	var seen1 := 0
	for b in mem.seen:
		seen1 += int(b)
	check(seen1 > seen0 + 100, "walking on explores more (%d -> %d)" % [seen0, seen1])
	zone.player.global_position = zone.maze.start_pos
	await settle(0.3)
	shot("minimap_zone.png")

	# --- the whole map ---
	var small := mm.size
	mm.toggle()
	await settle(0.3)
	check(mm.size.x > small.x * 2.0 and get_viewport().get_visible_rect().encloses(mm.get_global_rect()), "tapping it shows the whole map, on screen")
	shot("minimap_big.png")
	mm.toggle()
	await settle(0.2)
	check(is_equal_approx(mm.size.x, small.x), "and again puts it back")

	# --- the party list: on the left, under the hireling, pushing the rest down ---
	var dock: Control = pu._dock
	check(is_instance_valid(dock), "the party list has a place in the left column")
	var portrait: Control = null
	var title: Label = null
	for c in find_all(zone, "Control"):
		if c is HirelingPortrait:
			portrait = c
	for l in find_all(zone, "Label"):
		if (l as Label).text.contains("Area level"):
			title = l
	var y_before := title.global_position.y
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(PartyUI.ROW_W, 64)
		pu._frame.add_child(b)
	await settle(0.4)
	check(pu._frame.visible, "the list shows with rows in it")
	check(pu._frame.offset_left < 100.0, "it is on the left (%.0f)" % pu._frame.offset_left)
	var column := dock.get_parent()
	check(portrait.get_parent() == column and dock.get_index() == portrait.get_index() + 1, "it is the next thing in the column after the hireling's portrait")
	check(is_equal_approx(pu._frame.offset_top, dock.global_position.y), "and stands on its spacer")
	if portrait.visible:  # (with no hireling the portrait takes no room, and the list starts at the top)
		check(pu._frame.offset_top >= portrait.global_position.y + portrait.size.y - 1.0, "directly under the portrait")
	check(title.global_position.y >= pu._frame.offset_top + 3 * 64.0 - 1.0, "the zone title is below the list (%.0f -> %.0f)" % [y_before, title.global_position.y])
	check(title.global_position.y > y_before + 150.0, "it moved down to make room")
	# (the screenshot's party frame layer is hidden offline: shown for a look)
	for b in pu._frame.get_children():
		pass
	zone.queue_free()
	pu._frame.get_children().map(func(b): b.queue_free())
	await settle(0.4)
	check(pu._frame.offset_left == 16.0 and pu._frame.offset_top == 82.0 or not pu._frame.visible, "with no column the list waits under the portrait's place")
	Net.party_ui = null
	pu.queue_free()

	# --- town: the character screen where the scroll is, no maze, its people on the map ---
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await settle(0.6)
	var tmm: Minimap = null
	for c in find_all(town, "Control"):
		if c is Minimap:
			tmm = c
	check(tmm != null, "the town has a minimap")
	check_row("town", {
		"minimap": tmm,
		"bag": button_with(town.menu, "🎒"),
		"options": button_with(town.menu, "⚙"),
		"passives": button_with(town.skill_tree_ui, "✦"),
		"characters": button_with(town, "👥"),
	})
	shot("minimap_town.png")
	town.queue_free()
	await settle(0.3)

	# --- a rift ---
	GameState.test_map = "twin_oasis"
	var rift = load("res://scenes/main.tscn").instantiate()
	add_child(rift)
	await settle(0.8)
	var rmm: Minimap = null
	for c in find_all(rift, "Control"):
		if c is Minimap:
			rmm = c
	check(rmm != null, "the rift has a minimap")
	check_row("rift", {
		"minimap": rmm,
		"bag": button_with(rift.menu, "🎒"),
		"options": button_with(rift.menu, "⚙"),
		"passives": button_with(rift.skill_tree_ui, "✦"),
		"scroll": button_with(rift, "🌀"),
	})
	var m1: Minimap.Memory = rift.get_meta("minimap", null)
	check(m1 != null and m1.maze == rift.maze, "it knows the rift's maze")
	shot("minimap_rift.png")

	print("minimap: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
