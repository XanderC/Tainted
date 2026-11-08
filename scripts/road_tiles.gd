class_name RoadTiles
extends RefCounted
## Picks the pieces a road cell is drawn with, a quarter at a time (the same way WallTiles draws walls), so roads and
## paths of any shape join up. The pieces are the pack's road_N.png (64 px, the size of a quarter of a 128 px
## cell), in the theme's folder. There are two sets of 13: dirt (road_1 ... 13) and cobblestone (road_14 ... 26),
## each laid out the same way:
##   1 top-left corner   2 top edge     3 top-right corner
##   4 left edge         5 middle       6 right edge
##   7 bottom-left       8 bottom edge  9 bottom-right
##   10 inner corner bottom-right, 11 bottom-left, 12 top-right, 13 top-left (a notch where two roads meet)
## A map's "roads" layer is rows of characters, one per cell: "." none, "d" dirt path, "s" cobblestone.
## Each quarter of a road cell looks at the cell beside it, up or down and left or right, and the one diagonally
## between: an outer corner, an edge, an inner corner or the middle. A road of one cell width is all edges.

const STONE_OFFSET := 13  ## cobblestone piece = the dirt piece's number + this

const CORNERS := [[1, 3], [7, 9]]  # [bottom][right]
const V_EDGE := [2, 8]  # top, bottom
const H_EDGE := [4, 6]  # left, right
const INNER := [[13, 12], [11, 10]]  # [bottom][right]: which diagonal is missing
const MIDDLE := 5


## The road_N number of each quarter of road cell `c` as [top left, top right, bottom left, bottom right];
## `is_road` tells whether a cell has a road (outside the map: none); `stone` picks the cobblestone set.
static func pick(is_road: Callable, c: Vector2i, stone := false) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := STONE_OFFSET if stone else 0
	for qy in 2:
		for qx in 2:
			var sx := 1 if qx == 1 else -1
			var sy := 1 if qy == 1 else -1
			var v_open: bool = not is_road.call(c + Vector2i(0, sy))
			var h_open: bool = not is_road.call(c + Vector2i(sx, 0))
			var n := MIDDLE
			if v_open and h_open:
				n = CORNERS[qy][qx]
			elif v_open:
				n = V_EDGE[qy]
			elif h_open:
				n = H_EDGE[qx]
			elif not is_road.call(c + Vector2i(sx, sy)):
				n = INNER[qy][qx]
			out.append(n + base)
	return out
