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
var _water: Array = []  # the "water" layer rows: "." none, "~" river (a wall cell), "=" bridge (a floor cell over the river)
var _terrace_cells := {}  # Vector2i -> true: cells of terraces' footprints (raised ground: Terraces)
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
	_water = data.get("water", [])
	for t in MapData.objects_of(data, "terrace"):
		for ty in int(t.h):
			for tx in int(t.w):
				_terrace_cells[Vector2i(int(t.x) + tx, int(t.y) + ty)] = true
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
	_add_roads()
	_add_rivers()
	_add_terraces()
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


## Whether a cell is river (a wall: nothing crosses it but at a bridge).
func is_water(c: Vector2i) -> bool:
	return _water_at(c) == "~"


## Whether a cell is a bridge: floor over the river.
func is_bridge(c: Vector2i) -> bool:
	return _water_at(c) == "="


## Whether a cell is part of a terrace's footprint (its raised floor, and the cliff and trees round it).
func is_terrace(c: Vector2i) -> bool:
	return _terrace_cells.has(c)


func _water_at(c: Vector2i) -> String:
	if c.y < 0 or c.y >= _water.size() or c.x < 0 or c.x >= String(_water[c.y]).length():
		return "."
	return String(_water[c.y])[c.x]


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


## Every cell that isn't a wall.
func floor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			if _grid[y][x] != "#":
				out.append(Vector2i(x, y))
	return out


## Whether a straight line from `from` to `to` crosses no wall (an archer's clear shot).
func line_clear(from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / (CELL * 0.25)) + 1
	for i in steps + 1:
		var c := world_to_cell(from.lerp(to, float(i) / steps))
		if is_wall(c) and not is_water(c):
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
			if is_water(c) or (is_terrace(c) and is_wall(c)):
				continue
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
	PropFader.attach(self, s)  # see-through with the player behind it
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
	PropFader.attach(self, s)  # see-through with the player behind it


## The map's "water" layer (optional: rows of characters, "." none, "~" river, "=" bridge): a river a cell wide, drawn
## from the pack's two river pieces (`river`: straight and flowing left to right; `river_2`: a bend from the left edge to the
## top, its outer bank at the bottom right) turned to join each cell to the river cells beside it. River cells are walls
## in the grid (nothing walks or is hit across them but at a bridge); a bridge is floor, with a cobbled deck across the
## river. Under the roads' and the walls' drawing order, over the ground.
func _add_rivers() -> void:
	if _water.is_empty():
		return
	var wet := func(c: Vector2i) -> bool: return _water_at(c) != "."
	for y in _water.size():
		for x in String(_water[y]).length():
			var c := Vector2i(x, y)
			if not wet.call(c):
				continue
			var n: bool = wet.call(c + Vector2i(0, -1))
			var e: bool = wet.call(c + Vector2i(1, 0))
			var s: bool = wet.call(c + Vector2i(0, 1))
			var w: bool = wet.call(c + Vector2i(-1, 0))
			var piece := "river"
			var turn := 0.0
			if (n or s) and not (e or w):
				turn = 90.0
			elif (n or s) and (e or w) and not ((n and s) or (e and w)):
				piece = "river_2"  # a bend: left and top as drawn; turned clockwise to the pair of sides it joins
				if n and e:
					turn = 90.0
				elif e and s:
					turn = 180.0
				elif s and w:
					turn = 270.0
			elif n and s and not (e and w):
				turn = 90.0
			var tex := MapTheme.load_sprite(theme, piece)
			if tex == null:
				continue
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.scale = Vector2(0.5, 0.5)
			sp.rotation_degrees = turn
			sp.position = cell_center(c)
			sp.z_index = -58
			add_child(sp)
			if _water_at(c) == "=":
				_add_bridge_deck(c, piece == "river" and turn == 0.0)


## The cobbled deck of a bridge cell: a strip across the river (the river runs left to right when `flows_h`).
func _add_bridge_deck(c: Vector2i, flows_h: bool) -> void:
	var tex := MapTheme.load_sprite(theme, "road_18")
	if tex == null:
		return
	var deck := Sprite2D.new()
	deck.texture = tex
	deck.scale = Vector2(1.3, 2.05) if flows_h else Vector2(2.05, 1.3)  # 83 x 131 px: a little over the cell, banks to banks
	deck.position = cell_center(c)
	deck.z_index = -57
	add_child(deck)
	for side in [-1.0, 1.0]:
		var r := ColorRect.new()
		r.color = Color(0.32, 0.22, 0.12)
		r.size = Vector2(6, 136) if flows_h else Vector2(136, 6)
		r.position = cell_center(c) + (Vector2(side * 43.0 - 3.0, -68.0) if flows_h else Vector2(-68.0, side * 43.0 - 3.0))
		r.z_index = -56
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)


## Terraces (objects of type "terrace": x, y, w, h in cells, and `stairs`, the columns of the bottom row, counted from
## the left of the footprint, that are stairs): raised ground you can walk on. The grid already makes it: a footprint
## of wall cells round floor (left, right, top, and the bottom row, which is the cliff face), with the stairs' cells in
## the cliff row left as floor. Drawn with the plateau pieces undarkened (assets/tiles/<theme>/terrace/, by
## WallTiles as a wall is, the footprint standing for the plateau), stairs (`land_13`) in the gaps; MazeMap's walls
## and decoration skip it, and a map puts trees and rocks on the ring.
func _add_terraces() -> void:
	var terraces := MapData.objects_of(data, "terrace")
	if terraces.is_empty():
		return
	var layer := TileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_size = Vector2i(128, 128)
	layer.scale = Vector2(0.5, 0.5)
	layer.z_index = -45
	add_child(layer)
	var sources := {}
	var stairs_tex := MapTheme.load_sprite(theme, "land_13")
	for t in terraces:
		var x0 := int(t.x)
		var y0 := int(t.y)
		var w := int(t.w)
		var h := int(t.h)
		var stair_cells := {}
		for sx in t.get("stairs", []):
			stair_cells[Vector2i(x0 + int(sx), y0 + h - 1)] = true
		# The plateau above the steps ends in its lip as above any cliff, so for it the steps count as footprint; the cliff
		# row's own pieces, though, end (cliff_left / cliff_right) beside the gap
		var footprint := func(c: Vector2i) -> bool: return _terrace_cells.has(c)
		var footprint_less_steps := func(c: Vector2i) -> bool: return _terrace_cells.has(c) and not stair_cells.has(c)
		for ty in h:
			for tx in w:
				var c := Vector2i(x0 + tx, y0 + ty)
				if stair_cells.has(c):
					if stairs_tex != null:
						var st := Sprite2D.new()
						st.texture = stairs_tex
						st.scale = Vector2(0.5, 0.5)
						st.position = cell_center(c)
						st.z_index = -44
						add_child(st)
					continue
				var pieces := WallTiles.pick(footprint_less_steps if ty == h - 1 else footprint, c)
				for q in 4:
					var piece := pieces[q]
					if not sources.has(piece):
						var src := TileSetAtlasSource.new()
						src.texture = load(dir + "terrace/" + piece + ".png")
						src.texture_region_size = Vector2i(128, 128)
						for qy in 2:
							for qx in 2:
								src.create_tile(Vector2i(qx, qy))
						sources[piece] = layer.tile_set.add_source(src)
					var quarter := Vector2i(q % 2, q >> 1)
					layer.set_cell(Vector2i(c.x * 2, c.y * 2) + quarter, sources[piece], quarter)


## The map's "roads" layer (optional: rows of characters, "." none, "d" dirt path, "s" cobblestone; see RoadTiles):
## paths on the ground, drawn a quarter of a cell at a time from the theme's road_N pieces, over the ground and under the
## walls and everything that stands.
func _add_roads() -> void:
	var rows_: Array = data.get("roads", [])
	if rows_.is_empty():
		return
	var kind := func(c: Vector2i) -> String:
		if c.y < 0 or c.y >= rows_.size() or c.x < 0 or c.x >= String(rows_[c.y]).length():
			return "."
		return String(rows_[c.y])[c.x]
	var is_road := func(c: Vector2i) -> bool: return kind.call(c) != "."
	var layer := TileMapLayer.new()
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_size = Vector2i(64, 64)
	layer.z_index = -60
	add_child(layer)
	var sources := {}  # road piece number -> atlas source id
	for y in rows_.size():
		for x in String(rows_[y]).length():
			var c := Vector2i(x, y)
			if not is_road.call(c):
				continue
			var pieces := RoadTiles.pick(is_road, c, kind.call(c) == "s")
			for q in 4:
				var n: int = pieces[q]
				if not sources.has(n):
					var tex := MapTheme.load_sprite(theme, "road_%d" % n)
					if tex == null:
						continue
					var src := TileSetAtlasSource.new()
					src.texture = tex
					src.texture_region_size = Vector2i(64, 64)
					src.create_tile(Vector2i(0, 0))
					sources[n] = layer.tile_set.add_source(src)
				layer.set_cell(Vector2i(x * 2 + (q % 2), y * 2 + (q >> 1)), sources[n], Vector2i(0, 0))


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
	var wall := func(c: Vector2i) -> bool: return is_wall(c) and not is_water(c) and not is_terrace(c)
	for y in rows:
		for x in cols:
			if _grid[y][x] != "#" or is_water(Vector2i(x, y)) or is_terrace(Vector2i(x, y)):
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
