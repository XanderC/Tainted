extends Node2D
## Checks dragging socket gems straight onto items: at the Jeweler a gem from the shared gems dropped
## onto a worn item or a bag item goes into its next free socket (no item picked first); an item with
## no free socket refuses it; away from the stash and the Jeweler nothing takes it. Uses the
## character panel's own cells. Run headless:
##   godot --headless --path . res://scratch/test_gem_drop.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().create_timer(1.0).timeout  # the town has set the player up (its saved gear)
	var p: Player = GameState.player
	var menu: GameMenu = town.menu
	var sword := ItemInstance.new()
	sword.base = LootGenerator.base_by_id("broad_sword")
	sword.display_name = sword.base.display_name
	sword.sockets = 2
	p.equipment["weapon"] = sword  # worn (straight in: this checks sockets, not wearing requirements)
	p._sync_gear_visuals()
	var helm := ItemInstance.new()
	helm.base = LootGenerator.base_by_id("iron_helm")
	helm.display_name = helm.base.display_name
	helm.sockets = 1
	p.bag.add(helm)
	var gid: String = GemDef.all_ids()[0]
	GameState.gems[gid] = 3
	var gem := {"kind": "gem", "from": "pouch", "gem_id": gid}

	menu.open_vendor("jeweler")
	await get_tree().process_frame
	var weapon_cell := _gear_cell(menu, "weapon")
	check(weapon_cell != null, "the paperdoll's weapon cell (worn: %s; doll cells %d)" % [p.equipment.keys(), menu._char._doll.get_child_count()])
	if weapon_cell == null:
		print("gem drop: %d checks, %d failed" % [_checks, _fails])
		get_tree().quit(1)
		return
	check(weapon_cell.can_accept.call(gem), "a gem dragged over the worn sword: it can go in")
	weapon_cell.on_drop.call(gem)
	check(sword.gems == [gid] and GameState.gem_count(gid) == 2, "dropped: it's in the sword's socket (%s, %d left)" % [sword.gems, GameState.gem_count(gid)])
	await get_tree().process_frame
	var tile := _bag_tile(menu, helm)
	check(tile != null and tile.can_accept_at.call(gem, Vector2(5, 5)), "a gem dragged over the helmet in the bag: it can go in")
	tile.on_drop_at.call(gem, Vector2(5, 5))
	check(helm.gems == [gid] and GameState.gem_count(gid) == 1, "dropped: it's in the helmet's socket")
	await get_tree().process_frame
	tile = _bag_tile(menu, helm)
	check(tile != null and not tile.can_accept_at.call(gem, Vector2(5, 5)), "the helmet has no free socket now: it refuses another")
	check(menu.selected == null, "no item had to be picked first")
	menu.close()
	menu.open()
	await get_tree().process_frame
	weapon_cell = _gear_cell(menu, "weapon")
	check(weapon_cell != null and not weapon_cell.can_accept.call(gem), "away from the stash and the Jeweler a gem can't go in")
	menu.close()
	print("gem drop: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _gear_cell(menu: GameMenu, slot: String) -> DragSlot:
	for c in menu._char._doll.get_children():
		if c is DragSlot and String(c.payload.get("slot", "")) == slot:
			return c
	return null


func _bag_tile(menu: GameMenu, it: ItemInstance) -> DragSlot:
	for c in menu._char._bag_view.get_children():
		if c is DragSlot and c.payload.get("item") == it:
			return c
	return null
