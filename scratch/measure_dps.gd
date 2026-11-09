extends Node2D
## What a character of level L deals, to see how long the Act I bosses last: attribute points all in Strength, a Rare in every slot
## rolled at an item level near the zone's, and each equipped skill's hit, cooldown and damage per second. Prints a table.
##   godot --path . --resolution 1280x720 res://scratch/measure_dps.tscn

const LEVELS := [3, 6, 9, 12, 15, 17, 20]
## the item level a character of that level has been finding (area level + 1: ActDB zones are 2..9 over the act)
const ILVL := {3: 3, 6: 5, 9: 7, 12: 9, 15: 11, 17: 12, 20: 14}


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	seed(4242)
	for L in LEVELS:
		for s in p.equipment.keys():
			p.equipment[s].remove_from(p.stats)
		p.equipment.clear()
		GameState.level = 1
		GameState.xp = 0.0
		GameState.attributes = {}
		GameState.attr_points = 0
		GameState.add_xp(1.0e9)  # (past the level wanted: set by hand below)
		GameState.level = L
		GameState.attr_points = Attributes.POINTS_PER_LEVEL * (L - 1)
		GameState.add_attribute("str", GameState.attr_points - 2 * (L - 1))  # most in Strength, some Vitality
		GameState.add_attribute("vit", GameState.attr_points)
		var ilvl: int = ILVL[L]
		for slot in ["weapon", "body", "helmet", "gloves", "boots", "belt", "ring", "amulet"]:
			var it := LootGenerator.roll_item(ilvl, ItemInstance.Rarity.RARE, slot)
			if it != null:
				it.identify()
				p.equipment[slot] = it
				it.apply_to(p.stats)
		p.refresh_attributes()
		var line := "L%2d  ilvl %2d  life %4.0f  armor %4.0f  damage stat %6.1f  attack speed %.2f  |" % [L, ilvl, p.stats.get_stat("max_life"), p.stats.get_stat("armor"), p.stats.get_stat("damage"), p.stats.get_stat("attack_speed")]
		var best := 0.0
		var rows := []
		for i in GameState.SKILL_SLOTS:
			var s: SkillDef = GameState.get_slot_skill_def(i)
			if s == null:
				continue
			var rank := GameState.get_skill_rank(s.id)
			var hit := p.damage_for(s) * s.get_effective_damage_mult(rank)
			var cd := s.get_effective_cooldown(rank)
			if cd <= 0.0:
				cd = 1.0 / maxf(p.stats.get_stat("attack_speed"), 0.1)
			rows.append("%s hit %.0f cd %.2f dps %.0f" % [s.id, hit, cd, hit / cd])
			best = maxf(best, hit / cd)
		print(line)
		for r in rows:
			print("      ", r)
		print("      best single skill dps ~ %.0f" % best)
	print("--- boss hp (25 x 1.18^(area-1) x map hp x fight hp) ---")
	for b in [["briar_alpha", 2, 5.0], ["matron_vhol", 4, 12.0], ["grave_warden", 6, 10.0], ["rift_golem", 6, 12.0],
			["herald_oren", 7, 7.0], ["herald_sable", 7, 7.0], ["herald_morrow", 8, 7.5], ["lord_malaphax", 9, 14.0]]:
		var d := BossDB.def(b[0])
		var hp: float = 25.0 * pow(1.18, int(b[1]) - 1) * float(b[2]) * float(d.get("hp", 1.0))
		print("%-14s area %d  hp %.0f" % [b[0], b[1], hp])
	get_tree().quit()
