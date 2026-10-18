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

	print("two rings: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
