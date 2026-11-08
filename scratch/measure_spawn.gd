extends Node2D
## What one monster costs to build: the first of each kind (art loading) against the rest.
## godot --path . res://scratch/measure_spawn.tscn


func _ready() -> void:
	var out: Array[String] = []
	for round_ in 3:
		var t0 := Time.get_ticks_usec()
		var made: Array[Enemy] = []
		for kind in ["zombie", "skeleton", "goblin", "villager", "ghoul", "mummy", "bandit_archer", "skeleton_archer"]:
			for i in 10:
				var e := Enemy.new()
				e.max_hp = 25.0
				e.set_kind(kind)
				add_child(e)
				made.append(e)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		out.append("round %d: %d monsters in %.0f ms = %.1f ms each" % [round_ + 1, made.size(), ms, ms / made.size()])
		# split one monster's cost: new+set_kind vs add_child (the rig's _ready)
		var a0 := Time.get_ticks_usec()
		var e2 := Enemy.new()
		e2.set_kind("zombie")
		var a1 := Time.get_ticks_usec()
		add_child(e2)
		var a2 := Time.get_ticks_usec()
		out.append("   one zombie: new+set_kind %.2f ms, add_child %.2f ms" % [(a1 - a0) / 1000.0, (a2 - a1) / 1000.0])
		for e in made:
			e.queue_free()
		e2.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	for l in out:
		print(l)
	var f := FileAccess.open("res://scratch/measure_spawn.log", FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	get_tree().quit()
