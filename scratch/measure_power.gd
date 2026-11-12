extends Node2D
## Combat power of a full set of Rare gear, so the item rework can be balanced against the old one. For several item levels it rolls
## sets, puts each on a fresh character and reads what the game would use: damage per hit (Player.damage_for), attack speed, crit,
## life, armour and resistance. dps = damage x attack speed x (1 + crit), ehp = life x (100 + armour) / 100 against physical hits.
## Run the same scene in two builds to compare:   godot --path . --resolution 1280x720 res://scratch/measure_power.tscn
## (windowed: it needs the town scene; set POWER_SETS to change how many sets per level)

const SLOTS := ["weapon", "offhand", "helmet", "shoulders", "chest", "wrists", "gloves", "legs", "boots", "ring", "ring", "amulet", "belt"]


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	for s in p.equipment.keys():
		p.equipment[s].remove_from(p.stats)
	p.equipment.clear()
	var sets := int(OS.get_environment("POWER_SETS")) if OS.get_environment("POWER_SETS") != "" else 300
	for ilvl in [5, 10, 14, 20]:
		# a character of the level that finds this item level (area level + 1), attribute points in Strength and Vitality
		var level := int(round(1.45 * ilvl + 0.5))
		GameState.level = level
		GameState.attributes = {}
		GameState.attr_points = Attributes.POINTS_PER_LEVEL * (level - 1)
		GameState.add_attribute("str", GameState.attr_points - 2 * (level - 1))
		GameState.add_attribute("vit", GameState.attr_points)
		var acc := {"life": 0.0, "armor": 0.0, "dmg": 0.0, "as": 0.0, "crit": 0.0, "res": 0.0, "dps": 0.0, "ehp": 0.0, "str": 0.0, "vit": 0.0}
		for k in sets:
			var items := []
			for slot in SLOTS:
				var it := LootGenerator.roll_item(ilvl, ItemInstance.Rarity.RARE, slot)
				it.apply_to(p.stats)
				items.append(it)
			p.refresh_attributes()
			var life := p.stats.get_stat("max_life")
			var armor := p.stats.get_stat("armor")
			var dmg := p.damage_for(null)
			var aspeed := p.stats.get_stat("attack_speed")
			var crit := p.stats.get_stat("crit_chance")
			acc.life += life
			acc.armor += armor
			acc.dmg += dmg
			acc["as"] += aspeed
			acc.crit += crit
			acc.res += minf(p.resistance(RuneDef.DamageType.FIRE), 0.75)
			acc.dps += dmg * aspeed * (1.0 + crit) * (1.0 - (p.miss_chance() if p.has_method("miss_chance") else 0.0))  # (the old build never missed)
			acc.ehp += life * (100.0 + armor) / 100.0
			acc.str += GameState.attribute_bonus("str")
			acc.vit += GameState.attribute_bonus("vit")
			for it in items:
				it.remove_from(p.stats)
			p.refresh_attributes()
		var line := "ilvl %2d:" % ilvl
		for key in acc:
			line += "  %s %.2f" % [key, acc[key] / sets]
		print(line)
	get_tree().quit()
