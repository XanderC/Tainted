class_name CharacterSelect
extends Control
## The game's start screen. The game is online only: first it signs in (a kept Autharr sign-in
## does it by itself; else email and password) and joins the Tainted World, which sends this
## account's characters (Net.account_ready). Then: your characters on the left, the picked one
## standing on the right with Play and Delete; "Create New Character" swaps the right side for the
## creation form (pick a class and looks, enter a name). Each character has its own save; the stash
## is shared. If the server can't be reached, or a game lost it for good, it says so: Try again.

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
var _net_status: Label
var _list_title: Label
var _stage: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	if Net.dedicated_requested():
		return  # a dedicated server passes through this scene on its way to its own (server.tscn)
	# Launched by the map editor's "Test in Game": play that map straight away (nothing is saved)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-map="):
			GameState.test_map = arg.get_slice("=", 1)
			GameState.give_starter_skills()
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
	Net.status_changed.connect(_on_net_status)
	Net.account_ready.connect(_on_account_ready)
	_build()
	if _ready_to_play():
		_pick_default()  # back from a game: still online, the account's characters
		_refresh()
		return
	if Net.mode != Net.Mode.RECONNECTING and Net.mode != Net.Mode.CONNECTING:
		var failed := Net.status != "" and Net.status != "Offline"  # a game lost the server, or it refused us
		Net.leave()
		GameState.forget_account()
		if failed:
			_refresh()  # says why: Try again
			return
	_refresh()
	_connect_world()


## Signed in, on the Tainted World, with this account's characters.
func _ready_to_play() -> bool:
	return Net.online() and Net.accounts and GameState.online_saves


## Signs in by itself if a sign-in is kept, then joins the Tainted World; else asks to sign in.
func _connect_world() -> void:
	await Net.resume_sign_in()
	if Net.signed_in_as == "":
		_refresh()  # the sign-in form
		return
	Net.join_world()
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
	_stage = stage
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


func _refresh() -> void:
	_delete_armed = false
	var ready := _ready_to_play()
	_list_title.get_parent().get_parent().get_parent().visible = ready  # the character list, once there are characters
	_stage.visible = ready
	if not ready:
		_build_connect()
		return
	_build_list()
	if _creating:
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
	_right.add_child(_signed_in_row())


func _play() -> void:
	if GameState.select_character(_selected):
		get_tree().change_scene_to_file(_first_scene())


# ---------- right: signing in and joining ----------

## Before there are characters: signing in, connecting, or why it couldn't (with Try again).
func _build_connect() -> void:
	UIKit.clear(_right)
	var center := CenterContainer.new()  # a column in the middle of the screen
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(minf(620.0, get_viewport_rect().size.x - 120.0), 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var head := UIKit.label(Net.world_name().to_upper(), 30, Color(0.70, 0.85, 1.0))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var about := UIKit.label("Tainted is played online: everyone meets in Ashfall Outpost, and your characters are kept on the server.", 15, UIKit.TEXT_DIM, true)
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(about)
	var busy := Net.mode in [Net.Mode.CONNECTING, Net.Mode.RECONNECTING] or (Net.online() and not GameState.online_saves)
	_net_status = UIKit.label("Getting your characters..." if Net.online() else (Net.status if Net.status != "Offline" else ""),
		16, Color(1.0, 0.75, 0.45), true)
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_net_status)
	if Net.signed_in_as == "":
		_build_sign_in(box)
	elif not busy:
		var again := UIKit.button("⟳  Try again", Color(0.12, 0.26, 0.40), Color(0.50, 0.80, 1.0), Vector2(0, 60), 21)
		again.pressed.connect(_connect_world)
		box.add_child(again)
		box.add_child(_signed_in_row())


## Who you're signed in as, with Sign out (another account).
func _signed_in_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UIKit.label("Signed in as %s" % Net.signed_in_as, 14, Color(0.55, 1.0, 0.6))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var out := UIKit.button("Sign out", Color(0.16, 0.14, 0.18), Color(0.50, 0.45, 0.50), Vector2(110, 38), 14)
	out.pressed.connect(func():
		Net.leave()
		Net.sign_out()
		GameState.forget_account()
		_refresh())
	row.add_child(out)
	return row


## Email and password (Autharr); signing in joins the Tainted World.
func _build_sign_in(parent: Control) -> void:
	var email := LineEdit.new()
	email.placeholder_text = "Email"
	email.custom_minimum_size = Vector2(0, 50)
	email.add_theme_font_size_override("font_size", 18)
	parent.add_child(email)
	var pw := LineEdit.new()
	pw.placeholder_text = "Password"
	pw.secret = true
	pw.custom_minimum_size = Vector2(0, 50)
	pw.add_theme_font_size_override("font_size", 18)
	parent.add_child(pw)
	var err := UIKit.label(Net.sign_in_error, 14, Color(1.0, 0.6, 0.5), true)
	var go := UIKit.button("Sign in", Color(0.12, 0.26, 0.40), Color(0.50, 0.80, 1.0), Vector2(0, 58), 20)
	go.pressed.connect(func():
		err.text = "Signing in..."
		await Net.sign_in(email.text, pw.text)
		if Net.signed_in_as != "":
			_connect_world()
		else:
			err.text = Net.sign_in_error)
	email.text_submitted.connect(func(_t): pw.grab_focus())
	pw.text_submitted.connect(func(_t): go.pressed.emit())
	parent.add_child(go)
	parent.add_child(err)
	parent.add_child(UIKit.label("Your Xandflix account (Autharr).", 13, UIKit.TEXT_DIM, true))
	var links := HBoxContainer.new()  # Autharr's own pages, in the browser
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", 28)
	parent.add_child(links)
	for l in [["Create an account", "/register"], ["Forgot your password?", "/forgot-password"]]:
		var b := LinkButton.new()
		b.text = l[0]
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0))
		var url := Net.account_page(l[1])
		b.pressed.connect(func(): OS.shell_open(url))
		links.add_child(b)


func _on_net_status() -> void:
	if not _ready_to_play():
		_refresh()  # connecting, refused, couldn't reach it...


## The server's characters for your account are here: show them (create one if there are none).
func _on_account_ready() -> void:
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
