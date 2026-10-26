class_name MapCanvas
extends Control
## The map view: draws a map document (same format as the game's res://maps/*.json, see the
## game's scripts/map_data.gd) the way the game shows it, and turns mouse input into edits.
##   Left mouse   - use the current tool (paint walls/floor, drag a rectangle, place, select/move)
##   Right / middle drag - pan        Wheel - zoom at the cursor
## The editor (editor.gd) owns the document and the history; the canvas reports through signals.

signal edited                    # the map changed (after an undo snapshot was taken)
signal about_to_edit             # take an undo snapshot now
signal selection_changed(index: int)
signal hovered(cell: Vector2i, world: Vector2)

const WALL_COLOR := Color(0.36, 0.24, 0.15)
const PICK_RADIUS := 40.0

var map := {}            # the document (grid + objects)
var tool := "wall"       # wall | floor | rect_wall | rect_floor | select | start | portal | pack | marker | prop | tile | npc | trigger
var brush := 1
var snap := true
var prop_sprite := ""
var tile_sprite := ""
var tile_scale := 0.5    # ground tiles: 0.5 matches the game's art scale (land = 1 cell, road = 1/4 cell)
var selected := -1       # index into map.objects
var textures := {}       # sprite name -> Texture2D (loaded by the editor from the game's assets)
var wall_textures := {}  # wall piece -> Texture2D (the theme's walls/)
var tiles_root := ""     # the game's assets/tiles: where "<theme>/<name>" sprites borrowed from another theme are
var bg: Texture2D

var zoom := 0.35
var pan := Vector2(40, 40)
var _panning := false
var _painting := false
var _painting_tiles := false
var _rect_from := Vector2i(-1, -1)
var _rect_to := Vector2i(-1, -1)
var _dragging := false
var _hover := Vector2.ZERO
var _labels: Array = []  # [world pos, text, colour] drawn on top at a fixed screen size


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func cell_size() -> float:
	return float(map.get("cell", 128))


func cols() -> int:
	return String(map.grid[0]).length() if map.has("grid") and not map.grid.is_empty() else 0


func rows() -> int:
	return map.grid.size() if map.has("grid") else 0


func to_world(s: Vector2) -> Vector2:
	return (s - pan) / zoom


func to_screen(w: Vector2) -> Vector2:
	return w * zoom + pan


func cell_at(w: Vector2) -> Vector2i:
	return Vector2i(int(floor(w.x / cell_size())), int(floor(w.y / cell_size())))


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell_size()


func is_wall(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= cols() or c.y >= rows():
		return true
	return String(map.grid[c.y])[c.x] == "#"


func set_cell(c: Vector2i, wall: bool) -> void:
	if c.x < 0 or c.y < 0 or c.x >= cols() or c.y >= rows():
		return
	var row := String(map.grid[c.y])
	map.grid[c.y] = row.substr(0, c.x) + ("#" if wall else ".") + row.substr(c.x + 1)


## Fit the whole map in view.
func frame_map() -> void:
	if cols() == 0 or size.x <= 0:
		return
	var w := cols() * cell_size()
	var h := rows() * cell_size()
	zoom = clampf(minf((size.x - 40) / w, (size.y - 40) / h), 0.05, 2.0)
	pan = (size - Vector2(w, h) * zoom) * 0.5
	queue_redraw()


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if map.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if mb.pressed:
				_press(to_world(mb.position))
			else:
				_release()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover = to_world(mm.position)
		hovered.emit(cell_at(_hover), _hover)
		if _panning:
			pan += mm.relative
		elif _painting:
			_paint(cell_at(_hover))
		elif _painting_tiles:
			_put_tile(_hover)
		elif _rect_from.x >= 0:
			_rect_to = cell_at(_hover)
		elif _dragging and selected >= 0:
			var p := _snapped(_hover, String(map.objects[selected].type))
			map.objects[selected].x = p.x
			map.objects[selected].y = p.y
			edited.emit()
		queue_redraw()


func _zoom_at(at: Vector2, f: float) -> void:
	var before := to_world(at)
	zoom = clampf(zoom * f, 0.05, 3.0)
	pan = at - before * zoom
	queue_redraw()


func _press(w: Vector2) -> void:
	match tool:
		"wall", "floor":
			about_to_edit.emit()
			_painting = true
			_paint(cell_at(w))
		"rect_wall", "rect_floor":
			_rect_from = cell_at(w)
			_rect_to = _rect_from
		"tile":
			if tile_sprite != "":
				about_to_edit.emit()
				_painting_tiles = true
				_put_tile(w)
		"select":
			_select(_pick(w))
			if selected >= 0:
				about_to_edit.emit()
				_dragging = true
		_:
			_place(w)
	queue_redraw()


func _release() -> void:
	if _rect_from.x >= 0:
		about_to_edit.emit()
		var a := Vector2i(mini(_rect_from.x, _rect_to.x), mini(_rect_from.y, _rect_to.y))
		var b := Vector2i(maxi(_rect_from.x, _rect_to.x), maxi(_rect_from.y, _rect_to.y))
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				set_cell(Vector2i(x, y), tool == "rect_wall")
		_rect_from = Vector2i(-1, -1)
		edited.emit()
	_painting = false
	_painting_tiles = false
	if _dragging:
		_dragging = false
		selection_changed.emit(selected)  # so the inspector shows the new position
	queue_redraw()


## The picture for `sprite`: one of the map's theme, or "<theme>/<name>" from another theme.
func texture(sprite: String) -> Texture2D:
	if not textures.has(sprite) and "/" in sprite and tiles_root != "":
		var img := Image.load_from_file(tiles_root.path_join(sprite + ".png"))
		textures[sprite] = ImageTexture.create_from_image(img) if img != null else null
	return textures.get(sprite)


## Ground tiles snap to a grid the size of the tile; painting over a spot replaces what's there.
func tile_step(sprite: String, sc: float) -> Vector2:
	var tex := texture(sprite)
	return (tex.get_size() if tex != null else Vector2(256, 256)) * sc


func _put_tile(w: Vector2) -> void:
	var step := tile_step(tile_sprite, tile_scale)
	var p := (w / step).floor() * step
	for i in range(map.objects.size() - 1, -1, -1):
		var o: Dictionary = map.objects[i]
		if o.type == "tile" and is_equal_approx(float(o.x), p.x) and is_equal_approx(float(o.y), p.y):
			if String(o.sprite) == tile_sprite and is_equal_approx(float(o.get("scale", 0.5)), tile_scale):
				return  # already painted
			map.objects.remove_at(i)
	map.objects.append({"type": "tile", "x": p.x, "y": p.y, "sprite": tile_sprite, "scale": tile_scale})
	selected = -1
	edited.emit()


func _paint(c: Vector2i) -> void:
	var r := brush - 1
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			set_cell(Vector2i(x, y), tool == "wall")
	edited.emit()


## Objects snap to cell centres (props move freely); start is unique so it moves instead.
func _snapped(w: Vector2, type: String) -> Vector2:
	if snap and type != "prop":
		return cell_center(cell_at(w))
	return w.round()


func _place(w: Vector2) -> void:
	if tool == "prop" and prop_sprite == "":
		return
	about_to_edit.emit()
	var p := _snapped(w, tool)
	if tool == "start":
		for i in map.objects.size():
			if map.objects[i].type == "start":
				map.objects[i].x = p.x
				map.objects[i].y = p.y
				_select(i)
				edited.emit()
				return
	var o := {"type": tool, "x": p.x, "y": p.y}
	match tool:
		"portal": o.target = ""
		"pack":
			o.min = 3
			o.max = 5
		"marker": o.id = "marker_%d" % map.objects.size()
		"prop":
			o.sprite = prop_sprite
			o.scale = 0.5
			o.solid = false
		"npc":
			o.id = "npc_%d" % map.objects.size()
			o.name = "Stranger"
			o.dialogue = ""
		"trigger":
			o.id = "trigger_%d" % map.objects.size()
			o.radius = 150
			o.text = ""
	map.objects.append(o)
	_select(map.objects.size() - 1)
	edited.emit()


func _pick(w: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS / maxf(zoom, 0.2)
	for i in map.objects.size():
		var o: Dictionary = map.objects[i]
		var d := w.distance_to(Vector2(float(o.x), float(o.y)) + (Vector2(0, -30) if o.type == "prop" else Vector2.ZERO))
		if o.type != "tile" and d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return best
	for i in range(map.objects.size() - 1, -1, -1):
		var o: Dictionary = map.objects[i]
		if o.type == "tile":
			var r := Rect2(Vector2(float(o.x), float(o.y)), tile_step(String(o.sprite), float(o.get("scale", 0.5))))
			if r.has_point(w):
				return i
	return -1


func _select(i: int) -> void:
	selected = i
	selection_changed.emit(i)


func delete_selected() -> void:
	if selected < 0:
		return
	about_to_edit.emit()
	map.objects.remove_at(selected)
	_select(-1)
	edited.emit()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and has_focus() and event is InputEventKey \
			and event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		delete_selected()


# ---------- drawing ----------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	if map.is_empty() or cols() == 0:
		return
	var cs := cell_size()
	var w := cols() * cs
	var h := rows() * cs
	# Desert floor: the game draws bg.png at half size, tiled
	if bg != null:
		draw_set_transform(pan, 0.0, Vector2(zoom, zoom) * 0.5)
		draw_texture_rect(bg, Rect2(0, 0, w * 2.0, h * 2.0), true)
	draw_set_transform(pan, 0.0, Vector2(zoom, zoom))
	# Ground tiles (flat, under the walls)
	for i in map.objects.size():
		var o: Dictionary = map.objects[i]
		if o.type == "tile":
			var tex := texture(String(o.sprite))
			var r := Rect2(Vector2(float(o.x), float(o.y)), tile_step(String(o.sprite), float(o.get("scale", 0.5))))
			if tex != null:
				draw_texture_rect(tex, r, false)
			if i == selected:
				draw_rect(r, Color.WHITE, false, 3.0 / zoom)
	# Walls, like the game: plateau tops with rock cliffs facing the floor, a quarter cell at a time
	var wall := func(c: Vector2i) -> bool: return is_wall(c)
	var q := cs * 0.5
	for y in rows():
		var row := String(map.grid[y])
		for x in row.length():
			if row[x] != "#":
				continue
			var pieces := MapCanvasHelpers.wall_pieces(wall, Vector2i(x, y))
			for i in 4:
				var r := Rect2(x * cs + (i % 2) * q, y * cs + (i >> 1) * q, q, q)
				var tex: Texture2D = wall_textures.get(pieces[i])
				if tex == null:
					draw_rect(r, WALL_COLOR)
				else:
					draw_texture_rect_region(tex, r, Rect2((i % 2) * 128, (i >> 1) * 128, 128, 128))
	# Grid
	if zoom > 0.15:
		var gc := Color(1, 1, 1, 0.07)
		for x in cols() + 1:
			draw_line(Vector2(x * cs, 0), Vector2(x * cs, h), gc, 1.0 / zoom)
		for y in rows() + 1:
			draw_line(Vector2(0, y * cs), Vector2(w, y * cs), gc, 1.0 / zoom)
	draw_rect(Rect2(0, 0, w, h), Color(0.9, 0.8, 0.4, 0.6), false, 2.0 / zoom)
	_labels.clear()
	# Props (back to front), then markers on top
	var order := range(map.objects.size())
	order.sort_custom(func(a, b): return float(map.objects[a].y) < float(map.objects[b].y))
	for i in order:
		if map.objects[i].type == "prop":
			_draw_prop(map.objects[i], i == selected)
	for i in order:
		if not (map.objects[i].type in ["prop", "tile"]):
			_draw_marker(map.objects[i], i == selected)
	# Rectangle tool preview, brush outline
	if _rect_from.x >= 0:
		var a := Vector2(mini(_rect_from.x, _rect_to.x), mini(_rect_from.y, _rect_to.y)) * cs
		var b := Vector2(maxi(_rect_from.x, _rect_to.x) + 1, maxi(_rect_from.y, _rect_to.y) + 1) * cs
		draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(a, b - a), Color.WHITE, false, 2.0 / zoom)
	elif tool == "tile" and tile_sprite != "":
		var step := tile_step(tile_sprite, tile_scale)
		var p := (_hover / step).floor() * step
		var tex := texture(tile_sprite)
		if tex != null:
			draw_texture_rect(tex, Rect2(p, step), false, Color(1, 1, 1, 0.55))
		draw_rect(Rect2(p, step), Color.WHITE, false, 2.0 / zoom)
	elif tool in ["wall", "floor"]:
		var c := cell_at(_hover)
		var r := brush - 1
		draw_rect(Rect2(Vector2(c - Vector2i(r, r)) * cs, Vector2.ONE * cs * (2 * r + 1)), Color(1, 1, 1, 0.5), false, 2.0 / zoom)
	draw_set_transform(Vector2.ZERO)
	var font := ThemeDB.fallback_font
	for l in _labels:
		var sp := to_screen(l[0]) + Vector2(-100, -14)
		draw_string_outline(font, sp, l[1], HORIZONTAL_ALIGNMENT_CENTER, 200, 13, 4, Color.BLACK)
		draw_string(font, sp, l[1], HORIZONTAL_ALIGNMENT_CENTER, 200, 13, l[2])


func _draw_prop(o: Dictionary, sel: bool) -> void:
	var tex := texture(String(o.get("sprite", "")))
	var p := Vector2(float(o.x), float(o.y))
	if tex == null:
		draw_circle(p, 20, Color(1, 0, 1, 0.6))
		return
	var sc := float(o.get("scale", 0.5))
	var sz := tex.get_size() * sc
	var r := Rect2(p - Vector2(sz.x * 0.5, sz.y * 0.9), sz)
	draw_texture_rect(tex, r, false)
	if o.get("solid", false):
		draw_arc(p, tex.get_width() * sc * 0.3, 0, TAU, 24, Color(1, 0.3, 0.3, 0.8), 3.0 / zoom)
	if sel:
		draw_rect(r, Color.WHITE, false, 3.0 / zoom)


func _draw_marker(o: Dictionary, sel: bool) -> void:
	var p := Vector2(float(o.x), float(o.y))
	var col := Color.WHITE
	var label := ""
	match String(o.type):
		"start":
			col = Color(0.3, 1.0, 0.45)
			label = "START"
		"portal":
			col = Color(0.75, 0.45, 1.0)
			label = "Portal" + ((" → " + String(o.get("target", ""))) if String(o.get("target", "")) != "" else "")
			for k in 3:
				draw_arc(p, 60 - k * 14, 0, TAU, 32, col, 5.0)
		"pack":
			col = Color(1.0, 0.35, 0.3)
			label = "Pack %d-%d" % [int(o.get("min", 3)), int(o.get("max", 5))]
		"marker":
			col = Color(1.0, 0.85, 0.3)
			label = String(o.get("id", ""))
		"npc":
			col = Color(0.45, 0.75, 1.0)
			label = String(o.get("name", "NPC"))
		"trigger":
			col = Color(0.3, 0.95, 0.95)
			label = "⚑ " + String(o.get("id", ""))
			draw_arc(p, float(o.get("radius", 150)), 0, TAU, 48, Color(col, 0.7), 3.0 / zoom)
			draw_circle(p, float(o.get("radius", 150)), Color(col, 0.08))
	draw_circle(p, 26, Color(col, 0.85))
	draw_arc(p, 26, 0, TAU, 24, Color.BLACK, 3.0)
	if sel:
		draw_arc(p, 36, 0, TAU, 32, Color.WHITE, 4.0 / zoom)
	_labels.append([p + Vector2(0, -26), label, col])
