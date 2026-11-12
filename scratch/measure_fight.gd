extends Node2D
## A boss fight as the worst case: a character of the level the story has brought you to (the life and armour a Rare in every slot gives)
## stands still beside the boss and never dodges a telegraph, while dealing the damage per second the pacing counts on (90 a level, 60% of it
## landing). Prints how long the boss lasts and how long the character would, and the share of their life each of its hits took.
##   godot --path . --resolution 1280x720 res://scratch/measure_fight.tscn

## [zone, boss id, level, life, armour]
const FIGHTS := [["dune_wastes", "briar_alpha", 3.5, 350, 170], ["weeping_hollow", "matron_vhol", 5.5, 400, 150],
	["ashen_verge", "grave_warden", 8.5, 500, 140], ["ashen_verge", "rift_golem", 9.3, 520, 140],
	["grand_ossuary_1", "herald_oren", 10.5, 560, 150], ["grand_ossuary_1", "herald_sable", 11.2, 590, 150], ["grand_ossuary_2", "herald_morrow", 12.6, 620, 160],
	["sepulcher_of_mourning", "lord_malaphax", 13.7, 650, 170]]


func _ready() -> void:
	if OS.get_environment("FIGHT_SPEED") != "":
		Engine.time_scale = float(OS.get_environment("FIGHT_SPEED"))  # faster than real time: AILMENTS=0 switches ailments off
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	for f in FIGHTS:
		var quests := {}
		for q in ["a1_first_incursion", "a1_poisoning_the_well", "a1_breaking_the_seal", "a1_descent_into_madness"]:
			quests[q] = {"state": "done", "step": 9, "count": 0}
		GameState.quests = quests
		GameState.current_zone = f[0]
		GameState.zone_entry = "start"
		var zone: Zone = load("res://scenes/zone.tscn").instantiate()
		add_child(zone)
		await get_tree().create_timer(0.8).timeout
		var p: Player = zone.player
		p.stats.add_mod("max_life", StatBlock.ModType.FLAT, float(f[3]) - 140.0, "fight")
		p.stats.add_mod("armor", StatBlock.ModType.FLAT, float(f[4]), "fight")
		p.hp = p.stats.get_stat("max_life")
		var boss: Enemy = null
		for b in zone._bosses:
			if String(b.get_meta("boss_id")) == f[1]:
				boss = b
		if boss == null:
			print(f[1], ": no boss")
			zone.queue_free()
			continue
		for e in get_tree().get_nodes_in_group("enemies"):
			if e != boss and zone.is_ancestor_of(e):
				e.queue_free()
		p.global_position = boss.global_position + Vector2(-260, 30)
		var dps := 0.6 * 90.0 * float(f[2])
		var t := 0.0
		var hits := []
		var helpless := 0.0
		var last := p.hp
		var result := ""
		while t < 400.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
			if p.is_helpless():
				helpless += 0.25  # a stunned or frozen character deals nothing
			elif boss.brain != null and boss.brain.state != BossBrain.S.SLEEP and boss._shield_t <= 0.0 and boss.hp > 0.0:
				boss.take_damage(dps * 0.25)  # (a plain number, no crit)
			if p.hp < last - 0.5:
				hits.append((last - p.hp) / p.stats.get_stat("max_life"))
			last = p.hp
			if p.dead or p.hp <= 0.0:
				result = "the character dies"
				break
			if boss._dead:
				result = "the boss dies"
				break
		var biggest := 0.0
		for h in hits:
			biggest = maxf(biggest, h)
		print("%-14s life %6.0f: %s after %3.0f s (character left with %3.0f%%; biggest single hit %.0f%% of their life, %d hits, %.0f s stunned or frozen)" % [f[1], boss.max_hp, result, t, 100.0 * maxf(p.hp, 0.0) / p.stats.get_stat("max_life"), biggest * 100.0, hits.size(), helpless])
		zone.queue_free()
		await get_tree().create_timer(0.4).timeout
	get_tree().quit()
