class_name MazeMap
extends Node2D
## One map built from a JSON map file (MapData, made with the map editor), in the look of its theme
## (MapTheme): the theme's floor, raised walls with collision (WallTiles), placed props (plus random
## trees and stones when "auto_decorate" is on), and an AStarGrid2D so monsters can find their way to
## the player.
## Cell (x, y) covers world rect [x*CELL, y*CELL] .. +CELL.

const CELL := 128.0

var map_id := ""
var map_name := ""
var theme := MapTheme.DEFAULT
var dir := MapTheme.dir(MapTheme.DEFAULT)  # the theme's pictures
var data := {}      # the whole map file (objects include NPCs and story triggers for scenes to use)
var cols := 0
var rows := 0
var start_pos := Vector2.ZERO
var portal_pos := Vector2.ZERO
var group_spots: Array[Vector2] = []
var packs: Array = []    # pack objects ({x, y, min, max}), same order as group_spots
var markers := {}  # marker id -> Array of positions (e.g. the tutorial's "A")
var portals: Array = []  # portal objects ({x, y, target})

var _grid: Array[String] = []
var _astar := AStarGrid2D.new()
var _rng := RandomNumberGenerator.new()


## Build from a map file (MapData id). Call before adding to the tree.
func setup(id: String) -> void:
	map_id = id
	data = MapData.load_map(id)
	map_name = String(data.get("name", id))
	theme = String(data.get("theme", MapTheme.DEFAULT))
	dir = MapTheme.dir(theme)
	_grid.assign(data.get("grid", ["#"]))
	rows = _grid.size()
	cols = _grid[0].length()
	_rng.seed = hash(id)
	_astar.region = Rect2i(0, 0, cols, rows)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in rows:
		for x in cols:
			if _grid[y][x] == "#":
				_astar.set_point_solid(Vector2i(x, y), true)
	for o in data.get("objects", []):
		var pos := Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
		match String(o.get("type", "")):
			"start": start_pos = pos
			"portal":
				portals.append(o)
				if portals.size() == 1:
					portal_pos = pos
			"pack":
				group_spots.append(pos)
				packs.append(o)
			"marker":
				var mid := String(o.get("id", ""))
				if not markers.has(mid):
					markers[mid] = []
				markers[mid].append(pos)


func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_add_ground()
	_add_walls()
	_add_wall_collision()
	if data.get("auto_decorate", true):
		_decorate()
	for o in MapData.objects_of(data, "tile"):
		_placed_tile(o)
	for o in MapData.objects_of(data, "prop"):
		_placed_prop(o)


# ---------- queries ----------

func is_wall(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return true
	return _grid[c.y][c.x] == "#"


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


## Whether a straight line from `from` to `to` crosses no wall (an archer's clear shot).
func line_clear(from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / (CELL * 0.25)) + 1
	for i in steps + 1:
		if is_wall(world_to_cell(from.lerp(to, float(i) / steps))):
			return false
	return true


## Where a monster at `from` should head next to reach `to` (straight there once close).
func path_next(from: Vector2, to: Vector2) -> Vector2:
	var a := world_to_cell(from)
	var b := world_to_cell(to)
	if a == b or is_wall(a) or is_wall(b):
		return to
	var path := _astar.get_id_path(a, b)
	if path.size() < 2:
		return to
	if path.size() == 2:
		return to
	return cell_center(path[1])


## A random floor point between min_d and max_d from `around` (falls back to `around`).
func random_floor_near(around: Vector2, min_d: float, max_d: float) -> Vector2:
	for i in 60:
		var p := around + Vector2.from_angle(randf() * TAU) * randf_range(min_d, max_d)
		var c := world_to_cell(p)
		if not is_wall(c) and not is_wall(c + Vector2i(1, 0)) and not is_wall(c + Vector2i(-1, 0)):
			return cell_center(c)
	return around


# ---------- building ----------

func _add_ground() -> void:
	var g := Sprite2D.new()
	g.texture = load(dir + "bg.png")
	g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	g.region_enabled = true
	g.centered = false
	g.region_rect = Rect2(0, 0, cols * CELL * 2.0, rows * CELL * 2.0)
	g.scale = Vector2(0.5, 0.5)
	g.z_index = -100
	add_child(g)


## One box per horizontal run of wall cells, so a maze needs only a few dozen shapes.
func _add_wall_collision() -> void:
	var body := StaticBody2D.new()
	add_child(body)
	for y in rows:
		var x := 0
		while x < cols:
			if _grid[y][x] != "#":
				x += 1
				continue
			var start := x
			while x < cols and _grid[y][x] == "#":
				x += 1
			var cs := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2((x - start) * CELL, CELL)
			cs.shape = rect
			cs.position = Vector2((start + (x - start) * 0.5) * CELL, (y + 0.5) * CELL)
			body.add_child(cs)


func _decorate() -> void:
	var t := MapTheme.data(theme)
	var wall_props: Array = t.wall_props
	var floor_props: Array = t.floor_props
	var plateau_props: Array = t.plateau_props
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			var base := Vector2(x * CELL, (y + 1) * CELL)
			if is_wall(c):
				# Trees and boulders along wall edges that face the floor (not on the cliff faces),
				# and now and then a big rock or tree out in the middle of a wide plateau
				if not is_wall(c + Vector2i(0, 1)):
					continue
				var faces_floor := not is_wall(c + Vector2i(1, 0)) \
					or not is_wall(c + Vector2i(-1, 0)) or not is_wall(c + Vector2i(0, -1))
				if not faces_floor and _interior(c) and _rng.randf() < float(t.plateau_chance):
					var pp: Array = plateau_props[_rng.randi() % plateau_props.size()]
					_prop(pp[0], base + Vector2(0.5 * CELL, -0.2 * CELL), pp[1])
				elif faces_floor and _rng.randf() < float(t.wall_chance):
					var wp: Array = wall_props[_rng.randi() % wall_props.size()]
					_prop(wp[0], base + Vector2(_rng.randf_range(0.25, 0.75) * CELL, -_rng.randf_range(0.1, 0.4) * CELL), wp[1])
			elif _grid[y][x] == "." and _rng.randf() < 0.08:
				var fp: Array = floor_props[_rng.randi() % floor_props.size()]
				_prop(fp[0], base + Vector2(_rng.randf_range(0.2, 0.8) * CELL, -_rng.randf_range(0.2, 0.6) * CELL), fp[1])


## A flat ground piece (plateau, cliff, stairs, road) painted in the editor: under walls and characters.
func _placed_tile(o: Dictionary) -> void:
	var tex := MapTheme.load_sprite(theme, String(o.get("sprite", "")))
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	var sc := float(o.get("scale", 0.5))
	s.scale = Vector2(sc, sc)
	s.position = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	s.z_index = -50
	add_child(s)


## A prop placed in the editor (exact spot and scale; "solid" ones block movement).
func _placed_prop(o: Dictionary) -> void:
	var tex := MapTheme.load_sprite(theme, String(o.get("sprite", "")))
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.9)
	var sc := float(o.get("scale", 0.5))
	s.scale = Vector2(sc, sc)
	s.position = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	add_child(s)
	if o.get("solid", false):
		var body := StaticBody2D.new()
		body.position = s.position
		var cs := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = tex.get_width() * sc * 0.3
		cs.shape = circle
		body.add_child(cs)
		add_child(body)


## True when the cell and all 8 around it are walls (room for a big prop on the plateau).
func _interior(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not is_wall(c + Vector2i(dx, dy)):
				return false
	return true


func _prop(name_: String, pos: Vector2, sc := 0.5) -> void:
	var tex := MapTheme.load_sprite(theme, name_)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.9)
	s.scale = Vector2(sc, sc) * _rng.randf_range(0.9, 1.15)
	s.position = pos
	add_child(s)


## Walls: raised plateaus with rock cliffs facing the floor, drawn a quarter cell at a time (WallTiles
## picks each quarter's piece). A tile layer at half scale: its 128 px tiles are the pieces' quarters.
func _add_walls() -> void:
	var layer := TileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_size = Vector2i(128, 128)
	layer.scale = Vector2(0.5, 0.5)
	layer.z_index = -40  # over the ground and painted tiles, under everything standing
	add_child(layer)
	var sources := {}  # piece -> atlas source id
	var wall := func(c: Vector2i) -> bool: return is_wall(c)
	for y in rows:
		for x in cols:
			if _grid[y][x] != "#":
				continue
			var pieces := WallTiles.pick(wall, Vector2i(x, y))
			for q in 4:
				var piece := pieces[q]
				if not sources.has(piece):
					var src := TileSetAtlasSource.new()
					src.texture = load(dir + "walls/" + piece + ".png")
					src.texture_region_size = Vector2i(128, 128)
					for ty in 2:
						for tx in 2:
							src.create_tile(Vector2i(tx, ty))
					sources[piece] = layer.tile_set.add_source(src)
				var quarter := Vector2i(q % 2, q >> 1)
				layer.set_cell(Vector2i(x * 2, y * 2) + quarter, sources[piece], quarter)
