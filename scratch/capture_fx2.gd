extends Node2D
## The second batch of effects: elemental swings (cold, fire, lightning, chaos), Battle Cry's strength
## ring, the flasks' life and power rising, being revived, being slowed (a curse), a level up's stars,
## and on monsters blood, chill, poison and shock, a death's splat, a molten elite's burning ground
## and an elite going immune. Saves scratch/fx2_<n>.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_fx2.tscn

var main
var p: Player


func _ready() -> void:
	GameState.give_starter_skills()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.2)
	p = main.player
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	p.global_position = main.maze.random_floor_near(p.global_position, 500.0, 700.0)
	await _wait(1.0)
	# 1: the four elemental swings, a moment apart
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2(1, 0.6).normalized(), Vector2(-1, -0.4).normalized()]
	for i in 4:
		p._show_swing(dirs[i], 120.0, 110.0, Color.WHITE, 0.15, [1, 2, 3, 4][i])
		await _wait(0.06)
	_shot(1)
	await _wait(0.8)
	# 2: battle cry, then a life flask
	p._do_battle_cry(SkillTree.get_skill("battle_cry"))
	await _wait(0.3)
	_shot(2)
	await _wait(0.8)
	p._sfx_on("life_recovery", 0.85, 1.0, 30.0)
	await _wait(0.35)
	_shot(3)
	await _wait(0.8)
	p.apply_slow(1.5)
	await _wait(0.45)
	_shot(4)
	await _wait(1.6)
	p._on_leveled_up(2)
	await _wait(0.35)
	_shot(5)
	await _wait(1.0)
	p.dead = true
	p.revive(0.5)
	await _wait(0.45)
	_shot(6)
	await _wait(1.0)
	# 7: monsters: one bleeding, one chilled, one poisoned, one shocked, a molten elite, one immune
	var spots := [Vector2(-260, -40), Vector2(-120, 60), Vector2(20, -40), Vector2(160, 60), Vector2(300, -20)]
	var mons: Array = []
	for i in spots.size():
		var e := Enemy.new()
		e.position = p.global_position + spots[i]
		e.target = p
		e.max_hp = 5000.0
		e.touch_damage = 0.0
		e.speed = 0.0
		e.set_kind("zombie")
		if i == 4:
			var aff: Array[String] = ["molten", "shielding"]
			e.make_elite(MonsterAffix.Tier.ELITE, aff)
		main.add_child(e)
		mons.append(e)
	await _wait(0.3)
	mons[0].take_damage(10.0, false, RuneDef.DamageType.PHYSICAL)
	mons[1].take_damage(10.0, false, RuneDef.DamageType.COLD, "chill")
	mons[2].take_damage(10.0, false, RuneDef.DamageType.CHAOS, "poison")
	mons[3].take_damage(10.0, false, RuneDef.DamageType.LIGHTNING, "shock")
	mons[4]._shield_t = 2.5
	mons[4]._sfx_on("immunity", 2.5, mons[4].size_mult, 36.0 * mons[4].size_mult)
	await _wait(0.25)
	_shot(7)
	mons[0].take_damage(1.0e6)
	await _wait(0.4)
	_shot(8)
	get_tree().quit()


func _shot(n: int) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/fx2_%d.png" % n))


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
