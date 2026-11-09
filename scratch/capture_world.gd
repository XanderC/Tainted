extends Node2D
## Screenshots of the world events and the mini-dungeons in play: scratch/world_*.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_world.tscn


func shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/" + n))


func settle(s := 0.5) -> void:
	await get_tree().create_timer(s).timeout


func _zone(id: String, origin := "") -> Zone:
	GameState.current_zone = id
	GameState.zone_entry = "start"
	GameState.mini_origin = origin
	var z: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(z)
	return z


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	var zone := _zone("dune_wastes")
	await settle(1.2)
	var p: Player = zone.player
	for e in zone.get_children().filter(func(n): return n is ZoneEncounters):
		e.queue_free()
	for kind in ["shrine", "rift", "pilgrim", "pyre"]:
		var enc := ZoneEncounters.roll(zone, kind)
		p.global_position = enc.pos + Vector2(0, 330)
		await settle(0.6)
		if kind == "shrine":
			enc._it.action.call()
		elif kind == "pyre":
			enc._it.action.call()
		p.hp = p.stats.get_stat("max_life")
		await settle(1.6)
		shot("world_%s.png" % kind)
		for f in enc.foes.duplicate():
			if is_instance_valid(f):
				f.queue_free()
		for s in enc.spires:
			if is_instance_valid(s):
				s.queue_free()
		enc.queue_free()
		await settle(0.3)
	var md := MiniDungeons.roll(zone, Vector2(INF, INF), "mini_fissure")
	p.global_position = md.global_position + Vector2(0, 220)
	await settle(0.5)
	shot("world_entrance.png")
	zone.queue_free()
	await settle(0.4)
	zone = _zone("mini_fissure", "dune_wastes")
	await settle(1.5)
	zone.player.global_position = zone.maze.markers["chest"][0] + Vector2(-250, 100)
	await settle(0.8)
	shot("world_fissure.png")
	zone.queue_free()
	await settle(0.4)
	zone = _zone("mini_bonepit", "dune_wastes")
	await settle(1.5)
	zone.player.global_position = zone.maze.markers["pit"][0] + Vector2(0, 40)
	await settle(1.5)
	shot("world_bonepit.png")
	get_tree().quit()
