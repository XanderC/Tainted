extends Node2D
## The weapon swings (SpellFx.slash: the character art's slash crescent): Cleave facing right and
## left, a few moments into each, then Sundering Strike. Saves scratch/slash_<n>.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_slash.tscn


func _ready() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.2)
	var p: Player = main.player
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	p.global_position = main.maze.random_floor_near(p.global_position, 500.0, 700.0)  # open ground
	await _wait(1.0)
	print("player at %s" % p.get_global_transform_with_canvas().origin)
	var n := 1
	for dir in [Vector2.RIGHT, Vector2.LEFT]:
		p.facing = dir
		p.rig.set_facing(dir.x)
		p._do_cleave_skill(SkillTree.get_skill("cleave"))
		for d in [0.04, 0.08, 0.1]:
			await _wait(d)
			_shot(n)
			n += 1
		await _wait(0.6)
	p.facing = Vector2(1, 0.4).normalized()
	p._do_sundering_strike(SkillTree.get_skill("sundering_strike"))
	await _wait(0.08)
	_shot(n)
	get_tree().quit()


func _shot(n: int) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/slash_%d.png" % n))


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
