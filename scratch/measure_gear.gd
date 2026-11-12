extends Node
## How strong a full set of Rare gear is under the PoE2 modifiers: rolls 400 sets at several item levels and prints the
## average of what each gives (life, damage, armour, resistances, attribute points, attack speed).
##   godot --headless --path . res://scratch/measure_gear.tscn

const SLOTS := ["weapon", "offhand", "helmet", "shoulders", "chest", "wrists", "gloves", "legs", "boots", "ring", "ring", "amulet", "belt"]
const STATS := ["max_life", "damage", "armor", "res_fire", "res_all", "str", "dex", "vit", "ene", "all_attr", "attack_speed", "crit_chance", "move_speed"]


func _ready() -> void:
	await get_tree().process_frame
	for ilvl in [5, 10, 20, 30, 45, 60]:
		var sums := {}
		for s in STATS:
			sums[s] = 0.0
		var n := 400
		for k in n:
			for slot in SLOTS:
				var it := LootGenerator.roll_item(ilvl, ItemInstance.Rarity.RARE, "offhand" if slot == "offhand" else slot)
				for e in it.affixes:
					if sums.has(String(e.stat)):
						sums[String(e.stat)] += float(e.value)
		var line := "ilvl %2d:" % ilvl
		for s in STATS:
			var v: float = sums[s] / n
			line += "  %s %.2f" % [s, v]
		print(line)
	get_tree().quit()
