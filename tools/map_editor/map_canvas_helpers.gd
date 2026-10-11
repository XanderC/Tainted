class_name MapCanvasHelpers
extends RefCounted
## Small queries on a map document.


## land_ and road_ pictures are flat ground tiles; everything else stands up as a prop.
static func is_ground_tile(sprite: String) -> bool:
	return sprite.begins_with("land_") or sprite.begins_with("road_")


## Copy of the game's scripts/wall_tiles.gd (keep the two the same): which desert tile a wall cell
## is drawn with - plateau top 1 2 3 / 15 6 16, bottom lip 9 18 11, cliff face 12 17 14.
## Tile name for wall cell `c`; `wall` tells whether a cell is a wall (outside the map = wall).
static func wall_tile(wall: Callable, c: Vector2i) -> String:
	var n: bool = wall.call(c + Vector2i(0, -1))
	var s: bool = wall.call(c + Vector2i(0, 1))
	var w: bool = wall.call(c + Vector2i(-1, 0))
	var e: bool = wall.call(c + Vector2i(1, 0))
	if not s:  # floor below: the cliff face you see from the south
		if not w and e:
			return "land_12"
		if not e and w:
			return "land_14"
		return "land_17"
	var cliff_below: bool = not wall.call(c + Vector2i(0, 2))
	if cliff_below and n:  # the plateau's bottom lip, just above its cliff
		if not w:
			return "land_9"
		if not e:
			return "land_11"
		return "land_18"
	if not n:
		if not w:
			return "land_1"
		if not e:
			return "land_3"
		return "land_2"
	if not w:
		return "land_15"
	if not e:
		return "land_16"
	return "land_6"


static func count(map: Dictionary, type: String) -> int:
	return map.get("objects", []).filter(func(o): return String(o.get("type", "")) == type).size()
