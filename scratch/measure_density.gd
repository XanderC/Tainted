extends Node2D
## Loads the Blackroot Wilds zone and a rift, and reports how long each took to build, how many monsters
## it made and the frame time afterwards, with a screenshot from the same spot each
## (scratch/density_*.png, scratch/density.log). A different tag per run: MEASURE_TAG=old|new.
## godot --path . --resolution 1600x720 res://scratch/measure_density.tscn

var _log: Array[String] = []
var _tag := OS.get_environment("MEASURE_TAG")


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	await _measure_zone()
	await _measure_rift()
	var f := FileAccess.open("res://scratch/density.log", FileAccess.WRITE_READ)
	f.seek_end()
	f.store_string("\n".join(_log) + "\n")
	f.close()
	get_tree().quit()


func _measure_zone() -> void:
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var t0 := Time.get_ticks_usec()
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var n := get_tree().get_nodes_in_group("enemies").size()
	# Walk to the middle of the map (the nearest hand-placed pack to its centre) and let things settle
	var centre := Vector2(zone.maze.cols, zone.maze.rows) * MazeMap.CELL * 0.5
	var best: Vector2 = zone.maze.start_pos
	for o in zone.maze.packs:
		var p := Vector2(float(o.x), float(o.y))
		if p.distance_to(centre) < best.distance_to(centre):
			best = p
	zone.player.global_position = best + Vector2(-380, 40)
	await _settle()
	_stats("zone (Blackroot Wilds)", build_ms, n)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/density_zone_%s.png" % _tag))
	zone.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _measure_rift() -> void:
	GameState.test_map = "bone_labyrinth"
	var t0 := Time.get_ticks_usec()
	var rift = load("res://scenes/main.tscn").instantiate()
	add_child(rift)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var n := get_tree().get_nodes_in_group("enemies").size()
	var centre := Vector2(rift.maze.cols, rift.maze.rows) * MazeMap.CELL * 0.5
	var best: Vector2 = rift.maze.start_pos
	for o in rift.maze.packs:
		var p := Vector2(float(o.x), float(o.y))
		if p.distance_to(centre) < best.distance_to(centre):
			best = p
	rift.player.global_position = best + Vector2(-380, 40)
	await _settle()
	_stats("rift (Bone Labyrinth)", build_ms, n)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/density_rift_%s.png" % _tag))
	rift.queue_free()


var _avg_ms := 0.0
var _worst_ms := 0.0


## 60 frames to settle (the load, the first draws), then 180 timed: the average and worst frame.
func _settle() -> void:
	for i in 60:
		await get_tree().process_frame
	var total := 0.0
	_worst_ms = 0.0
	var last := Time.get_ticks_usec()
	for i in 180:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		total += ms
		_worst_ms = maxf(_worst_ms, ms)
	_avg_ms = total / 180.0


func _stats(what: String, build_ms: float, monsters: int) -> void:
	var awake := 0
	var animating := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e._aggro:
			awake += 1
		if e.rig != null and e.rig.is_processing():
			animating += 1
	var line := "[%s] %-22s built in %6.0f ms, %3d monsters (%d awake, %d animating), %d draw calls, frame avg %.1f ms worst %.1f ms, physics %.2f ms, %d nodes" % [
		_tag, what, build_ms, monsters, awake, animating,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		_avg_ms, _worst_ms,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	print(line)
	_log.append(line)
