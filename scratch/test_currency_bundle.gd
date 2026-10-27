extends Node2D
## Currency bundles (CurrencyPickup): drops near each other join one pile, far ones start another, one
## pickup hands over everything (orbs and shards into the stash), the label counts what's inside, a
## pile left behind comes back whole, and rift piles are one Currency and one Gems & Runes pile.
##   godot --headless --path . res://scratch/test_currency_bundle.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var scene := Node2D.new()
	add_child(scene)
	await get_tree().process_frame
	var a := CurrencyPickup.add_to_bundle(scene, "Currency", ["shard", "transmute", 2], Vector2(100, 100))
	await get_tree().process_frame
	var b := CurrencyPickup.add_to_bundle(scene, "Currency", ["shard", "transmute", 3], a.position + Vector2(60, 0))
	var c := CurrencyPickup.add_to_bundle(scene, "Currency", ["orb", "alteration", 1], a.position + Vector2(-80, 40))
	check(a == b and a == c, "nearby drops join one pile")
	check(a.parts.size() == 2 and int(a.parts[0][2]) == 5, "the same shard adds up: %s" % [a.parts])
	check(a.label_text() == "Currency (6)", "label counts what is in it: %s" % a.label_text())
	var far := CurrencyPickup.add_to_bundle(scene, "Currency", ["shard", "chaos", 1], Vector2(2000, 2000))
	check(far != a, "a far drop starts another pile")
	var other := CurrencyPickup.add_to_bundle(scene, "Gems & Runes", ["gem", "ruby_1", 1], a.position)
	check(other != a, "another title is another pile")
	var before_t := GameState.shard_count("transmute")
	var before_o := GameState.orb_count("alteration")
	var text := a.collect()
	check(GameState.shard_count("transmute") == before_t + 5 and GameState.orb_count("alteration") == before_o + 1, "one pickup hands everything over")
	check(text.begins_with("+ "), "it says what you got: %s" % text)
	# left behind and restored
	TownPortals.remember_loot(scene, {"zone": "x"})
	var saved := JSON.stringify(GameState.left_loot)
	GameState.left_loot = JSON.parse_string(saved)
	var scene2 := Node2D.new()
	add_child(scene2)
	TownPortals.restore_loot(scene2, {"zone": "x"})
	await get_tree().process_frame
	var bundles := scene2.get_children().filter(func(n): return n is CurrencyPickup and n.kind == "bundle")
	check(bundles.size() == 3, "all three piles come back: %d" % bundles.size())
	var again := bundles.filter(func(n): return n.title == "Currency" and n.parts.size() == 2)
	check(again.size() == 1 and int(again[0].parts[0][2]) == 5, "a restored pile keeps its contents")
	print("currency bundle: ", "ok" if fails == 0 else "%d failed" % fails)
	get_tree().quit(fails)
