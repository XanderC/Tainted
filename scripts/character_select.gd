class_name CharacterSelect
extends Control
## The game's start screen: your characters on the left, the picked one standing on the right
## with Play and Delete. "Create New Character" swaps the right side for the creation form
## (pick a class, enter a name). Each character has its own save; the stash is shared.
## "Play Online" swaps it for the online screen: games on your Wi-Fi (Net.scan), join by address,
## or host one on this device. A server that keeps characters (the Tainted World, Net.accounts) lists
## its own here instead, your online characters, until you go offline; coming back here from a game
## on it keeps you online. From any other game, coming back here takes you offline.

const SCENE := "res://scenes/character_select.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"

var _selected := ""      # character id shown on the right
var _creating := false
var _new_class := "warrior"
var _look := Appearance.default_look()  # the new character's looks, picked on the creation form
var _new_name := ""  # kept while the form is rebuilt
var _look_box: GridContainer  # the looks options, rebuilt when one changes

var _list: VBoxContainer
var _right: VBoxContainer
var _rig: RigSprite
var _name_edit: LineEdit
var _name_error: Label
var _delete_armed := false
var _online := false  # the online screen is shown on the right
var _servers: Array = []  # games found on the Wi-Fi (Net.servers_found)
var _scan_t := 0.0
var _net_status: Label
var _server_box: VBoxContainer
var _addr_edit: LineEdit
var _list_title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	# Launched by the map editor's "Test in Game": play that map straight away (nothing is saved)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-map="):
			GameState.test_map = arg.get_slice("=", 1)
			GameState.give_starter_skills()
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
	if (Net.online() and not Net.accounts) or Net.mode == Net.Mode.CONNECTING:
		Net.leave()  # back from a hosted game: offline, free to pick any character
	Net.status_changed.connect(_on_net_status)
	Net.account_ready.connect(_on_account_ready)
	Net.servers_found.connect(_on_servers_found)
	_build()
	_selected = GameState.last_character if not GameState.character_info(GameState.last_character).is_empty() else ""
	if _selected == "" and not GameState.characters.is_empty():
		_selected = GameState.characters[0].id
	_creating = GameState.characters.is_empty()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.035, 0.055)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)

	var title := UIKit.label("TAINTED", 44, UIKit.GOLD)
	title.add_theme_font_override("font", UIKit.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.05))
	title.add_theme_constant_override("outline_size", 8)
	outer.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)

	# LEFT: the character list
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	left.add_theme_stylebox_override("panel", UIKit.window_box(20, Color.WHITE, true))
	cols.add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 8)
	left.add_child(lbox)
	_list_title = UIKit.window_header(lbox, "CHARACTERS", UIKit.GOLD, Callable(), 20).get_node("Title")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# RIGHT: the stage (the character standing there) and its info / the creation form
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", UIKit.window_box(28, Color(1.0, 0.8, 0.8)))
	cols.add_child(right)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 16)
	right.add_child(rrow)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(300, 0)
	stage.clip_contents = true
	rrow.add_child(stage)
	stage.draw.connect(func():
		var c := Vector2(stage.size.x * 0.5, stage.size.y * 0.80)
		for i in 5:  # a soft glow under the character's feet
			stage.draw_set_transform(c, 0.0, Vector2(1.0, 0.32))
			stage.draw_circle(Vector2.ZERO, 120.0 - i * 20.0, Color(0.85, 0.35, 0.15, 0.05 + i * 0.03))
		stage.draw_set_transform(Vector2.ZERO)
	)
	_rig = RigSprite.new()
	_rig.base_scale = 0.55
	_rig.weapon_from_gear = true
	stage.add_child(_rig)
	_rig.play_loop("Idle")
	stage.resized.connect(func():
		_rig.position = Vector2(stage.size.x * 0.5, stage.size.y * 0.80)
		stage.queue_redraw()
	)

	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 12)
	rrow.add_child(_right)


func _exit_tree() -> void:
	Net.stop_scan()


func _process(delta: float) -> void:
	if _online:
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 3.0  # ask again now and then: servers come and go
			Net.scan()


func _refresh() -> void:
	_delete_armed = false
	var on_server := Net.online() and Net.accounts
	_list_title.text = "ONLINE CHARACTERS" if on_server else "CHARACTERS"
	_list_title.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0) if on_server else UIKit.GOLD)
	_build_list()
	if _online and not _creating:
		_build_online()
		_dress(GameState.peek_equipment(_selected))
	elif _creating:
		_build_create()
		_dress({})
	else:
		_build_info()
		_dress(GameState.peek_equipment(_selected))


func _dress(gear: Dictionary) -> void:
	Appearance.apply(_rig, _look if _creating else GameState.character_info(_selected).get("appearance", {}))
	Player.dress_rig(_rig, gear)


# ---------- left: the list ----------

func _build_list() -> void:
	UIKit.clear(_list)
	for c in GameState.characters:
		var on: bool = not _creating and c.id == _selected
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 78)
		# The picked character is lit stone; the rest are sunk into the panel
		var face := UIKit.tab_box(on)
		UIKit.tab_font(b)
		b.add_theme_stylebox_override("normal", face)
		b.add_theme_stylebox_override("hover", face)
		b.add_theme_stylebox_override("pressed", face)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var id: String = c.id
		b.pressed.connect(func():
			_selected = id
			_creating = false
			_online = false
			_refresh()
		)
		_list.add_child(b)
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 14 if side in ["left", "right"] else 8)
		b.add_child(m)
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		m.add_child(v)
		var cls := ClassLibrary.get_class_def(String(c["class"]))
		var n := UIKit.label(String(c.name), 22, Color(1.0, 0.92, 0.65) if on else Color(0.92, 0.88, 0.80))
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(n)
		var sub := UIKit.label("Level %d %s" % [int(c.level), cls.display_name], 15, UIKit.TEXT_DIM)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub)

	if GameState.characters.size() < GameState.MAX_CHARACTERS:
		var nb := UIKit.button("＋  Create New Character", Color(0.10, 0.20, 0.12) if not _creating else Color(0.14, 0.30, 0.17),
			Color(0.35, 0.80, 0.45), Vector2(0, 64), 18)
		nb.pressed.connect(func():
			_creating = true
			_refresh()
		)
		_list.add_child(nb)


# ---------- right: the picked character ----------

func _build_info() -> void:
	UIKit.clear(_right)
	var c := GameState.character_info(_selected)
	if c.is_empty():
		return
	var cls := ClassLibrary.get_class_def(String(c["class"]))
	_right.add_child(_spacer())
	_right.add_child(UIKit.label(String(c.name), 34, Color(1.0, 0.90, 0.60)))
	_right.add_child(UIKit.label("Level %d %s" % [int(c.level), cls.display_name], 20, cls.color.lightened(0.35)))
	_right.add_child(UIKit.label(cls.description, 15, UIKit.TEXT_DIM, true))
	_right.add_child(_spacer())

	var play := UIKit.button("▶  PLAY", Color(0.14, 0.38, 0.18), Color(0.40, 1.0, 0.55), Vector2(0, 72), 26)
	play.pressed.connect(_play)
	_right.add_child(play)
	if Net.online() and Net.accounts:
		# Playing on a server that keeps characters: these are its, and you can go back to the device's
		var off := UIKit.button("🌐  Go offline  (%s)" % Net.server_name, Color(0.10, 0.20, 0.34), Color(0.45, 0.70, 1.0), Vector2(0, 50), 17)
		off.pressed.connect(_go_offline)
		_right.add_child(off)
	else:
		var online := UIKit.button("🌐  Play Online", Color(0.10, 0.20, 0.34), Color(0.45, 0.70, 1.0), Vector2(0, 56), 20)
		online.pressed.connect(func():
			_online = true
			_scan_t = 0.0
			_refresh()
		)
		_right.add_child(online)
	var del := UIKit.button("🗑  Delete Character", Color(0.20, 0.08, 0.08), Color(0.60, 0.25, 0.25), Vector2(0, 50), 16)
	del.pressed.connect(func():
		if not _delete_armed:
			_delete_armed = true
			del.text = "Tap again to delete %s forever" % String(c.name)
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(del) and _delete_armed:
					_delete_armed = false
					del.text = "🗑  Delete Character"
			)
			return
		GameState.delete_character(_selected)
		_selected = GameState.characters[0].id if not GameState.characters.is_empty() else ""
		_creating = _selected == ""
		_refresh()
	)
	_right.add_child(del)


func _play() -> void:
	if GameState.select_character(_selected):
		get_tree().change_scene_to_file(_first_scene())


# ---------- right: playing online ----------

func _build_online() -> void:
	UIKit.clear(_right)
	var c := GameState.character_info(_selected)
	_right.add_child(UIKit.label("PLAY ONLINE", 30, Color(0.70, 0.85, 1.0)))
	_right.add_child(UIKit.label("as %s. Everyone online meets in Ashfall Outpost." % String(c.get("name", "")), 15, UIKit.TEXT_DIM, true))
	_net_status = UIKit.label(Net.status if Net.mode != Net.Mode.OFFLINE or Net.status != "Offline" else "", 15, Color(1.0, 0.75, 0.45), true)
	_right.add_child(_net_status)

	var world := UIKit.section(_right, Net.world_name().to_upper())
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 10)
	world.add_child(wrow)
	var wl := UIKit.label("The shared world: everyone online, whatever their Wi-Fi.", 15, Color(0.85, 0.88, 0.95), true)
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(wl)
	var wb := UIKit.button("🌍  Join", Color(0.12, 0.26, 0.40), Color(0.50, 0.80, 1.0), Vector2(130, 46), 17)
	wb.pressed.connect(func():
		if not _selected.is_empty():
			GameState.select_character(_selected)  # used if the server doesn't keep characters
		Net.join_world()
	)
	wrow.add_child(wb)

	var sec := UIKit.section(_right, "GAMES ON YOUR WI-FI")
	_server_box = VBoxContainer.new()
	_server_box.add_theme_constant_override("separation", 6)
	sec.add_child(_server_box)
	_fill_servers()

	var addr_sec := UIKit.section(_right, "JOIN BY ADDRESS")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	addr_sec.add_child(row)
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "e.g. 192.168.86.20 or wss://..."
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr_edit.custom_minimum_size = Vector2(0, 46)
	_addr_edit.add_theme_font_size_override("font_size", 18)
	row.add_child(_addr_edit)
	var join := UIKit.button("Join", Color(0.10, 0.20, 0.34), Color(0.45, 0.70, 1.0), Vector2(120, 46), 17)
	join.pressed.connect(func():
		if _addr_edit.text.strip_edges() != "":
			_connect_to(_addr_edit.text)
	)
	row.add_child(join)

	var host := UIKit.button("🏠  Host a game on this device", Color(0.14, 0.30, 0.18), Color(0.40, 0.95, 0.55), Vector2(0, 52), 18)
	host.pressed.connect(func():
		if GameState.select_character(_selected) and Net.host():
			get_tree().change_scene_to_file(_first_scene())
	)
	_right.add_child(host)
	var back := UIKit.button("←  Back", Color(0.16, 0.14, 0.18), Color(0.50, 0.45, 0.50), Vector2(0, 44), 15)
	back.pressed.connect(func():
		Net.leave()
		_online = false
		_refresh()
	)
	_right.add_child(back)


func _on_servers_found(list: Array) -> void:
	_servers = list
	if _online:
		_fill_servers()


func _fill_servers() -> void:
	if _server_box == null or not is_instance_valid(_server_box):
		return
	UIKit.clear(_server_box)
	if _servers.is_empty():
		_server_box.add_child(UIKit.label("Looking... (a game hosted on a phone or PC on this Wi-Fi shows up here)", 14, UIKit.TEXT_DIM, true))
		return
	for s in _servers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_server_box.add_child(row)
		var l := UIKit.label("%s   (%d / %d online)" % [s.name, int(s.players), int(s.max)], 17, Color(0.92, 0.90, 0.84))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var addr: String = s.address
		var b := UIKit.button("Join", Color(0.10, 0.20, 0.34), Color(0.45, 0.70, 1.0), Vector2(110, 42), 16)
		b.pressed.connect(func(): _connect_to(addr))
		row.add_child(b)


## Loads the character (a server that keeps characters uses its own instead), then joins;
## Net.status_changed says how it went.
func _connect_to(address: String) -> void:
	if not _selected.is_empty():
		GameState.select_character(_selected)
	Net.join(address)


func _on_net_status() -> void:
	if is_instance_valid(_net_status):
		_net_status.text = Net.status
	if _online and Net.mode == Net.Mode.CLIENT and not Net.accounts:
		get_tree().change_scene_to_file(_first_scene())  # in: off to town
	elif Net.mode == Net.Mode.OFFLINE and not _online:
		_pick_default()  # the device's characters again
		_refresh()


## The server's characters for your account are here: show them (create one if there are none).
func _on_account_ready() -> void:
	_online = false
	_pick_default()
	_refresh()


func _go_offline() -> void:
	Net.leave()
	_pick_default()
	_refresh()


func _pick_default() -> void:
	_selected = GameState.last_character if not GameState.character_info(GameState.last_character).is_empty() else ""
	if _selected == "" and not GameState.characters.is_empty():
		_selected = GameState.characters[0].id
	_creating = GameState.characters.is_empty()


## New characters (and ones who quit midway) go to the tutorial map first.
static func _first_scene() -> String:
	return TOWN_SCENE if GameState.tutorial_stage >= GameState.TUTORIAL_DONE else TutorialMap.SCENE


# ---------- right: creating a character ----------

func _build_create() -> void:
	UIKit.clear(_right)
	_right.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_right.add_child(top)
	var title := UIKit.label("CREATE A CHARACTER", 24, Color(1.0, 0.90, 0.60))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	for id in ClassLibrary.CLASS_IDS:
		var cls := ClassLibrary.get_class_def(id)
		var on: bool = id == _new_class
		var b := UIKit.button(cls.display_name, Color(0.24, 0.16, 0.09) if on else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.80, 0.40) if on else Color(0.32, 0.26, 0.20), Vector2(130, 44), 17)
		b.tooltip_text = cls.description
		b.pressed.connect(func():
			_new_class = id
			_refresh()
		)
		top.add_child(b)
	var cls := ClassLibrary.get_class_def(_new_class)
	_right.add_child(UIKit.label(cls.description, 14, UIKit.TEXT_DIM, true))

	# Looks: gender, face, hair and its colour, facial hair and its colour, skin, outfit
	# Two columns on a wide screen; on a narrower one a single column that scrolls
	var wide := get_viewport_rect().size.x >= 1500.0
	var looks := PanelContainer.new()
	looks.add_theme_stylebox_override("panel", UIKit.inset_box(12))
	if wide:
		_right.add_child(looks)
	else:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.size_flags_stretch_ratio = 4.0
		_right.add_child(sc)
		looks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(looks)
	_look_box = GridContainer.new()
	_look_box.columns = 2 if wide else 1
	_look_box.add_theme_constant_override("h_separation", 24)
	_look_box.add_theme_constant_override("v_separation", 8)
	looks.add_child(_look_box)
	_build_look_options()

	_name_edit = LineEdit.new()
	_name_edit.max_length = GameState.NAME_MAX_LEN
	_name_edit.placeholder_text = "Enter a name"
	_name_edit.custom_minimum_size = Vector2(0, 50)
	_name_edit.text = _new_name
	_name_edit.add_theme_font_size_override("font_size", 22)
	for st in [["normal", Color(0.55, 0.45, 0.30)], ["focus", Color(0.95, 0.80, 0.40)]]:
		var sb := UIKit.inset_box(14, Color.WHITE if st[0] == "normal" else Color(1.0, 0.85, 0.55))
		_name_edit.add_theme_stylebox_override(st[0], sb)
	_name_edit.text_submitted.connect(func(_t): _create())
	_name_edit.text_changed.connect(func(t):
		_new_name = t
		_name_error.text = ""
	)
	_right.add_child(_name_edit)
	_name_error = UIKit.label("", 14, Color(1.0, 0.45, 0.45))
	_right.add_child(_name_error)
	if wide:
		_right.add_child(_spacer())  # (narrow: the scrolling options take the spare height)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_right.add_child(row)
	if not GameState.characters.is_empty():
		var cancel := UIKit.button("Cancel", Color(0.15, 0.12, 0.14), Color(0.45, 0.38, 0.32), Vector2(150, 64), 18)
		cancel.pressed.connect(func():
			_creating = false
			_refresh()
		)
		row.add_child(cancel)
	var create := UIKit.button("✦  Create & Play", Color(0.14, 0.38, 0.18), Color(0.40, 1.0, 0.55), Vector2(0, 64), 22)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(_create)
	row.add_child(create)


func _create() -> void:
	var why := GameState.name_block_reason(_name_edit.text)
	if why != "":
		_name_error.text = why
		return
	DisplayServer.virtual_keyboard_hide()
	if GameState.create_character(_name_edit.text, _new_class, _look) != "":
		get_tree().change_scene_to_file(_first_scene())


## The looks options on the creation form, in two columns. Changing one redresses the character.
func _build_look_options() -> void:
	UIKit.clear(_look_box)
	var g: String = _look["gender"]
	_look_row("Gender", _choice(["male", "female"], g, func(v):
		var old: Dictionary = _look.duplicate()
		_look = Appearance.default_look(v)
		for k in ["hair_color", "skin", "beard_color"]:
			_look[k] = old[k]
		_look_changed()
	, ["Male", "Female"]))
	_look_row("Face", _stepper("faces", "face", Appearance.options("faces", g)))
	_look_row("Hair", _stepper("hair", "hair", Appearance.options("hair")))
	_look_row("Hair colour", _swatches(Appearance.HAIR_COLORS, "hair_color"))
	if g == "male":
		_look_row("Facial hair", _stepper("beards", "beard", Appearance.options("beards")))
		_look_row("Beard colour", _swatches(Appearance.HAIR_COLORS, "beard_color"))
	_look_row("Skin", _swatches(Appearance.SKIN_TONES, "skin"))
	_look_row("Outfit", _stepper("outfits", "outfit", Appearance.options("outfits")))
	var rnd := UIKit.button("🎲  Random", Color(0.15, 0.12, 0.10), Color(0.75, 0.58, 0.30), Vector2(0, 40), 16)
	rnd.pressed.connect(func():
		_look = Appearance.random_look()
		_look_changed()
	)
	_look_box.add_child(rnd)


func _look_changed() -> void:
	_build_look_options()
	_dress({})


func _look_row(title: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UIKit.label(title, 15, UIKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(108, 0)
	row.add_child(l)
	row.add_child(control)
	_look_box.add_child(row)


## ◀ name ▶ through the options of one look key.
func _stepper(kind: String, key: String, opts: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var i := maxi(opts.find(_look[key]), 0)
	for step in [-1, 1]:
		var b := UIKit.button("◀" if step < 0 else "▶", Color(0.12, 0.10, 0.12), Color(0.55, 0.45, 0.30), Vector2(40, 38), 15)
		b.pressed.connect(func():
			_look[key] = opts[posmod(i + step, opts.size())]
			_look_changed()
		)
		box.add_child(b)
		if step < 0:
			var name_lbl := UIKit.label(Appearance.label(kind, String(_look[key])), 16, Color(0.95, 0.90, 0.78))
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.custom_minimum_size = Vector2(110, 0)
			box.add_child(name_lbl)
	return box


## Buttons for a few fixed choices (gender).
func _choice(values: Array, current: String, on_pick: Callable, labels: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	for k in values.size():
		var on: bool = values[k] == current
		var b := UIKit.button(labels[k], Color(0.24, 0.16, 0.09) if on else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.80, 0.40) if on else Color(0.32, 0.26, 0.20), Vector2(96, 38), 16)
		var v: String = values[k]
		b.pressed.connect(func(): on_pick.call(v))
		box.add_child(b)
	return box


## A row of colour swatches for one look key; the picked one has a gold rim.
func _swatches(palette: Dictionary, key: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	for id in palette:
		var on: bool = _look[key] == id
		var b := Button.new()
		b.custom_minimum_size = Vector2(26, 30)
		b.tooltip_text = String(id).capitalize()
		var sb := UIKit.box(palette[id], Color(1.0, 0.85, 0.40) if on else Color(0.08, 0.06, 0.06), 3 if on else 2, 5)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var v: String = id
		b.pressed.connect(func():
			_look[key] = v
			_look_changed()
		)
		box.add_child(b)
	return box


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s
