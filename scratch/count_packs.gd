extends SceneTree
## How many packs and monsters each map gets, with and without PackSpots' extras (scratch/count_packs.log).
## godot --headless --path . -s res://scratch/count_packs.gd


func _init() -> void:
	var lines: Array[String] = []
	for id in ["bone_labyrinth", "scorched_halls", "sunken_courtyards", "twin_oasis", "dune_wastes"]:
		var m := MazeMap.new()
		m.setup(id)
		var cells := m.floor_cells().size()
		var density := 10.0 if id == "dune_wastes" else 8.0
		var spots := PackSpots.for_map(m, density)
		var hand := m.packs.size()
		var lo := 0
		var hi := 0
		for o in spots:
			lo += int(o.get("min", 3))
			hi += int(o.get("max", 5))
		var old_lo := 0
		var old_hi := 0
		for o in m.packs:
			old_lo += int(o.get("min", 3))
			old_hi += int(o.get("max", 5))
		# the nearest two packs, to check the spacing, and the closest any pack is to the start
		var nearest := INF
		var from_start := INF
		for i in spots.size():
			var a := Vector2(float(spots[i].x), float(spots[i].y))
			from_start = minf(from_start, a.distance_to(m.start_pos))
			for j in range(i + 1, spots.size()):
				nearest = minf(nearest, a.distance_to(Vector2(float(spots[j].x), float(spots[j].y))))
		lines.append("%-18s floor %4d cells | hand-placed %2d packs (%3d-%3d monsters) -> now %2d packs (%3d-%3d) | closest pair %4.0f px, closest to start %4.0f px" % [
			id, cells, hand, old_lo, old_hi, spots.size(), lo, hi, nearest, from_start])
		# same spots again for the same map? (a zone must look the same every visit)
		var again := PackSpots.for_map(m, density)
		for i in spots.size():
			if spots[i].x != again[i].x or spots[i].y != again[i].y:
				lines.append("  !! %s: the extra packs changed between two calls" % id)
				break
	var f := FileAccess.open("res://scratch/count_packs.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
