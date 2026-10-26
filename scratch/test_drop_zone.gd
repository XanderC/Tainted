extends Node2D
## Checks dropping gear by dragging it onto the empty screen around the menu's windows: no drop box
## on the paperdoll; the empty screen takes bag, worn and flask items (and drops them) but not stash
## items or gems; the windows still take their own drops (the empty screen isn't under them); the
## message shows with the bag open alone.
## Needs a window (headless, pushed mouse events reach no control, so the real drags can't be checked):
##   godot --path . --resolution 1600x720 res://scratch/test_drop_zone.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


## A drag of `data` (as a bag cell starts one), moved to `at` and let go there.
func _drag_to(menu: GameMenu, data: Dictionary, at: Vector2) -> void:
	var vp := get_viewport()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	menu._char.force_drag(data, Label.new())
	await get_tree().process_frame
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(mv)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	vp.push_input(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var menu: GameMenu = town.menu
	p.bag.clear()
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id("iron_helm")
	it.display_name = "Iron Helm"
	p.pick_up(it)
	menu.open()
	for f in 3:
		await get_tree().process_frame
	check(not menu._char.find_children("*", "Label", true, false).any(func(l): return "DROP" in l.text), "no drop box on the paperdoll")
	var zones := menu._root.find_children("*", "DropZone", true, false)
	check(zones.size() == 1, "a drop zone behind the windows")
	var z: DropZone = zones[0]
	check(z._can_drop_data(Vector2.ZERO, {"kind": "item", "from": "bag", "item": it}), "it takes a bag item")
	check(z._can_drop_data(Vector2.ZERO, {"kind": "item", "from": "gear", "item": it}), "a worn one")
	check(not z._can_drop_data(Vector2.ZERO, {"kind": "item", "from": "stash", "item": it}), "not a stash item")
	check(not z._can_drop_data(Vector2.ZERO, {"kind": "gem", "from": "pouch", "gem_id": "ruby_1"}), "nor a gem")
	# What is under the empty screen, and under the bag window
	var vp := get_viewport()
	var empty_pt := Vector2(200, 360)  # left of the bag window, with it open alone
	var bag_pt: Vector2 = menu._char.get_global_rect().get_center()
	check(menu._char.get_global_rect().has_point(bag_pt) and not menu._char.get_global_rect().has_point(empty_pt),
		"the bag window is on the right, the left empty")
	# A real drag let go over the bag window: not dropped
	await _drag_to(menu, {"kind": "item", "from": "bag", "item": it}, bag_pt)
	check(p.bag.has(it), "let go over the bag window: still in the bag")
	# ...and over the empty screen: dropped
	await _drag_to(menu, {"kind": "item", "from": "bag", "item": it}, empty_pt)
	check(not p.bag.has(it), "let go over the empty screen: dropped on the ground")
	check(menu._toast.visible and "Dropped" in menu._toast.text, "and says so over the screen")
	menu.close()
	print("drop zone: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
