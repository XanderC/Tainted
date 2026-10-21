extends Node2D
## Checks identifying: Magic and better gear drops unidentified (flasks and Normal items never),
## shows only its base name, can't be worn or crafted on, a Scroll of Identify reveals it,
## it saves, and the Sage identifies the whole bag. Run headless:
##   godot --headless --path . res://scratch/test_identify.tscn

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
	# Enough of every attribute that gear requirements (Attributes) don't get in the way here
	GameState.attributes = {"str": 300, "dex": 300, "ene": 300}
	p.refresh_attributes()
	p.bag.clear()
	var scrolls_before := GameState.orb_count("identify")

	var it := LootGenerator.roll_item(20, ItemInstance.Rarity.RARE, "chest")
	var real_name := it.display_name
	var real_affixes := it.affixes.size()
	it.unidentify()
	check(not it.identified, "a Rare drops unidentified")
	check(it.display_name == it.base.display_name, "it shows only its base name (%s)" % it.display_name)
	check(it.affixes.size() == real_affixes, "its modifiers are kept, just hidden")
	check(p.equip_block_reason(it) == "Identify it first", "it can't be worn")
	check(not p.is_better_in_slot(it), "it's never offered as an upgrade")
	check(Crafting.orb_block_reason(it, "chaos") == "Identify it first", "orbs can't be used on it")
	check(Crafting.orb_block_reason(it, "identify") == "", "a Scroll of Identify can")
	check(it.get_tooltip().contains("Unidentified"), "the tooltip says Unidentified")

	var back := ItemInstance.from_dict(it.to_dict())
	check(not back.identified and back.hidden_name == real_name, "it saves unidentified")
	var old := ItemInstance.from_dict({"base": it.base.id, "name": "Old", "rarity": 2})
	check(old.identified, "items saved before identifying existed load identified")

	var flask := LootGenerator.roll_item(20, ItemInstance.Rarity.MAGIC, "flask")
	flask.unidentify()
	check(flask.identified, "flasks never drop unidentified")
	var plain := LootGenerator.roll_item(20, ItemInstance.Rarity.NORMAL, "chest")
	plain.unidentify()
	check(plain.identified, "Normal items never drop unidentified")

	# A scroll from the bag
	GameState.add_orb("identify", 1)
	p.bag.add(it)
	var res := Crafting.apply_orb(p, it, "identify")
	check(res.ok and it.identified and it.display_name == real_name, "a scroll identifies it (%s)" % res.msg)
	check(GameState.orb_count("identify") == scrolls_before, "the scroll is used up")
	check(Crafting.orb_block_reason(it, "identify") == "Already identified", "it can't be identified twice")
	check(p.equip_block_reason(it) == "", "it can be worn now")

	# The Sage: everything in the bag at once
	p.bag.clear()
	var a := LootGenerator.roll_item(20, ItemInstance.Rarity.MAGIC, "helmet")
	var b := LootGenerator.roll_item(20, ItemInstance.Rarity.RARE, "boots")
	a.unidentify()
	b.unidentify()
	p.bag.add(a)
	p.bag.add(b)
	check(GameState.identify_all(p) >= 2 and a.identified and b.identified, "the Sage identifies the whole bag")
	check(GameState.identify_all(p) == 0, "nothing left for the Sage")
	check(GameState.orb_count("identify") == scrolls_before, "the Sage is free")
	p.bag.clear()

	print("identify: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
