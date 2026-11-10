extends Node2D
## Currency on the ground (CurrencyPickup): every drop lies on its own, and tapping one takes it together with
## all the currency within NEAR_RADIUS of it (far ones stay), into the stash, in one toast. A pet's fetch takes
## just the one. A legacy "bundle" (saved before drops were single) still restores and collects.
##   godot --headless --path . res://scratch/test_currency_near.tscn

var fails := 0
var toasts: Array[String] = []


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func currency_taken(text: String, _col: Color) -> void:  # (the scene's toast, as a Zone has it)
	toasts.append(text)


func alive(c) -> bool:
	return is_instance_valid(c) and not c.is_queued_for_deletion()


func _ready() -> void:
	await get_tree().process_frame
	var o0 := GameState.orb_count("alteration")
	var s0 := GameState.shard_count("transmute")
	var a := CurrencyPickup.drop(self, ["orb", "alteration", 2], Vector2(100, 100))
	var b := CurrencyPickup.drop(self, ["shard", "transmute", 3], a.position + Vector2(120, 0))
	var c := CurrencyPickup.drop(self, ["shard", "transmute", 2], a.position + Vector2(-150, 90))
	var far := CurrencyPickup.drop(self, ["orb", "chaos", 1], Vector2(3000, 3000))
	await get_tree().process_frame
	check(a.kind == "orb" and b.kind == "shard" and a != b and a != c, "each drop is its own pickup")
	check(get_tree().get_nodes_in_group("currency_pickups").size() == 4, "four labels on the ground")
	check(a.neighbours().size() == 2 and not a.neighbours().has(far), "two lie near the first, the far one does not")

	# A pet fetching one takes only that one
	var pet_one := CurrencyPickup.drop(self, ["shard", "alchemy", 1], a.position + Vector2(40, 40))
	pet_one.take_by_pet("Rex")
	check(alive(a) and alive(b) and alive(c), "a pet's fetch leaves the neighbours")
	check(toasts.back().begins_with("Rex fetched"), "and says who fetched it: %s" % toasts.back())

	a._plate.pressed.emit()  # tapped with the player out of reach: walks over, then takes (no player here: nothing)
	a._take()
	await get_tree().process_frame
	check(not alive(a) and not alive(b) and not alive(c), "one tap took it and the currency near it")
	check(alive(far), "the far one stayed")
	check(GameState.orb_count("alteration") == o0 + 2 and GameState.shard_count("transmute") == s0 + 5, "all of it is in the stash")
	check(toasts.back().begins_with("+ ") and toasts.back().count(",") >= 1, "one toast says what you got: %s" % toasts.back())

	# More than three: the toast counts the rest
	var ids := ["transmute", "alteration", "alchemy", "chaos", "exalt"]
	for i in ids.size():
		CurrencyPickup.drop(self, ["orb", ids[i], 1], Vector2(500 + i * 40, 500))
	var tapped: CurrencyPickup = null
	for p in get_tree().get_nodes_in_group("currency_pickups"):
		if p.position.x >= 500 and p.position.x < 800:
			tapped = p
			break
	tapped._take()
	await get_tree().process_frame
	check(toasts.back().contains("and 2 more"), "a long list says 'and N more': %s" % toasts.back())

	# A legacy bundle is still understood
	var old := CurrencyPickup.new()
	old.kind = "bundle"
	old.title = "Currency"
	old.add_part(["shard", "transmute", 2])
	old.add_part(["orb", "alteration", 1])
	var s1 := GameState.shard_count("transmute")
	var text := old.collect()
	check(GameState.shard_count("transmute") == s1 + 2 and text.begins_with("+ "), "an old bundle still hands everything over")
	old.free()

	# And restores after a portal trip as saved
	TownPortals.remember_loot(self, {"zone": "x"})
	GameState.left_loot = JSON.parse_string(JSON.stringify(GameState.left_loot))
	var scene2 := Node2D.new()
	add_child(scene2)
	TownPortals.restore_loot(scene2, {"zone": "x"})
	await get_tree().process_frame
	check(scene2.get_children().any(func(n): return n is CurrencyPickup and n.kind == "orb" and n.id == "chaos"),
		"a pickup left behind comes back")
	print("currency near: ", "ok" if fails == 0 else "%d failed" % fails)
	get_tree().quit(fails)
