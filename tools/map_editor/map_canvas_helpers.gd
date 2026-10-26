class_name MapCanvasHelpers
extends RefCounted
## Small queries on a map document.


## land_ and road_ pictures are flat ground tiles; everything else stands up as a prop.
static func is_ground_tile(sprite: String) -> bool:
	return sprite.begins_with("land_") or sprite.begins_with("road_")


## Copy of the game's scripts/wall_tiles.gd (keep the two the same): the pieces a wall cell is drawn
## with (assets/tiles/<theme>/walls/<piece>.png), as [top left, top right, bottom left, bottom right]
## quarters; `wall` tells whether a cell is a wall (outside the map = wall).
const PLATEAU_TOP := [["top_left", "top_right"], ["lip_left", "lip_right"]]  # [bottom][right]: outer corners
const PLATEAU_EDGE := ["top", "lip"]
const SIDE_EDGE := ["left", "right"]
const INNER := [["inner_tl", "inner_tr"], ["inner_bl", "inner_br"]]


## The pieces for wall cell `c` as [top left, top right, bottom left, bottom right] quarters;
## `wall` tells whether a cell is a wall (outside the map = wall).
static func wall_pieces(wall: Callable, c: Vector2i) -> PackedStringArray:
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


static func count(map: Dictionary, type: String) -> int:
	return map.get("objects", []).filter(func(o): return String(o.get("type", "")) == type).size()
