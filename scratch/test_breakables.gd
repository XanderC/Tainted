extends Node2D
## Barrels, crates, urns and chests in the zones (Breakables, Breakable, LootChest): placed the same every time for a map, clear of
## the start and the walls, in every zone; broken by a melee swing, an arrow, a bolt and a dash; never seen as
## monsters; they spill loot, and a chest opens once and always holds gear. Takes scratch/breakables.png.
##   godot --path . --resolution 1600x720 res://scratch/test_breakables.tscn   (headless works too, no picture)

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	# Every zone's map: how many, where
	for id in ActDB.ZONES:
		var info: Dictionary = ActDB.ZONES[id]
		var m := MazeMap.new()
		m.setup(String(info.map))
		var s := Breakables.spots(m)
		var again := Breakables.spots(m)
		check(JSON.stringify(s) == JSON.stringify(again) or str(s) == str(again), "%s: the same every time" % id)
		var cells := m.floor_cells().size()
		print("%-22s %4d cells  %3d props  %d chests" % [id, cells, s.props.size(), s.chests.size()])
		if info.get("packs", true) == false:
			continue
		check(s.props.size() >= 4 and s.props.size() <= cells / 8, "%s: a fair number of props (%d for %d cells)" % [id, s.props.size(), cells])
		check(s.chests.size() >= 1 and s.chests.size() <= Breakables.MAX_CHESTS, "%s: one to %d chests (%d)" % [id, Breakables.MAX_CHESTS, s.chests.size()])
		var bad := 0
		for p in s.props:
			if m.is_wall(m.world_to_cell(p.pos)) or p.pos.distance_to(m.start_pos) < Breakables.KEEP_CLEAR.start - 1.0:
				bad += 1
		check(bad == 0, "%s: no prop in a wall or on the start (%d)" % [id, bad])
		for c in s.chests:
			check(not m.is_wall(m.world_to_cell(c)) and c.distance_to(m.start_pos) >= Breakables.CHEST_FROM_START, "%s: a chest on open floor away from the start" % id)
		m.free()
	var quiet := MazeMap.new()
	quiet.setup("dune_wastes")
	check(Breakables.spots(quiet, 0.0).props.is_empty() and Breakables.spots(quiet, 0.0).chests.is_empty(), "a zone can ask for none")
	check(Breakables.spots(quiet, 2.0).props.size() > Breakables.spots(quiet, 1.0).props.size(), "and for more")
	quiet.free()

	# A zone: they stand in it
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await get_tree().create_timer(1.0).timeout
	var p: Player = zone.player
	var props := get_tree().get_nodes_in_group("breakables")
	var chests := get_tree().get_nodes_in_group("interactables").filter(func(n): return n is LootChest)
	check(props.size() > 10 and chests.size() >= 1, "the zone has them (%d props, %d chests)" % [props.size(), chests.size()])
	check(props.all(func(b): return not get_tree().get_nodes_in_group("enemies").has(b)), "none of them is a monster")
	var kinds := {}
	for b in props:
		kinds[b.kind] = true
	check(kinds.size() == 3, "barrels, crates and urns (%s)" % [kinds.keys()])
	GameState.give_starter_skills()
	p.sync_skills_from_state()

	# A melee swing breaks one in two hits
	for b in get_tree().get_nodes_in_group("breakables"):
		b.global_position = p.global_position + Vector2(5000, 5000)  # out of the way
	var barrel := Breakable.new()
	barrel.kind = "barrel"
	zone.add_child(barrel)
	barrel.global_position = p.global_position + Vector2(70, 0)
	var broke := []
	barrel.broken.connect(func(at): broke.append(at))
	var cleave := SkillTree.get_skill("cleave")
	p.facing = Vector2.RIGHT
	p._hit_area(p.global_position, Vector2.RIGHT, 120.0, 120.0, cleave)
	check(not barrel._dead and barrel.hp == 1.0, "a barrel takes two hits (one: %.0f left)" % barrel.hp)
	p._hit_area(p.global_position, Vector2.RIGHT, 120.0, 120.0, cleave)
	check(barrel._dead and broke.size() == 1, "the second breaks it")
	check(not get_tree().get_nodes_in_group("breakables").has(barrel), "and it leaves the group")
	p._hit_area(p.global_position, Vector2.RIGHT, 120.0, 120.0, cleave)
	check(broke.size() == 1, "a broken one breaks once")
	# behind the swing, or too far: untouched
	var behind := Breakable.new()
	behind.kind = "urn"
	zone.add_child(behind)
	behind.global_position = p.global_position + Vector2(-70, 0)
	var far := Breakable.new()
	far.kind = "urn"
	zone.add_child(far)
	far.global_position = p.global_position + Vector2(400, 0)
	p._hit_area(p.global_position, Vector2.RIGHT, 120.0, 120.0, cleave)
	check(not behind._dead and not far._dead, "one behind the swing, and one out of reach, stand")
	p._hit_area(p.global_position, Vector2.RIGHT, 120.0, 360.0, cleave)
	check(behind._dead and not far._dead, "a circle takes the one behind")
	await get_tree().create_timer(0.7).timeout
	check(not is_instance_valid(barrel), "pieces fly, then it is gone")

	# An arrow, a bolt, a dash
	var arrow_target := Breakable.new()
	arrow_target.kind = "urn"
	zone.add_child(arrow_target)
	arrow_target.global_position = p.global_position + Vector2(260, 0)
	p._shoot(SkillTree.get_skill("quick_shot"), Vector2.RIGHT, false, "arrow", 500.0)
	await get_tree().create_timer(0.8).timeout
	check(arrow_target._dead, "an arrow breaks an urn on its way")
	var bolt_target := Breakable.new()
	bolt_target.kind = "crate"
	zone.add_child(bolt_target)
	bolt_target.global_position = p.global_position + Vector2(240, 0)
	var firebolt := SkillTree.get_skill("firebolt")
	p._shoot(firebolt, Vector2.RIGHT, false, "orb", 500.0)
	await get_tree().create_timer(0.8).timeout
	check(bolt_target.hp < 2.0, "a bolt hits a crate (%.0f left)" % bolt_target.hp)
	var dash_target := Breakable.new()
	dash_target.kind = "urn"
	zone.add_child(dash_target)
	p.global_position = zone.maze.start_pos
	dash_target.global_position = p.global_position + Vector2(100, 0)
	p.facing = Vector2.RIGHT
	p._do_dash(SkillTree.get_skill("shadow_step"))
	await get_tree().create_timer(0.5).timeout
	check(dash_target._dead, "a dash breaks what it passes through")
	# A hireling's arrow leaves them alone
	var spare := Breakable.new()
	spare.kind = "urn"
	zone.add_child(spare)
	spare.global_position = p.global_position + Vector2(0, 200)
	var hit_by_hireling := []
	var ha := HirelingArrow.new()
	ha.global_position = p.global_position + Vector2(0, 150)
	ha.dir = Vector2.DOWN
	ha.on_hit = func(e): hit_by_hireling.append(e)
	zone.add_child(ha)
	await get_tree().create_timer(0.5).timeout
	check(hit_by_hireling.is_empty() and not spare._dead, "a hireling's arrow does not touch them")

	# Loot
	var before := get_tree().get_nodes_in_group("pickups").size()
	for i in 300:
		Breakables.drop_loot(zone, p.global_position + Vector2(0, -300))
	var after := get_tree().get_nodes_in_group("pickups").size()
	check(after > before + 20 and after < before + 300 * 3, "breaking things now and then drops loot (%d in 300)" % (after - before))
	for n in get_tree().get_nodes_in_group("pickups"):
		n.queue_free()
	await get_tree().process_frame

	# A chest: opens once, always has gear
	var chest: LootChest = chests[0]
	check(chest.prompt != "" and get_tree().get_nodes_in_group("interactables").has(chest), "the chest offers to be opened")
	var gear0 := get_tree().get_nodes_in_group("pickups").filter(func(n): return n is LootPickup).size()
	chest.action.call()
	await get_tree().process_frame
	var gear := get_tree().get_nodes_in_group("pickups").filter(func(n): return n is LootPickup).size()
	check(chest.is_open and gear >= gear0 + 1, "opening it spills gear (%d pieces)" % (gear - gear0))
	check(not get_tree().get_nodes_in_group("interactables").has(chest), "and it offers no more")
	chest.open()
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("pickups").filter(func(n): return n is LootPickup).size() == gear, "a second try gives nothing")
	if DisplayServer.get_name() != "headless":
		for b in get_tree().get_nodes_in_group("breakables"):
			if b.global_position.distance_to(p.global_position) > 3000.0:
				b.global_position = zone.maze.start_pos + Vector2(randf_range(-250, 250), randf_range(60, 260))
		p.global_position = zone.maze.start_pos
		var show_off := Breakable.new()
		show_off.kind = "barrel"
		zone.add_child(show_off)
		show_off.global_position = p.global_position + Vector2(-140, 120)
		var show_crate := Breakable.new()
		show_crate.kind = "crate"
		zone.add_child(show_crate)
		show_crate.global_position = p.global_position + Vector2(-60, 150)
		var show_urn := Breakable.new()
		show_urn.kind = "urn"
		zone.add_child(show_urn)
		show_urn.global_position = p.global_position + Vector2(20, 130)
		var show_chest := LootChest.new()
		zone.add_child(show_chest)
		show_chest.global_position = p.global_position + Vector2(130, 140)
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/breakables.png"))
	print("breakables: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
