class_name PackSpots
extends RefCounted
## Where a map's monsters stand. The packs placed by hand in the map editor (MapData "pack" objects)
## leave long empty stretches between them, so this adds small packs of its own across the floor:
## roughly one for every `cells_per_pack` floor cells, never near another pack, the start, an exit,
## or anything the map placed on purpose (a waypoint, an NPC, a boss). A spot is {x, y, min, max}
## like the map's own. The hand-placed spots come first, untouched.

const SPACING := 400.0     # under a pack's wake-up range (520): a fight can pull in the pack next door, and sometimes two
const SIZE := Vector2i(2, 4)  # the extra packs are small; the hand-placed ones keep their own sizes
## What stays clear of each kind of map object (pixels).
const KEEP_CLEAR := {"start": 650.0, "portal": 320.0, "waypoint": 450.0, "npc": 350.0, "boss": 450.0,
	"quest_object": 300.0, "marker": 300.0}


## The map's pack spots plus the extra ones. The extras are the same every time for one map
## (`seed_` < 0: from the map's id), or differ with `seed_`, as a rift's should.
static func for_map(maze: MazeMap, cells_per_pack: float, seed_ := -1) -> Array:
	var spots: Array = maze.packs.duplicate()
	var cells := maze.floor_cells()
	var want := int(cells.size() / cells_per_pack) - spots.size()
	if want <= 0:
		return spots

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(maze.map_id) if seed_ < 0 else seed_
	for i in range(cells.size() - 1, 0, -1):  # shuffled, so the extras aren't all in one corner
		var j := rng.randi_range(0, i)
		var t := cells[i]
		cells[i] = cells[j]
		cells[j] = t

	var clear: Array = []  # [position, distance]
	for o in maze.data.get("objects", []):
		var r: float = KEEP_CLEAR.get(String(o.get("type", "")), 0.0)
		if r > 0.0:
			clear.append([Vector2(float(o.get("x", 0)), float(o.get("y", 0))), r])
	var taken: Array[Vector2] = []
	for o in spots:
		taken.append(Vector2(float(o.x), float(o.y)))

	var added := 0
	for c in cells:
		if added >= want:
			break
		var p := maze.cell_center(c)
		if _near(p, clear) or _too_close(p, taken):
			continue
		taken.append(p)
		spots.append({"type": "pack", "x": p.x, "y": p.y, "min": SIZE.x, "max": SIZE.y})
		added += 1
	return spots


static func _near(p: Vector2, clear: Array) -> bool:
	for c in clear:
		if p.distance_to(c[0]) < float(c[1]):
			return true
	return false


static func _too_close(p: Vector2, taken: Array[Vector2]) -> bool:
	for t in taken:
		if p.distance_squared_to(t) < SPACING * SPACING:
			return true
	return false
