extends Node2D
## Checks the grid bag and stash: item sizes, filling, moving and swapping, equipping and
## unequipping with room checks, saving, loading old saves, and bag <-> stash. Run headless:
##   godot --headless --path . res://scratch/test_item_grid.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func base(id: String) -> ItemBase:
	for b in LootGenerator.bases:
		if b.id == id:
			return b
	return null


func item(id: String) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = base(id)
	it.display_name = it.base.display_name
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	GameState.stash.clear()
	GameState.stash_overflow.clear()

	# --- sizes ---
	check(item("bone_ring").grid_size() == Vector2i(1, 1), "ring 1x1")
	check(item("dagger").grid_size() == Vector2i(1, 2), "dagger 1x2")
	check(item("rusty_sword").grid_size() == Vector2i(1, 3), "sword 1x3")
	check(item("greatsword").grid_size() == Vector2i(2, 4), "greatsword 2x4")
	check(item("battle_axe").grid_size() == Vector2i(2, 3), "battle axe 2x3")
	check(item("oak_staff").grid_size() == Vector2i(1, 4), "staff 1x4")
	check(item("chain_mail").grid_size() == Vector2i(2, 3), "chest 2x3")
	check(item("wooden_shield").grid_size() == Vector2i(2, 2), "wooden shield 2x2")
	check(item("tower_shield").grid_size() == Vector2i(2, 3), "tower shield 2x3")

	# --- filling: 10x6 holds five 2x4 greatswords side by side, then nothing that tall ---
	for i in 5:
		check(p.add_to_bag(item("greatsword")), "greatsword %d fits" % i)
	check(not p.add_to_bag(item("greatsword")), "sixth greatsword refused")
	check(p.bag_cells_used() == 40, "five greatswords use 40 cells (got %d)" % p.bag_cells_used())
	check(p.add_to_bag(item("bone_ring")), "a ring fits in the row left")
	check(not p.can_fit(item("chain_mail")), "a 2x3 chest no longer fits")
	p.bag.clear()

	# --- moving and swapping within the bag ---
	var sword := item("rusty_sword")
	var ring := item("bone_ring")
	var amulet := item("old_amulet")
	check(p.bag.place(sword, Vector2i(0, 0)), "place sword at 0,0")
	check(p.bag.place(ring, Vector2i(3, 0)), "place ring at 3,0")
	check(p.bag.place(amulet, Vector2i(4, 0)), "place amulet at 4,0")
	check(p.move_in_bag(sword, Vector2i(6, 2)), "move sword to free space")
	check(p.bag.position_of(sword) == Vector2i(6, 2), "sword now at 6,2")
	# Sword (1x3) onto the ring alone: they swap, the ring going where the sword was
	check(p.move_in_bag(sword, Vector2i(3, 0)), "sword onto one item swaps")
	check(p.bag.position_of(sword) == Vector2i(3, 0) and p.bag.position_of(ring) == Vector2i(6, 2),
		"swapped: sword 3,0 ring 6,2 (got %s %s)" % [p.bag.position_of(sword), p.bag.position_of(ring)])
	# A 2x2 shield covering both the sword and the amulet is refused
	var shield := item("wooden_shield")
	check(p.bag.place(shield, Vector2i(8, 4)), "place shield")
	check(not p.move_in_bag(shield, Vector2i(3, 0)), "landing on two items is refused")
	check(not p.move_in_bag(shield, Vector2i(9, 0)), "off the grid is refused")
	p.bag.clear()

	# --- unequipping onto the grid ---
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	var mail := item("chain_mail")
	check(p.equip_to(mail, "chest", true), "wear chain mail")
	check(p.can_unequip_to("chest", Vector2i(0, 0)), "chest can come off into an empty corner")
	check(not p.can_unequip_to("chest", Vector2i(9, 4)), "a 2x3 chest can't hang off the edge")
	var vest := item("padded_vest")
	check(p.bag.place(vest, Vector2i(4, 1)), "place a vest in the bag")
	check(p.unequip_to("chest", Vector2i(4, 1)), "dropping worn mail onto the vest swaps them")
	check(p.equipment.get("chest") == vest and p.bag.has(mail) and not p.bag.has(vest), "vest worn, mail in bag")
	check(p.bag.position_of(mail) == Vector2i(4, 1), "mail went where it was dropped")

	# --- equipping needs room for what comes off ---
	p.bag.clear()
	var rings: Array[ItemInstance] = []
	for i in Player.BAG_SIZE - 1:
		var r := item("bone_ring")
		rings.append(r)
		p.bag.add(r)
	var mail2 := item("chain_mail")
	p.bag.add(item("bone_ring"))  # bag now completely full
	check(p.bag.free_cells() == 0, "bag full of rings")
	check(not p.unequip("chest"), "no room to take the vest off")
	p.bag.clear()

	# --- saving and loading ---
	var a := item("greatsword")
	var b2 := item("bone_ring")
	p.bag.place(a, Vector2i(2, 1))
	p.bag.place(b2, Vector2i(9, 5))
	var saved := p.bag.to_array()
	var g := ItemGrid.new(Player.BAG_COLS, Player.BAG_ROWS)
	check(g.load_array(saved).is_empty(), "everything reloads")
	var names := g.items().map(func(x): return [x.base.id, g.position_of(x)])
	check(names.has(["greatsword", Vector2i(2, 1)]) and names.has(["bone_ring", Vector2i(9, 5)]),
		"positions survive a save (got %s)" % [names])
	# Old format: a list of item dicts with nulls; too much to fit comes back to the caller
	var old: Array = []
	for i in 24:
		old.append(item("greatsword").to_dict() if i % 2 == 0 else null)
	var homeless := g.load_array(old)
	check(g.count() == 5 and homeless.size() == 7, "old save: 5 of 12 greatswords fit, 7 returned (got %d, %d)" % [g.count(), homeless.size()])

	# --- bag <-> stash ---
	p.bag.clear()
	var helm := item("iron_helm")
	var boots := item("worn_boots")
	p.bag.place(helm, Vector2i(0, 0))
	GameState.stash.place(boots, Vector2i(5, 5))
	check(GameState.can_bag_to_stash(helm, Vector2i(0, 0)), "helm can go to stash space")
	check(GameState.bag_to_stash(helm, Vector2i(5, 5)), "helm onto the boots swaps with them")
	check(GameState.stash.has(helm) and p.bag.has(boots), "helm stashed, boots in bag")
	check(p.bag.position_of(boots) == Vector2i(0, 0), "boots took the helm's old place")
	check(GameState.stash_to_bag(helm, Vector2i(4, 2)), "helm back to the bag")
	check(p.bag.has(helm) and not GameState.stash.has(helm), "helm in the bag again")

	# --- the overflow moves in once there's room ---
	GameState.stash.clear()
	while GameState.stash.add(item("chain_mail")):
		pass  # 18 fit: 10 rows don't divide into threes, so a row of 12 cells is left
	check(GameState.stash.count() == 18 and GameState.stash.free_cells() == 12,
		"18 mail fit, 12 cells left (got %d, %d)" % [GameState.stash.count(), GameState.stash.free_cells()])
	while GameState.stash.add(item("bone_ring")):
		pass
	check(GameState.stash.free_cells() == 0, "stash topped up with rings (free %d)" % GameState.stash.free_cells())
	var waiting := item("old_amulet")
	GameState.stash_overflow.append(waiting)
	var first: ItemInstance = GameState.stash.items()[0]
	p.bag.clear()
	check(GameState.stash_to_bag(first, Vector2i(0, 0)), "take one mail out")
	check(GameState.stash.has(waiting) and GameState.stash_overflow.is_empty(), "the waiting amulet moved into the freed space")

	print("item grid: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
