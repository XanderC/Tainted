extends Node
## Average of every stat a full Rare set (13 pieces) gives, by stat and modifier type, at the item levels Act I drops
## (and beyond). Used to calibrate the PoE2 modifier scales against the pacing the game was tuned with: run it in both
## builds and compare.   godot --headless --path . res://scratch/measure_sums.tscn     (POWER_SETS sets per level, default 200)

const SLOTS := ["weapon", "offhand", "helmet", "shoulders", "chest", "wrists", "gloves", "legs", "boots", "ring", "ring", "amulet", "belt"]
const KINDS := ["F", "I", "M"]


func _ready() -> void:
	await get_tree().process_frame
	var sets := int(OS.get_environment("POWER_SETS")) if OS.get_environment("POWER_SETS") != "" else 200
	for ilvl in [5, 10, 14, 20, 30]:
		var sums := {}
		for k in sets:
			for slot in SLOTS:
				var it := LootGenerator.roll_item(ilvl, ItemInstance.Rarity.RARE, "offhand" if slot == "offhand" else slot)
				if it.base.implicit_stat != "":
					var ik := "%s/%s*" % [it.base.implicit_stat, "F"]  # the base's own implicit (same in both builds)
					sums[ik] = float(sums.get(ik, 0.0)) + it.implicit_value()
				for e in it.affixes:
					var key := "%s/%s" % [e.stat, KINDS[int(e.mod_type)]]
					sums[key] = float(sums.get(key, 0.0)) + float(e.value)
		var keys := sums.keys()
		keys.sort()
		var line := "ilvl %2d:" % ilvl
		for key in keys:
			line += " %s=%.3f" % [key, float(sums[key]) / sets]
		print(line)
	get_tree().quit()
