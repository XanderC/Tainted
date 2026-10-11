class_name WallTiles
extends RefCounted
## Picks the desert tileset piece for a wall cell from its neighbours, so walls are drawn as
## raised plateaus with rock cliffs facing the floor (land_N.png in assets/tiles/desert):
##   plateau top:  1 2 3 / 15 6 16      bottom lip (row above a cliff): 9 18 11
##   cliff face (wall with floor just below it): 12 left end, 17 middle, 14 right end
## The map editor (tools/map_editor/map_canvas.gd) has a copy of this: keep them the same.


## Tile name for wall cell `c`; `wall` tells whether a cell is a wall (outside the map = wall).
static func pick(wall: Callable, c: Vector2i) -> String:
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
