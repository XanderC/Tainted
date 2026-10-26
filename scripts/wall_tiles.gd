class_name WallTiles
extends RefCounted
## Picks the pieces a wall cell is drawn with, a quarter at a time, so walls of any shape join up:
## raised plateaus with a rock cliff facing the floor below them (3/4 view). The pieces are
## assets/tiles/<theme>/walls/<piece>.png, 256 px each, made by tools/import_tilesets.py; a quarter of
## a cell is drawn from the same quarter of its piece.
##   A wall cell with wall below it is plateau. Each of its quarters looks at its two side neighbours
##   and the diagonal between them (plateau or not): an outer corner (top_left, lip_right ...), an edge
##   (top, left, right, or lip at the bottom, where the cliff starts), an inner corner where two walls
##   meet (inner_tl ...), or the middle.
##   A wall cell with floor below it is the cliff face (cliff), or, with nothing above it either (a
##   wall one cell thick), a cliff with a thin ledge of plateau on top (ledge); each half has an end
##   (_left / _right) when floor is beside it.
## The map editor (tools/map_editor/map_canvas_helpers.gd) has a copy of this: keep them the same.

const PLATEAU_TOP := [["top_left", "top_right"], ["lip_left", "lip_right"]]  # [bottom][right]: outer corners
const PLATEAU_EDGE := ["top", "lip"]
const SIDE_EDGE := ["left", "right"]
const INNER := [["inner_tl", "inner_tr"], ["inner_bl", "inner_br"]]


## The pieces for wall cell `c` as [top left, top right, bottom left, bottom right] quarters;
## `wall` tells whether a cell is a wall (outside the map = wall).
static func pick(wall: Callable, c: Vector2i) -> PackedStringArray:
	var out := PackedStringArray()
	if wall.call(c + Vector2i(0, 1)):
		var plateau := func(p: Vector2i) -> bool: return wall.call(p) and wall.call(p + Vector2i(0, 1))
		for qy in 2:
			for qx in 2:
				var sx := 1 if qx == 1 else -1
				var sy := 1 if qy == 1 else -1
				var v_open: bool = not plateau.call(c + Vector2i(0, sy))
				var h_open: bool = not plateau.call(c + Vector2i(sx, 0))
				if v_open and h_open:
					out.append(PLATEAU_TOP[qy][qx])
				elif v_open:
					out.append(PLATEAU_EDGE[qy])
				elif h_open:
					out.append(SIDE_EDGE[qx])
				elif not plateau.call(c + Vector2i(sx, sy)):
					out.append(INNER[qy][qx])
				else:
					out.append("middle")
		return out
	var kind := "cliff" if wall.call(c + Vector2i(0, -1)) else "ledge"
	var left := kind if wall.call(c + Vector2i(-1, 0)) else kind + "_left"
	var right := kind if wall.call(c + Vector2i(1, 0)) else kind + "_right"
	return PackedStringArray([left, right, left, right])
