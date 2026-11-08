class_name Minimap
extends Control
## The minimap in the top right corner. It shows the map around the player as it has been explored (the
## cells within REVEAL of where they have been; what is seen is kept with the scene, so a zone kept by
## ZoneInstances is as explored as you left it), and on it the player, the exits, the waypoint, people to
## talk to, things to use, town portals, the boss, and the monsters near. Tap it (or press M) to see the
## whole map larger. Town has no maze: it shows the town's area and its people.
## Made by each scene's HUD with Minimap.add(layer, scene); it finds what to show through the scene's `player`
## and `maze` and the groups of what is in it (rift_portals, interactables, town_portals, enemies).

const VIEW_CELLS := 36.0  ## cells across the small map
const REVEAL := 12  ## cells round the player that are explored
const BIG := Vector2(480, 280)  ## the whole-map view: under the row of buttons, above the weapon swap
const FLOOR := Color(0.60, 0.53, 0.38, 0.9)
const WALL := Color(0.17, 0.14, 0.12, 0.95)

## What has been seen of one maze (kept on the scene).
class Memory:
	extends RefCounted
	var maze: MazeMap
	var seen := PackedByteArray()
	var img: Image

var scene: Node
var _mem: Memory = null
var _tex: ImageTexture = null
var _expanded := false
var _acc := 0.0
var _origin := Vector2.ZERO  # where the world's (0, 0) is on the map, and px per world px
var _k := 1.0


static func add(layer: CanvasLayer, for_scene: Node) -> Minimap:
	var m := Minimap.new()
	m.scene = for_scene
	layer.add_child(m)
	return m


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tooltip_text = "Tap to see the whole map (M)"
	_layout()


func _layout() -> void:
	var s := BIG if _expanded else Vector2(HudLayout.MAP, HudLayout.MAP)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -HudLayout.MARGIN
	offset_left = -(HudLayout.MARGIN + s.x)
	offset_top = HudLayout.BELOW_ROW if _expanded else HudLayout.ROW_TOP
	offset_bottom = offset_top + s.y


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
		or (event is InputEventScreenTouch and not event.pressed)
	if tapped:
		accept_event()
		toggle()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and not get_tree().paused:
		toggle()


func toggle() -> void:
	_expanded = not _expanded
	_layout()
	queue_redraw()


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.1:
		return
	_acc = 0.0
	_refresh()
	queue_redraw()


# ---------- what has been seen ----------

func _refresh() -> void:
	var p = scene.get("player") if is_instance_valid(scene) else null
	if not is_instance_valid(p):
		return
	var maze = scene.get("maze")
	if maze != (_mem.maze if _mem != null else null):
		_bind(maze)
	if _mem == null:
		return
	var c: Vector2i = maze.world_to_cell(p.global_position)
	var changed := false
	for dy in range(-REVEAL, REVEAL + 1):
		for dx in range(-REVEAL, REVEAL + 1):
			if dx * dx + dy * dy > REVEAL * REVEAL:
				continue
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= maze.cols or y >= maze.rows:
				continue
			var i: int = y * maze.cols + x
			if _mem.seen[i] == 0:
				_mem.seen[i] = 1
				_mem.img.set_pixel(x, y, WALL if maze.is_wall(Vector2i(x, y)) else FLOOR)
				changed = true
	if changed:
		_tex.update(_mem.img)


## The maze changed (a rift's next maze) or this is the first look: what was seen of it before comes back.
func _bind(maze) -> void:
	if maze == null:
		_mem = null
		_tex = null
		return
	var kept = scene.get_meta("minimap", null)
	if kept is Memory and kept.maze == maze:
		_mem = kept
	else:
		_mem = Memory.new()
		_mem.maze = maze
		_mem.seen.resize(maze.cols * maze.rows)
		_mem.img = Image.create(maze.cols, maze.rows, false, Image.FORMAT_RGBA8)
		scene.set_meta("minimap", _mem)
	_tex = ImageTexture.create_from_image(_mem.img)


func _seen_at(pos: Vector2) -> bool:
	if _mem == null:
		return true  # town: all of it
	var c: Vector2i = _mem.maze.world_to_cell(pos)
	if c.x < 0 or c.y < 0 or c.x >= _mem.maze.cols or c.y >= _mem.maze.rows:
		return false
	return _mem.seen[c.y * _mem.maze.cols + c.x] != 0


# ---------- drawing ----------

func _w2m(pos: Vector2) -> Vector2:
	return _origin + pos * _k


func _set_view(p: Node2D) -> void:
	if _mem != null:
		var cols: int = _mem.maze.cols
		var rows: int = _mem.maze.rows
		var cell := MazeMap.CELL
		if _expanded:
			var s := minf((size.x - 12.0) / cols, (size.y - 12.0) / rows)
			_k = s / cell
			_origin = (size - Vector2(cols, rows) * s) * 0.5
		else:
			var s := size.x / VIEW_CELLS
			_k = s / cell
			_origin = size * 0.5 - p.global_position * _k
	else:
		var r := TownMap.CAM_LIMIT
		_k = minf(size.x / r.size.x, size.y / r.size.y) * 0.92
		_origin = size * 0.5 - (r.position + r.size * 0.5) * _k


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.05, 0.74))
	var p = scene.get("player") if is_instance_valid(scene) else null
	if is_instance_valid(p):
		_set_view(p)
		if _mem != null and _tex != null:
			draw_texture_rect(_tex, Rect2(_origin, Vector2(_mem.maze.cols, _mem.maze.rows) * MazeMap.CELL * _k), false)
		elif _mem == null:
			var r := TownMap.CAM_LIMIT
			draw_rect(Rect2(_w2m(r.position), r.size * _k), Color(0.30, 0.36, 0.20, 0.55))
		_draw_markers(p)
		_draw_player(p)
	var edge := Color(0.78, 0.62, 0.34, 0.95)
	draw_rect(Rect2(Vector2.ZERO, size), edge, false, 2.0)
	if _expanded:
		draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 8), "Tap to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.85, 0.7, 0.8))


func _draw_markers(p: Node2D) -> void:
	var tree := get_tree()
	for n in tree.get_nodes_in_group("rift_portals"):
		if n.active and _seen_at(n.global_position):
			_ring(_w2m(n.global_position), 4.5, Color(0.78, 0.45, 1.0))
	for n in tree.get_nodes_in_group("town_portals"):
		if _seen_at(n.global_position):
			_ring(_w2m(n.global_position), 4.0, Color(0.55, 0.80, 1.0))
	for n in tree.get_nodes_in_group("interactables"):
		if not n.visible or not _seen_at(n.global_position):
			continue
		var at := _w2m(n.global_position)
		var prompt := String(n.get("prompt")) if n.get("prompt") != null else ""
		if prompt == "Waypoint":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5), at + Vector2(-5, 0)]), Color(0.5, 0.9, 1.0))
		elif prompt.begins_with("Talk"):
			draw_circle(at, 3.2, Color(1.0, 0.88, 0.35))
		else:
			draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.7, 0.25))
	var near := 0.0 if _expanded else VIEW_CELLS * MazeMap.CELL * 0.6
	var dots := 0
	for e in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e._dead or not _seen_at(e.global_position):
			continue
		if e.is_boss:
			var at := _w2m(e.global_position)
			draw_circle(at, 5.5, Color(0.9, 0.12, 0.1))
			draw_arc(at, 7.5, 0.0, TAU, 20, Color(1.0, 0.8, 0.6), 1.5)
		elif near > 0.0 and dots < 220 and e.global_position.distance_to(p.global_position) < near:
			draw_circle(_w2m(e.global_position), 1.7, Color(0.95, 0.3, 0.25, 0.9))
			dots += 1


func _ring(at: Vector2, r: float, col: Color) -> void:
	draw_arc(at, r, 0.0, TAU, 16, col, 2.0)
	draw_circle(at, r * 0.35, col)


func _draw_player(p: Node2D) -> void:
	var at := _w2m(p.global_position)
	var dir := Vector2.RIGHT
	var f = p.get("facing")
	if f is Vector2 and (f as Vector2).length() > 0.1:
		dir = (f as Vector2).normalized()
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([at + dir * 7.0, at - dir * 4.0 + side * 4.5, at - dir * 4.0 - side * 4.5]), Color(1, 1, 1))
	draw_polyline(PackedVector2Array([at + dir * 7.0, at - dir * 4.0 + side * 4.5, at - dir * 4.0 - side * 4.5, at + dir * 7.0]), Color(0, 0, 0, 0.8), 1.2)
