extends Node2D
## The wrists and legs slots: every base exists with its icon, rolls on its slot, wears in its slot
## (and no other), and is in the bag as a 2 x 2. Run:
##   godot --headless --path . res://scratch/test_wrist_legs.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var loot = LootGenerator
	for table in [["wrists", loot.WRIST_BASES], ["legs", loot.LEG_BASES]]:
		check(table[1].size() == 8, "%s: 8 pieces" % table[0])
		for row in table[1]:
			var b: ItemBase = loot.base_by_id(row[0])
			check(b != null and b.slot == table[0], "%s is a %s base" % [row[0], table[0]])
			check(b != null and b.icon != null, "%s has its icon" % row[0])
			check(b != null and b.bag_size() == Vector2i(2, 2), "%s is 2 x 2 in the bag" % row[0])
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	var p: Player = town.player
	GameState.attributes = {"str": 300}  # (the better pieces need Strength)
	p.refresh_attributes()
	for id in ["laced_bracers", "iron_guards"]:
		var it: ItemInstance = loot.roll_item(30, ItemInstance.Rarity.RARE, "")
		it.base = loot.base_by_id(id)
		var slot: String = it.base.slot
		check(slot in Player.SLOTS, "%s: %s is a slot" % [id, slot])
		p.bag.add(it)
		p.equip_to(it, slot)
		check(p.equipment.get(slot) == it, "%s is worn in %s" % [id, slot])
		check(not slot in Player.VISIBLE_SLOTS, "%s is not drawn on the character" % slot)
	var seen := {}
	for i in 400:
		var it: ItemInstance = loot.roll_item(40, ItemInstance.Rarity.MAGIC, "")
		seen[it.base.slot] = true
	check(seen.has("wrists") and seen.has("legs"), "both drop: %s" % [seen.keys()])
	print("wrists and legs: ", "ok" if fails == 0 else "%d failed" % fails)
	get_tree().quit(fails)
