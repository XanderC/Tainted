extends Node
## Kept zones (ZoneInstances): leave the Ashwood by a town portal, a waypoint or an exit and it is still there
## as you left it (the monsters you killed stay dead, what lay on the ground lies there, the boss you
## woke is asleep and whole again); going back asks whether to carry on or start over (Cancel, Continue and
## Reset); a town portal goes back to the instance it was read in without asking; dying brings you back to
## the waypoint in the same zone; leaving the game forgets them. Also the rift prompt in town.
## Runs with real scene changes: this node is kept (it is not the current scene).
##   godot --path . --resolution 1600x720 res://scratch/test_instances.tscn

var _fails := 0
var tree: SceneTree


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func settle(seconds := 0.4) -> void:
	await get_tree().create_timer(seconds).timeout


func alive_in(z: Node) -> int:
	var n := 0
	for c in z.get_children():
		if c is Enemy and not c._dead and not c.is_queued_for_deletion():
			n += 1
	return n


func loot_in(z: Node) -> int:
	var n := 0
	for c in z.get_children():
		if c is LootPickup and not c.is_queued_for_deletion():
			n += 1
	return n


func choice() -> InstanceChoice:
	for c in tree.current_scene.get_children():
		if c is InstanceChoice and not c.is_queued_for_deletion():
			return c
	return null


func button(from: Node, text_part: String) -> Button:
	for c in from.find_children("*", "Button", true, false):
		if (c as Button).text.contains(text_part):
			return c
	return null


func is_town() -> bool:
	return tree.current_scene != null and tree.current_scene.scene_file_path.ends_with("town.tscn")


func _ready() -> void:
	tree = get_tree()
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	GameState.pet = "boar"
	GameState.tp_scrolls = 5
	var zone: Zone = load(Zone.SCENE).instantiate()
	tree.root.add_child.call_deferred(zone)  # (under the root, as a scene is: this node stays when the scene changes)
	await tree.process_frame
	await tree.process_frame
	tree.current_scene = zone
	await settle(0.8)
	check(is_instance_valid(PetDB.node), "the pet comes along")

	# Change the zone: kill some monsters, leave loot on the ground, hurt one
	var all: Array = []
	for c in zone.get_children():
		if c is Enemy and not c.is_boss:
			all.append(c)
	var n0 := alive_in(zone)
	for i in 12:
		all[i].hp = 0.0
		all[i]._die()
	var marker: Enemy = all[20]
	marker.hp = 7.0
	zone._drop_item(LootGenerator.roll_item(5, 0), zone.player.global_position + Vector2(200, 0))
	await settle(0.3)
	var n1 := alive_in(zone)
	var loot1 := loot_in(zone)
	check(n1 == n0 - 12 and loot1 >= 1, "the zone is changed (%d -> %d monsters, %d on the ground)" % [n0, n1, loot1])
	var old_player := zone.player

	# Leave by a waypoint: the zone is kept
	var flags := {}
	ActDB.travel(tree, ActDB.TOWN, "waypoint")
	await settle(1.5)
	check(is_town(), "you are in town")
	check(ZoneInstances.has("dune_wastes"), "the zone is kept")
	check(zone.get_parent() == null and not is_instance_valid(zone.player), "out of the game, without the player")

	# Going back asks: Cancel
	ActDB.travel(tree, "dune_wastes", "start", func(): flags["cancelled"] = true)
	await settle(0.5)
	var ui := choice()
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/instance_choice.png"))
	check(ui != null and tree.paused, "going back to a kept zone asks, with the game paused")
	check(ui != null and ui.find_children("*", "Label", true, false).any(func(l): return (l as Label).text.contains("monsters are left")), "and says what is left")
	check(ui != null and ui.find_children("*", "Label", true, false).any(func(l): return (l as Label).text.contains("still lives")), "and that the boss still lives")
	button(ui, "Cancel").pressed.emit()
	await settle(0.5)
	check(flags.has("cancelled") and is_town() and not tree.paused and ZoneInstances.has("dune_wastes"), "Cancel stays in town, nothing lost")

	# Continue
	ActDB.travel(tree, "dune_wastes", "start")
	await settle(0.5)
	ui = choice()
	button(ui, "Continue").pressed.emit()
	await settle(1.5)
	check(tree.current_scene == zone, "Continue is the same zone again")
	check(is_instance_valid(zone.player) and GameState.player == zone.player and zone.player != old_player, "with a new player")
	check(alive_in(zone) == n1, "the monsters you killed are still dead (%d of %d)" % [alive_in(zone), n1])
	check(is_instance_valid(marker) and marker.hp == 7.0 and marker.target == zone.player, "the hurt monster is as it was, and after the new player")
	check(loot_in(zone) == loot1, "what lay on the ground still does")
	check(zone.get_children().filter(func(c): return c is GameMenu).size() == 1, "one menu, not two")
	check(is_instance_valid(PetDB.node) and tree.get_nodes_in_group("pet").size() == 1, "one pet, with the new player")
	check(zone.player.global_position.distance_to(zone.maze.start_pos) < 250.0, "at the entrance (%.0f px)" % zone.player.global_position.distance_to(zone.maze.start_pos))

	# A town portal back and forth goes to the instance it was read in, without asking
	zone.player.global_position = zone.maze.start_pos + Vector2(400, 200)
	check(TownPortals.read_scroll(zone), "a scroll is read")
	var tp_at := Vector2(float(GameState.town_portal.x), float(GameState.town_portal.y))
	for i in 5:
		all[30 + i].hp = 0.0
		all[30 + i]._die()
	var n2 := alive_in(zone)
	await settle(0.5)
	zone.portal_to_town()
	await settle(1.5)
	check(is_town() and ZoneInstances.has("dune_wastes"), "through the portal to town, the zone kept")
	await settle(0.6)
	var back: Array = tree.get_nodes_in_group("town_portals")
	check(back.size() == 1, "its portal stands in town (%d)" % back.size())
	TownPortals.go_back(tree, GameState.town_portal, true)
	await settle(1.5)
	check(choice() == null, "going back through the portal does not ask")
	check(tree.current_scene == zone and alive_in(zone) == n2, "it is the same zone, as left (%d monsters)" % alive_in(zone))
	check(zone.player.global_position.distance_to(tp_at) < 120.0, "and you stand by the portal (%.0f px)" % zone.player.global_position.distance_to(tp_at))
	check(tree.get_nodes_in_group("town_portals").size() == 0 or tree.get_nodes_in_group("town_portals").size() == 1, "(no doubled portals)")

	# Dying in a boss fight: back at the waypoint, in the same zone, the boss whole again
	var boss: Enemy = zone._boss
	check(is_instance_valid(boss), "the zone has its boss")
	var home := Vector2(float(MapData.objects_of(zone.maze.data, "boss")[0].x), float(MapData.objects_of(zone.maze.data, "boss")[0].y))
	zone.player.global_position = home + Vector2(-380, 40)
	await settle(1.0)
	check(boss._aggro, "the boss wakes")
	await settle(2.2)
	boss._shield_t = 0.0
	boss.hp = boss.max_hp * 0.5
	var killed_before := alive_in(zone)
	zone.player.take_damage(1.0e9)
	await settle(0.3)
	check(zone.player.dead, "the player dies")
	zone._respawn()
	await settle(1.8)
	check(tree.current_scene == zone and not zone.player.dead, "back in the same zone, alive")
	var boss2: Enemy = zone._boss
	check(is_instance_valid(boss2) and boss2 != boss and boss2.hp == boss2.max_hp and not boss2._aggro, "the boss is made again: whole and asleep")
	check(BossArena.current == null and tree.get_nodes_in_group("boss_arena").size() == 1, "its ring is open, and one ready")
	check(tree.get_nodes_in_group("boss_adds").size() == 0, "his adds are gone")
	check(alive_in(zone) <= killed_before, "the monsters killed stay dead")

	# Reset: a new zone, the old one thrown away
	ActDB.travel(tree, ActDB.TOWN, "waypoint")
	await settle(1.5)
	ActDB.travel(tree, "dune_wastes", "start")
	await settle(0.5)
	ui = choice()
	button(ui, "Reset area").pressed.emit()
	await settle(3.0)
	check(tree.current_scene != zone and not is_instance_valid(zone), "Reset throws the old zone away")
	var fresh: Zone = tree.current_scene as Zone
	check(fresh != null and alive_in(fresh) > n0 - 40, "and the new one is full of monsters (%d)" % alive_in(fresh) if fresh != null else "no new zone")
	check(not ZoneInstances.has("dune_wastes"), "(nothing kept while you are in it)")

	# Leaving the game forgets them
	ActDB.travel(tree, ActDB.TOWN, "waypoint")
	await settle(1.5)
	check(ZoneInstances.has("dune_wastes"), "kept again")
	GameState.leave_character()
	check(not ZoneInstances.has("dune_wastes"), "leaving the character forgets the zone")

	# A solo rift left through a town portal: Rift Gate asks too
	GameState.town_portal = {"id": 5, "kind": "rift", "inst": "", "key": "solo:1", "maze": 1, "level": 3, "x": 100.0, "y": 100.0,
		"save": {"level": 3, "map": "twin_oasis"}}
	var town = tree.current_scene
	town.enter_dungeon()
	await settle(0.5)
	ui = choice()
	check(ui != null, "the Rift Gate asks about the rift you left")
	check(ui != null and ui.find_children("*", "Label", true, false).any(func(l): return (l as Label).text.contains("Rift 3")), "naming it")
	button(ui, "New rift").pressed.emit()
	await settle(1.5)
	check(GameState.town_portal.is_empty(), "a new rift lets the old one go")

	print("instances: ", "ok" if _fails == 0 else "%d failed" % _fails)
	tree.quit(1 if _fails > 0 else 0)
