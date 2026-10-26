extends Control
## Tainted Map Editor: a PC tool (separate Godot project) for building the game's maps.
## It reads the game's art (assets/tiles/<theme>) and reads/writes the game's map files
## (maps/<id>.json plus maps/index.json) directly in the game project folder, so a saved map is
## immediately in the game. "Test in Game" saves and launches the game straight into that map.
##
## Shortcuts: Ctrl+S save, Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo, Delete removes the selected
## object, F frames the whole map. Tools: 1 wall, 2 floor, 3 select.

const SETTINGS := "user://map_editor.cfg"
const THEMES := ["desert", "woodland"]  # the game's MapTheme.THEMES (assets/tiles/<theme>)
const DEFAULT_GODOT := "D:/godot_bin/Godot_v4.4.1-stable_win64.exe"
const TOOLS := [
	["select", "🖱 Select / Move", "Click an object to edit it, drag to move it"],
	["wall", "▦ Paint Wall", "Paint wall cells (drag)"],
	["floor", "▢ Paint Floor", "Paint floor cells (drag)"],
	["rect_wall", "▦ Wall Rectangle", "Drag a rectangle of walls"],
	["rect_floor", "▢ Floor Rectangle", "Drag a rectangle of floor"],
	["start", "🟢 Player Start", "Where the player appears (one per map)"],
	["portal", "🌀 Portal", "Rift: next random maze. Story: set a target map id or 'town'"],
	["pack", "👹 Monster Pack", "A group of monsters (rifts use some of them)"],
	["marker", "📍 Marker", "A named spot for scripts (e.g. the tutorial altar 'A')"],
	["npc", "🧍 NPC", "A character to talk to"],
	["trigger", "⚑ Story Trigger", "Fires a story event when the player walks into its radius"],
	["prop", "🌴 Prop", "Place a standing picture: trees, rocks, buildings (pick it in the list below)"],
	["tile", "🧱 Ground Tile", "Paint flat ground pieces: plateaus, cliffs, stairs, roads (pick land_ / road_ in the list, drag to paint)"],
]

var game_root := ""
var godot_exe := ""
var map_id := ""            # file name (no .json); "" until saved
var dirty := false

var _canvas: MapCanvas
var _name: LineEdit
var _kind: OptionButton
var _theme: OptionButton
var _textures_theme := ""   # the theme whose pictures are loaded
var _cols: SpinBox
var _rows: SpinBox
var _auto: CheckBox
var _snap: CheckBox
var _brush: SpinBox
var _tool_buttons := {}
var _props: ItemList
var _inspector: VBoxContainer
var _checks: RichTextLabel
var _status: Label
var _title: Label
var _open_dlg: FileDialog
var _save_dlg: FileDialog
var _dir_dlg: FileDialog
var _exe_dlg: FileDialog
var _undo: Array[String] = []
var _redo: Array[String] = []


func _ready() -> void:
	_load_settings()
	_build_ui()
	_load_textures()
	_new_map(40, 24)
	if not _valid_game_root(game_root):
		_status.text = "Game folder not found - press 'Game Folder…' and pick the Tainted project folder."


# ---------- settings & paths ----------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	game_root = String(cfg.get_value("paths", "game_root", ""))
	godot_exe = String(cfg.get_value("paths", "godot_exe", ""))
	if not _valid_game_root(game_root):
		# Run from the Godot editor: this project sits in <game>/tools/map_editor
		game_root = ProjectSettings.globalize_path("res://").path_join("../..").simplify_path()
		if not _valid_game_root(game_root):
			game_root = OS.get_executable_path().get_base_dir()
	if godot_exe == "" or not FileAccess.file_exists(godot_exe):
		godot_exe = DEFAULT_GODOT if FileAccess.file_exists(DEFAULT_GODOT) else OS.get_executable_path()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("paths", "game_root", game_root)
	cfg.set_value("paths", "godot_exe", godot_exe)
	cfg.save(SETTINGS)


func _valid_game_root(p: String) -> bool:
	return p != "" and FileAccess.file_exists(p.path_join("project.godot")) and DirAccess.dir_exists_absolute(p.path_join("assets/tiles"))


func _maps_dir() -> String:
	return game_root.path_join("maps")


## The map's theme's pictures and wall pieces, loaded straight from the game's folder (they aren't
## part of this project).
func _load_textures() -> void:
	_canvas.textures.clear()
	_canvas.wall_textures.clear()
	_props.clear()
	_textures_theme = String(_canvas.map.get("theme", THEMES[0]))
	_canvas.tiles_root = game_root.path_join("assets/tiles")
	var dir := game_root.path_join("assets/tiles").path_join(_textures_theme)
	for f in DirAccess.get_files_at(dir.path_join("walls")):
		if f.get_extension() == "png":
			var wimg := Image.load_from_file(dir.path_join("walls").path_join(f))
			if wimg != null:
				_canvas.wall_textures[f.get_basename()] = ImageTexture.create_from_image(wimg)
	var names: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "png":
			names.append(f.get_basename())
	names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for n in names:
		var img := Image.load_from_file(dir.path_join(n + ".png"))
		if img == null:
			continue
		var tex := ImageTexture.create_from_image(img)
		if n == "bg":
			_canvas.bg = tex
			continue
		_canvas.textures[n] = tex
		var thumb := img.duplicate() as Image
		var s := 48.0 / maxf(img.get_width(), img.get_height())
		thumb.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)))
		_props.add_item(n, ImageTexture.create_from_image(thumb))
	_canvas.queue_redraw()


# ---------- documents ----------

func _new_map(c: int, r: int) -> void:
	var grid: Array = []
	for y in r:
		var row := ""
		for x in c:
			row += "#" if x == 0 or y == 0 or x == c - 1 or y == r - 1 else "."
		grid.append(row)
	_set_map({"format": 1, "id": "", "name": "New Map", "kind": "story", "theme": "desert", "cell": 128,
		"auto_decorate": true, "grid": grid,
		"objects": [{"type": "start", "x": 2.5 * 128.0, "y": 2.5 * 128.0}]}, "")


func _set_map(m: Dictionary, id: String) -> void:
	_canvas.map = m
	if String(m.get("theme", THEMES[0])) != _textures_theme:
		_load_textures()
	_canvas.selected = -1
	map_id = id
	dirty = false
	_undo.clear()
	_redo.clear()
	_sync_fields()
	_refresh_inspector()
	_canvas.frame_map.call_deferred()
	_update_title()


func _sync_fields() -> void:
	var m := _canvas.map
	_name.text = String(m.get("name", ""))
	_kind.select(maxi(["rift", "story", "special"].find(String(m.get("kind", "story"))), 0))
	_theme.select(maxi(THEMES.find(String(m.get("theme", THEMES[0]))), 0))
	_cols.set_value_no_signal(_canvas.cols())
	_rows.set_value_no_signal(_canvas.rows())
	_auto.set_pressed_no_signal(bool(m.get("auto_decorate", true)))


func _open(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("grid"):
		_status.text = "Not a map file: " + path
		return
	if not data.has("objects"):
		data.objects = []
	_set_map(data, path.get_file().get_basename())
	_status.text = "Opened " + path


func _save(id: String) -> void:
	if not _valid_game_root(game_root):
		_status.text = "Pick the game folder first (Game Folder…)."
		return
	id = id.to_snake_case().replace(" ", "_")
	var m := _canvas.map
	m.id = id
	m.format = 1
	DirAccess.make_dir_recursive_absolute(_maps_dir())
	var f := FileAccess.open(_maps_dir().path_join(id + ".json"), FileAccess.WRITE)
	if f == null:
		_status.text = "Could not write " + id + ".json"
		return
	f.store_string(JSON.stringify(m, "\t"))
	f.close()
	_update_index(id, m)
	map_id = id
	dirty = false
	_update_title()
	_status.text = "Saved maps/%s.json" % id


## maps/index.json lists every map with its name and kind (the game reads it to find maps).
func _update_index(id: String, m: Dictionary) -> void:
	var path := _maps_dir().path_join("index.json")
	var idx = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(idx) != TYPE_DICTIONARY:
		idx = {"maps": {}}
	idx.maps[id] = {"name": m.get("name", id), "kind": m.get("kind", "story")}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(idx, "\t"))


func _save_pressed() -> void:
	if map_id == "":
		_save_as()
	else:
		_save(map_id)


func _save_as() -> void:
	_save_dlg.current_dir = _maps_dir()
	_save_dlg.current_file = String(_canvas.map.get("name", "new_map")).to_snake_case().replace(" ", "_") + ".json"
	_save_dlg.popup_centered_ratio(0.6)


## Save, then start the game straight into this map (as a rift, so packs spawn and you can fight).
func _test_in_game() -> void:
	_save_pressed()
	if map_id == "" or dirty:
		return
	var pid := OS.create_process(godot_exe, ["--path", game_root, "--", "--test-map=" + map_id])
	_status.text = ("Launched the game on '%s'." % map_id) if pid > 0 else "Could not start Godot: " + godot_exe


# ---------- undo ----------

func _snapshot() -> void:
	_undo.append(JSON.stringify(_canvas.map))
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()


func _undo_step(back: bool) -> void:
	var from: Array[String] = _undo if back else _redo
	var to: Array[String] = _redo if back else _undo
	if from.is_empty():
		return
	to.append(JSON.stringify(_canvas.map))
	_canvas.map = JSON.parse_string(from.pop_back())
	_canvas.selected = -1
	_sync_fields()
	_refresh_inspector()
	_mark_dirty()


func _mark_dirty() -> void:
	dirty = true
	_update_title()
	_run_checks()
	_canvas.queue_redraw()


func _update_title() -> void:
	_title.text = "%s%s" % [map_id if map_id != "" else "(unsaved)", " •" if dirty else ""]
	get_window().title = "Tainted Map Editor - " + _title.text


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed:
		match k.keycode:
			KEY_S: _save_pressed()
			KEY_Z: _undo_step(not k.shift_pressed)
			KEY_Y: _undo_step(false)
		return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		return
	match k.keycode:
		KEY_F: _canvas.frame_map()
		KEY_1: _pick_tool("wall")
		KEY_2: _pick_tool("floor")
		KEY_3: _pick_tool("select")


# ---------- map settings ----------

## Change the map size, keeping the top-left; new cells are walls, objects outside are removed.
func _resize() -> void:
	var c := int(_cols.value)
	var r := int(_rows.value)
	if c == _canvas.cols() and r == _canvas.rows():
		return
	_snapshot()
	var old: Array = _canvas.map.grid
	var grid: Array = []
	for y in r:
		var row := ""
		for x in c:
			row += String(old[y])[x] if y < old.size() and x < String(old[y]).length() else "#"
		grid.append(row)
	_canvas.map.grid = grid
	var cs := _canvas.cell_size()
	_canvas.map.objects = _canvas.map.objects.filter(func(o): return float(o.x) < c * cs and float(o.y) < r * cs)
	_canvas.selected = -1
	_refresh_inspector()
	_mark_dirty()
	_canvas.frame_map()


func _run_checks() -> void:
	var m := _canvas.map
	var lines: Array[String] = []
	var starts := MapCanvasHelpers.count(m, "start")
	if starts == 0:
		lines.append("[color=#f87171]✗ No player start[/color]")
	for o in m.objects:
		if o.type in ["start", "portal", "pack", "npc"] and _canvas.is_wall(_canvas.cell_at(Vector2(float(o.x), float(o.y)))):
			lines.append("[color=#fbbf24]⚠ %s is inside a wall[/color]" % String(o.type).capitalize())
	if String(m.get("kind", "")) == "rift":
		if MapCanvasHelpers.count(m, "portal") == 0:
			lines.append("[color=#fbbf24]⚠ Rift maps need a portal[/color]")
		if MapCanvasHelpers.count(m, "pack") < 6:
			lines.append("[color=#fbbf24]⚠ Rifts use up to 6 packs (%d placed)[/color]" % MapCanvasHelpers.count(m, "pack"))
	if lines.is_empty():
		lines.append("[color=#4ade80]✓ Looks good[/color]")
	_checks.text = "\n".join(PackedStringArray(lines))


# ---------- inspector ----------

func _refresh_inspector() -> void:
	for c in _inspector.get_children():
		c.queue_free()
	var i := _canvas.selected
	if i < 0 or i >= _canvas.map.objects.size():
		_inspector.add_child(_label("Nothing selected.\nUse Select (3) and click an object.", 13, Color(0.6, 0.6, 0.6), true))
		_run_checks()
		return
	var o: Dictionary = _canvas.map.objects[i]
	_inspector.add_child(_label(String(o.type).to_upper(), 16, Color(1.0, 0.85, 0.4)))
	_num_field(o, "x", -100000, 100000)
	_num_field(o, "y", -100000, 100000)
	match String(o.type):
		"portal": _text_field(o, "target", "Target map id ('' = next rift maze, 'town')")
		"pack":
			_num_field(o, "min", 1, 30)
			_num_field(o, "max", 1, 30)
		"marker": _text_field(o, "id", "Marker id")
		"prop":
			_text_field(o, "sprite", "Picture")
			_num_field(o, "scale", 0.05, 5.0, 0.05)
			_bool_field(o, "solid", "Solid (blocks movement)")
		"tile":
			_text_field(o, "sprite", "Picture")
			_num_field(o, "scale", 0.05, 5.0, 0.05)
		"npc":
			_text_field(o, "id", "NPC id")
			_text_field(o, "name", "Name")
			_text_field(o, "dialogue", "Dialogue", true)
		"trigger":
			_text_field(o, "id", "Trigger id")
			_num_field(o, "radius", 20, 2000)
			_text_field(o, "text", "Story text / event", true)
	var del := Button.new()
	del.text = "🗑 Delete (Del)"
	del.pressed.connect(_canvas.delete_selected)
	_inspector.add_child(del)
	_run_checks()


func _label(t: String, sz := 13, col := Color(0.85, 0.85, 0.85), wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l


func _num_field(o: Dictionary, key: String, lo: float, hi: float, step := 1.0) -> void:
	_inspector.add_child(_label(key.capitalize(), 12, Color(0.7, 0.7, 0.7)))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(o.get(key, 0))
	s.value_changed.connect(func(v: float):
		_snapshot()
		o[key] = v if step < 1.0 else int(v)
		_mark_dirty()
	)
	_inspector.add_child(s)


func _text_field(o: Dictionary, key: String, title: String, multiline := false) -> void:
	_inspector.add_child(_label(title, 12, Color(0.7, 0.7, 0.7)))
	if multiline:
		var t := TextEdit.new()
		t.custom_minimum_size = Vector2(0, 110)
		t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		t.text = String(o.get(key, ""))
		t.focus_exited.connect(func():
			if t.text != String(o.get(key, "")):
				_snapshot()
				o[key] = t.text
				_mark_dirty()
		)
		_inspector.add_child(t)
	else:
		var e := LineEdit.new()
		e.text = String(o.get(key, ""))
		var commit := func(_x = null):
			if e.text != String(o.get(key, "")):
				_snapshot()
				o[key] = e.text
				_mark_dirty()
		e.text_submitted.connect(commit)
		e.focus_exited.connect(commit)
		_inspector.add_child(e)


func _bool_field(o: Dictionary, key: String, title: String) -> void:
	var c := CheckBox.new()
	c.text = title
	c.button_pressed = bool(o.get(key, false))
	c.toggled.connect(func(on: bool):
		_snapshot()
		o[key] = on
		_mark_dirty()
	)
	_inspector.add_child(c)


# ---------- UI ----------

func _pick_tool(id: String) -> void:
	_canvas.tool = id
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == id)
	_props.visible = true
	_status.text = TOOLS.filter(func(x): return x[0] == id)[0][2]


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	add_child(root)

	# Top bar: files and map settings
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	for b in [["📄 New", func(): _new_map(int(_cols.value), int(_rows.value))],
			["📂 Open", func():
				_open_dlg.current_dir = _maps_dir()
				_open_dlg.popup_centered_ratio(0.6)],
			["💾 Save", _save_pressed], ["Save As…", _save_as]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		top.add_child(btn)
	_title = _label("", 15, Color(1.0, 0.85, 0.4))
	_title.custom_minimum_size = Vector2(160, 0)
	top.add_child(_title)
	top.add_child(_label("Name"))
	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(170, 0)
	_name.text_changed.connect(func(t: String):
		_canvas.map.name = t
		_mark_dirty()
	)
	top.add_child(_name)
	top.add_child(_label("Kind"))
	_kind = OptionButton.new()
	for k in ["rift", "story", "special"]:
		_kind.add_item(k)
	_kind.item_selected.connect(func(i: int):
		_snapshot()
		_canvas.map.kind = ["rift", "story", "special"][i]
		_mark_dirty()
	)
	top.add_child(_kind)
	top.add_child(_label("Theme"))
	_theme = OptionButton.new()
	for t in THEMES:
		_theme.add_item(t)
	_theme.tooltip_text = "The map's look: its floor, walls and pictures (a prop can borrow another theme's as <theme>/<name>)"
	_theme.item_selected.connect(func(i: int):
		_snapshot()
		_canvas.map.theme = THEMES[i]
		_load_textures()
		_mark_dirty()
	)
	top.add_child(_theme)
	top.add_child(_label("Size"))
	_cols = SpinBox.new()
	_cols.min_value = 5
	_cols.max_value = 300
	top.add_child(_cols)
	top.add_child(_label("×"))
	_rows = SpinBox.new()
	_rows.min_value = 5
	_rows.max_value = 300
	top.add_child(_rows)
	var rs := Button.new()
	rs.text = "Resize"
	rs.pressed.connect(_resize)
	top.add_child(rs)
	_auto = CheckBox.new()
	_auto.text = "Auto decor"
	_auto.tooltip_text = "The game adds random trees on wall edges and stones on the floor"
	_auto.toggled.connect(func(on: bool):
		_snapshot()
		_canvas.map.auto_decorate = on
		_mark_dirty()
	)
	top.add_child(_auto)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var test := Button.new()
	test.text = "▶ Test in Game"
	test.pressed.connect(_test_in_game)
	top.add_child(test)
	var gf := Button.new()
	gf.text = "📁 Game"
	gf.pressed.connect(func(): _dir_dlg.popup_centered_ratio(0.6))
	top.add_child(gf)
	var ge := Button.new()
	ge.text = "⚙ Godot"
	ge.pressed.connect(func(): _exe_dlg.popup_centered_ratio(0.6))
	top.add_child(ge)

	# Middle: tools | canvas | inspector
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	root.add_child(mid)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(210, 0)
	mid.add_child(left)
	left.add_child(_label("TOOLS", 13, Color(1.0, 0.85, 0.4)))
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.tooltip_text = t[2]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id: String = t[0]
		b.pressed.connect(_pick_tool.bind(id))
		left.add_child(b)
		_tool_buttons[id] = b
	var brow := HBoxContainer.new()
	left.add_child(brow)
	brow.add_child(_label("Brush"))
	_brush = SpinBox.new()
	_brush.min_value = 1
	_brush.max_value = 5
	_brush.value_changed.connect(func(v: float): _canvas.brush = int(v))
	brow.add_child(_brush)
	_snap = CheckBox.new()
	_snap.text = "Snap to cells"
	_snap.button_pressed = true
	_snap.toggled.connect(func(on: bool): _canvas.snap = on)
	left.add_child(_snap)
	var trow := HBoxContainer.new()
	left.add_child(trow)
	trow.add_child(_label("Tile scale"))
	var ts := SpinBox.new()
	ts.min_value = 0.125
	ts.max_value = 2.0
	ts.step = 0.125
	ts.value = 0.5
	ts.tooltip_text = "0.5 = the game's art scale: land tiles fill one cell, road pieces a quarter"
	ts.value_changed.connect(func(v: float): _canvas.tile_scale = v)
	trow.add_child(ts)
	left.add_child(_label("PROPS & GROUND TILES", 13, Color(1.0, 0.85, 0.4)))
	_props = ItemList.new()
	_props.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_props.icon_mode = ItemList.ICON_MODE_LEFT
	_props.fixed_icon_size = Vector2i(40, 40)
	_props.item_selected.connect(func(i: int):
		var n := _props.get_item_text(i)
		if MapCanvasHelpers.is_ground_tile(n):
			_canvas.tile_sprite = n
			_pick_tool("tile")
		else:
			_canvas.prop_sprite = n
			_pick_tool("prop")
	)
	left.add_child(_props)

	_canvas = MapCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.about_to_edit.connect(_snapshot)
	_canvas.edited.connect(_mark_dirty)
	_canvas.selection_changed.connect(func(_i): _refresh_inspector())
	_canvas.hovered.connect(func(c: Vector2i, w: Vector2):
		_status.text = "Cell %d, %d   •   World %d, %d   •   %s" % [c.x, c.y, int(w.x), int(w.y), _canvas.tool])
	mid.add_child(_canvas)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	mid.add_child(right)
	right.add_child(_label("INSPECTOR", 13, Color(1.0, 0.85, 0.4)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)
	right.add_child(_label("CHECKS", 13, Color(1.0, 0.85, 0.4)))
	_checks = RichTextLabel.new()
	_checks.bbcode_enabled = true
	_checks.fit_content = true
	right.add_child(_checks)

	_status = _label("", 13, Color(0.7, 0.7, 0.75))
	root.add_child(_status)

	# Dialogs
	_open_dlg = _dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Map files"])
	_open_dlg.file_selected.connect(_open)
	_save_dlg = _dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.json ; Map files"])
	_save_dlg.file_selected.connect(func(p: String): _save(p.get_file().get_basename()))
	_dir_dlg = _dialog(FileDialog.FILE_MODE_OPEN_DIR, [])
	_dir_dlg.dir_selected.connect(func(p: String):
		if _valid_game_root(p):
			game_root = p
			_save_settings()
			_load_textures()
			_status.text = "Game folder: " + p
		else:
			_status.text = "That folder isn't the Tainted project (no project.godot / assets/tiles)."
	)
	_exe_dlg = _dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.exe ; Godot"])
	_exe_dlg.file_selected.connect(func(p: String):
		godot_exe = p
		_save_settings()
		_status.text = "Godot: " + p
	)
	_pick_tool("wall")


func _dialog(mode: int, filters: Array) -> FileDialog:
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = mode
	d.filters = PackedStringArray(filters)
	d.use_native_dialog = true
	add_child(d)
	return d
