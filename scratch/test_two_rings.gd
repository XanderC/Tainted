extends Node2D
## Checks the second ring slot: a ring fits either slot, the first free one is used, both rings'
## stats count, rings move between the slots, and a third ring swaps out the first. Run headless:
##   godot --headless --path . res://scratch/test_two_rings.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func ring() -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id("bone_ring")
	it.rarity = ItemInstance.Rarity.MAGIC
	it.ilvl = 10
	it.display_name = it.base.display_name
	it.affixes = [{"id": "test", "stat": "max_life", "mod_type": StatBlock.ModType.FLAT, "value": 10.0, "text": "+10 Max Life"}]
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()

	var a := ring()
	var b := ring()
	var c := ring()
	var slots := p.valid_slots(a)
	check(slots.size() == 2 and slots.has("ring") and slots.has("ring2"), "a ring fits both ring slots (%s)" % [slots])
	check("ring2" in Player.SLOTS, "ring2 is an equipment slot")

	var life0 := p.stats.get_stat("max_life")
	p.bag.add(a)
	p.bag.add(b)
	check(p.equip_slot_for(a) == "ring", "the first ring goes in the first slot")
	check(p.equip_to(a, p.equip_slot_for(a)), "equip the first ring")
	check(p.equip_slot_for(b) == "ring2", "the second ring goes in the free second slot")
	check(p.equip_to(b, p.equip_slot_for(b)), "equip the second ring")
	check(p.equipment.get("ring") == a and p.equipment.get("ring2") == b, "both rings worn")
	check(absf(p.stats.get_stat("max_life") - (life0 + 20.0)) < 0.01, "both rings' stats count (%.1f)" % p.stats.get_stat("max_life"))

	# Swap them between the slots
	check(p.equip_to(a, "ring2"), "move the first ring to the second slot")
	check(p.equipment.get("ring2") == a and p.equipment.get("ring") == b, "the rings swapped slots")
	check(absf(p.stats.get_stat("max_life") - (life0 + 20.0)) < 0.01, "swapping doesn't change stats")

	# A third ring replaces one and the old one goes to the bag
	p.bag.add(c)
	check(p.equip_to(c, "ring"), "a third ring into the first slot")
	check(p.equipment.get("ring") == c and p.bag.has(b), "the ring it replaced went to the bag")

	# Saved and loaded by slot name
	var saved := {}
	for s in p.equipment:
		saved[s] = p.equipment[s].to_dict()
	check(saved.has("ring2"), "the second ring is saved under its slot")
	var back := ItemInstance.from_dict(saved["ring2"])
	check(p.valid_slots(back).has("ring2"), "a loaded ring can go back in the second slot")

	# Legendary and Set items are one of a kind on you
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	p.bag.clear()
	p._sync_gear_visuals()
	var echo_a := UniqueItems.make("band_of_echoes", 20)
	var echo_b := UniqueItems.make("band_of_echoes", 20)
	var signet := UniqueItems.make("frugal_signet", 20)
	for it in [echo_a, echo_b, signet]:
		p.bag.add(it)
	check(p.equip_to(echo_a, "ring"), "wear a Band of Echoes")
	check(p.unique_conflict(echo_b, "ring2") == echo_a, "a second Band of Echoes clashes with the first")
	check(not p.equip_to(echo_b, "ring2"), "so it can't go in the other ring slot")
	check(p.slot_block_reason(echo_b, "ring2").contains("only be worn once"), "and says why (%s)" % p.slot_block_reason(echo_b, "ring2"))
	check(p.equip_slot_for(echo_b) == "ring", "equipping it without a slot replaces the copy")
	check(p.equip_to(echo_b, "ring") and p.equipment.get("ring") == echo_b and p.bag.has(echo_a), "and swapping one copy for the other works")
	check(p.equip_to(signet, "ring2"), "a different Legendary ring goes beside it")
	var at := p.bag.position_of(echo_a)
	check(not p.can_unequip_to("ring2", at), "dragging the other ring onto the copy in the bag won't swap it in")

	var set_a := UniqueItems.make("bloodsworn_band", 20)
	var set_b := UniqueItems.make("bloodsworn_band", 20)
	p.unequip("ring")
	p.unequip("ring2")
	p.bag.add(set_a)
	p.bag.add(set_b)
	check(p.equip_to(set_a, "ring") and not p.equip_to(set_b, "ring2"), "two of the same Set ring can't both be worn")

	# One-handed weapons in both hands
	GameState.attributes = {"str": 100, "dex": 100}
	p.refresh_attributes()
	var fury_a := UniqueItems.make("fury_of_the_ancients", 20)
	var fury_b := UniqueItems.make("fury_of_the_ancients", 20)
	var cleaver := UniqueItems.make("bloodthirst_cleaver", 20)
	p.bag.clear()
	for it in [fury_a, fury_b, cleaver]:
		p.bag.add(it)
	check(p.equip_to(fury_a, "weapon"), "wield Fury of the Ancients")
	check(not p.equip_to(fury_b, "offhand"), "not a second one in the off hand")
	check(p.equip_to(cleaver, "offhand"), "a different Legendary one-hander is fine")
	check(p.equip_to(fury_a, "offhand") and p.equipment.get("weapon") == cleaver, "moving it between hands still works")
	GameState.attributes = {}

	print("two rings: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
