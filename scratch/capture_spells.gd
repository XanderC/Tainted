extends Node2D
## The spell effects in a rift (SpellFx): the warrior's skills cast in turn, then hit sparks of each
## damage type on a monster, a molten blast and a lightning strike. Saves scratch/spells_<n>.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_spells.tscn

var main


func _ready() -> void:
	GameState.give_starter_skills()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.2)
	var p: Player = main.player
	p.can_fight = true
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()  # a clear stage
	await _wait(0.2)
	p._do_earthquake(SkillTree.get_skill("earthquake"))
	p._do_iron_skin(SkillTree.get_skill("iron_skin"))
	await _wait(0.45)
	_shot(1)
	await _wait(1.0)
	p.facing = Vector2.RIGHT
	p._do_sundering_strike(SkillTree.get_skill("sundering_strike"))
	await _wait(0.3)
	_shot(2)
	await _wait(0.8)
	p._do_blade_vortex(SkillTree.get_skill("blade_vortex"))
	await _wait(0.3)
	_shot(3)
	await _wait(0.8)
	for i in 4:
		p._do_whirlwind(SkillTree.get_skill("whirlwind"))
		await _wait(0.15)
	_shot(4)
	await _wait(0.8)
	p._do_battle_cry(SkillTree.get_skill("battle_cry"))
	p._do_call_ancients(SkillTree.get_skill("ancients"))
	await _wait(0.3)
	_shot(5)
	await _wait(1.0)
	# Hit sparks of each damage type, a molten blast, a lightning strike
	var at := p.global_position + Vector2(260, 0)
	for i in SpellFx.HITS.size():
		SpellFx.spawn(main, SpellFx.HITS[i], at + Vector2(-200 + i * 100, -60), 1.3)
	SpellFx.spawn(main, "fire_explosion", at + Vector2(-120, 140))
	SpellFx.spawn(main, "lightning_strike", at + Vector2(120, 100))
	SpellFx.spawn(main, "ground_hit", p.global_position + Vector2(-300, 120))
	await _wait(0.3)
	_shot(6)
	get_tree().quit()


func _shot(n: int) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/spells_%d.png" % n))
	print("saved spells_%d" % n)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
