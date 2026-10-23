extends Node
## Checks town portal scrolls alone (TownPortals): read one in a zone and a portal opens where you
## stand; reading another moves it (one each); through it to town, where a portal back stands; back
## through that you come out at it, with what you left on the ground, and it closes. A solo rift is
## carried on with: the same maze, monsters, kills and clock. A rift's portal closes when it moves on
## to its next maze, and when you leave it another way. No scrolls, no portal. The Merchant sells
## them, monsters drop them, and the boss leaves some. Runs at the root (the scenes change under it):
##   godot --headless --path . res://scratch/test_town_portal.tscn

var runner := false
var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	GameState.give_starter_skills()
	GameState.tp_scrolls = 3
	await _zone()
	await _rift()
	_shop_and_drops()
	print("town portal: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _portals() -> Array:
	return get_tree().get_nodes_in_group("town_portals").filter(func(n): return not n.is_queued_for_deletion())


## Into a portal: stand on it and tap its label.
func _go_through(portal: TownPortal) -> void:
	GameState.player.global_position = portal.global_position
	portal._plate.pressed.emit()
	await _wait(1.5)


func _zone() -> void:
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	get_tree().change_scene_to_file("res://scenes/zone.tscn")
	await _wait(1.2)
	var z = _scene()
	var p: Player = z.player
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	p.global_position = z.maze.random_floor_near(z.maze.start_pos, 500.0, 700.0)
	check(TownPortals.read_scroll(z), "a scroll is read in a zone")
	await get_tree().process_frame
	check(GameState.tp_scrolls == 2, "it's used up (3 -> %d)" % GameState.tp_scrolls)
	var first: Dictionary = GameState.town_portal
	var ps := _portals()
	check(ps.size() == 1 and ps[0].global_position.distance_to(p.global_position) < 1.0 and "Town Portal" in ps[0]._plate.text,
		"a portal opens where you stand, labelled (%d)" % ps.size())
	p.global_position = z.maze.random_floor_near(p.global_position, 250.0, 350.0)
	TownPortals.read_scroll(z)
	await get_tree().process_frame
	ps = _portals()
	check(ps.size() == 1 and ps[0].global_position.distance_to(p.global_position) < 1.0 and int(GameState.town_portal.id) != int(first.id),
		"reading another replaces it: still one portal, where you stand now (%d)" % ps.size())
	var spot: Vector2 = ps[0].global_position
	# Something left lying here: an item and a pile of orbs
	var item := LootGenerator.roll_item(5, ItemInstance.Rarity.MAGIC)
	var pk := LootPickup.new()
	pk.item = item
	pk.position = spot + Vector2(150, 0)
	z.add_child(pk)
	var c := CurrencyPickup.new()
	c.kind = "orb"
	c.id = "chaos"
	c.amount = 2
	c.position = spot + Vector2(-150, 0)
	z.add_child(c)
	await _go_through(ps[0])
	var town = _scene()
	check(town.scene_file_path.ends_with("town.tscn"), "through it: in town")
	ps = _portals()
	check(ps.size() == 1 and "Portal: The Dune Wastes" in ps[0]._plate.text and ps[0].global_position.distance_to(town.PORTAL) < 1.0,
		"a portal back stands by the square (%s)" % (ps[0]._plate.text if ps.size() > 0 else "none"))
	if ps.is_empty():
		return
	await _go_through(ps[0])
	z = _scene()
	check(z.scene_file_path.ends_with("zone.tscn"), "back through it: in the zone")
	check(z.player.global_position.distance_to(spot) < 80.0, "standing by where the portal was (%.0f away)" % z.player.global_position.distance_to(spot))
	check(GameState.town_portal.is_empty() and _portals().is_empty(), "and it closed behind you")
	var items: Array = z.get_children().filter(func(n): return n is LootPickup)
	var piles: Array = z.get_children().filter(func(n): return n is CurrencyPickup and n.kind == "orb")
	check(items.size() == 1 and items[0].item.display_name == item.display_name and items[0].position.distance_to(spot + Vector2(150, 0)) < 1.0,
		"the item you left is lying where it was (%d)" % items.size())
	check(piles.size() == 1 and piles[0].amount == 2 and piles[0].position.distance_to(spot + Vector2(-150, 0)) < 1.0,
		"and the orbs (%d)" % piles.size())
	var had := GameState.tp_scrolls
	GameState.tp_scrolls = 0
	check(not TownPortals.read_scroll(z) and _portals().is_empty(), "with no scrolls, no portal")
	GameState.tp_scrolls = had


func _rift() -> void:
	GameState.rift_level = 1
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(1.2)
	var m = _scene()
	var p: Player = m.player
	for e in get_tree().get_nodes_in_group("enemies").slice(0, 3):
		e.take_damage(1.0e7)
	await _wait(0.3)
	var map: String = m.maze.map_id
	var n: int = m.mazes_visited
	var kills: int = m.run.kills
	var left := get_tree().get_nodes_in_group("enemies").filter(func(e): return not e._dead).size()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e._dead:
			e.hp = e.max_hp * 0.5  # hurt: still hurt when you come back
	p.global_position = m.maze.random_floor_near(m.maze.start_pos, 150.0, 250.0)
	TownPortals.read_scroll(m)
	await get_tree().process_frame
	var ps := _portals()
	check(ps.size() == 1, "a scroll read in a rift opens a portal")
	var spot: Vector2 = ps[0].global_position
	var elapsed: float = m.run.elapsed
	await _go_through(ps[0])
	check(_scene().scene_file_path.ends_with("town.tscn"), "through it: in town")
	var save: Dictionary = GameState.town_portal.get("save", {})
	check(save.get("enemies", []).size() == left, "the rift was kept as you left it (%d monsters)" % save.get("enemies", []).size())
	ps = _portals()
	check(ps.size() == 1 and "Portal: Rift 1" in ps[0]._plate.text, "a portal back to the rift stands by the square")
	await _wait(2.0)  # the clock doesn't run in town
	await _go_through(ps[0])
	m = _scene()
	check(m.scene_file_path.ends_with("main.tscn") and m.maze != null and m.maze.map_id == map and m.mazes_visited == n,
		"back through it: the same rift, the same maze (%s %d)" % [m.maze.map_id if m.maze else "?", m.mazes_visited])
	var now := get_tree().get_nodes_in_group("enemies").filter(func(e): return not e._dead)
	check(now.size() == left and m.run.kills == kills, "its monsters still there (%d of %d) and its kills (%d)" % [now.size(), left, m.run.kills])
	check(now.all(func(e): return absf(e.hp - e.max_hp * 0.5) < 1.0), "still as hurt as they were")
	var saved_t := float(save.get("run", {}).get("e", -9.0))
	check(absf(saved_t - elapsed) < 0.5 and m.run.elapsed - saved_t < 1.9,  # back 1.5 s; the 2 s in town don't count
		"the clock carried on from where it was, not while in town (%.1f, %.1f now)" % [saved_t, m.run.elapsed])
	check(m.player.global_position.distance_to(spot) < 80.0, "standing by the portal's spot")
	check(GameState.town_portal.is_empty() and _portals().is_empty(), "the portal closed behind you")
	# Moving on to the next maze closes it
	TownPortals.read_scroll(m)
	m._travel()
	await _wait(1.2)
	check(GameState.town_portal.is_empty() and _portals().is_empty(), "a rift's portal closes when it moves on to its next maze")
	# Leaving another way (fallen alone): it closes, the rift is gone
	TownPortals.read_scroll(m)
	await get_tree().process_frame
	m.return_to_town()
	await _wait(1.2)
	check(_scene().scene_file_path.ends_with("town.tscn") and GameState.town_portal.is_empty() and _portals().is_empty(),
		"leaving a rift another way closes its portal: nothing to go back to")
	# The boss leaves scrolls
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(1.2)
	m = _scene()
	m.run.state = DungeonRun.State.BOSS
	m.run._on_boss_died(m.player.global_position + Vector2(300, 0))
	await get_tree().process_frame
	var scrolls := get_tree().get_nodes_in_group("currency_pickups").filter(func(c): return c.kind == "scroll")
	check(scrolls.size() == 1 and scrolls[0].amount >= 1 and "Scroll" in scrolls[0]._plate.text, "the boss leaves Scrolls of Town Portal on the ground")
	if not scrolls.is_empty():
		var before := GameState.tp_scrolls
		m.player.global_position = scrolls[0].global_position
		scrolls[0]._plate.pressed.emit()
		check(GameState.tp_scrolls == before + scrolls[0].amount, "picked up, they're yours to read (%d -> %d)" % [before, GameState.tp_scrolls])


func _shop_and_drops() -> void:
	GameState.tp_scrolls = 5
	GameState.orbs["transmute"] = 3
	check(GameState.buy_scroll() and GameState.tp_scrolls == 6 and int(GameState.orbs["transmute"]) == 2,
		"the Merchant sells one for an Orb of Transmutation")
	GameState.tp_scrolls = GameState.MAX_SCROLLS
	check(not GameState.buy_scroll() and int(GameState.orbs["transmute"]) == 2, "not past the most you can carry (%d)" % GameState.MAX_SCROLLS)
	var c := CurrencyPickup.new()
	c.kind = "scroll"
	c.id = "town_portal"
	add_child(c)
	c._take()
	check(is_instance_valid(c) and not c.is_queued_for_deletion() and GameState.tp_scrolls == GameState.MAX_SCROLLS,
		"carrying all you can, one on the ground stays there")
	var shop := ShopPanel.new()
	shop.player = Player.new()
	shop.player.class_def = ClassLibrary.get_class_def("warrior")
	check(shop._wares().any(func(w): return w.type == "scroll" and w.icon != null), "it's among the Merchant's wares")
	shop.player.free()
	shop.free()
