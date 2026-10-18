class_name CharacterSelect
extends Control
## The game's start screen: your characters on the left, the picked one standing on the right
## with Play and Delete. "Create New Character" swaps the right side for the creation form
## (pick a class, enter a name). Each character has its own save; the stash is shared.

const SCENE := "res://scenes/character_select.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"

var _selected := ""      # character id shown on the right
var _creating := false
var _new_class := "warrior"

var _list: VBoxContainer
var _right: VBoxContainer
var _rig: RigSprite
var _name_edit: LineEdit
var _name_error: Label
var _delete_armed := false


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

	var title := UIKit.label("TAINTED", 40, UIKit.GOLD)
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
	var lsb := UIKit.window_box(10)
	lsb.set_content_margin_all(10)
	left.add_theme_stylebox_override("panel", lsb)
	cols.add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 8)
	left.add_child(lbox)
	lbox.add_child(UIKit.label("CHARACTERS", 18, UIKit.TEXT_DIM))
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
	var rsb := UIKit.window_box(10, Color(1.0, 0.8, 0.8))
	rsb.set_content_margin_all(14)
	right.add_theme_stylebox_override("panel", rsb)
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


func _refresh() -> void:
	_delete_armed = false
	_build_list()
	if _creating:
		_build_create()
		_dress({})
	else:
		_build_info()
		_dress(GameState.peek_equipment(_selected))


func _dress(gear: Dictionary) -> void:
	Player.dress_rig(_rig, gear)
	var cls := ClassLibrary.get_class_def(_new_class if _creating else String(GameState.character_info(_selected).get("class", "warrior")))
	_rig.modulate = Color.WHITE.lerp(cls.color, 0.15)


# ---------- left: the list ----------

func _build_list() -> void:
	UIKit.clear(_list)
	for c in GameState.characters:
		var on: bool = not _creating and c.id == _selected
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 78)
		b.add_theme_stylebox_override("normal", UIKit.box(
			Color(0.24, 0.16, 0.09) if on else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.80, 0.40) if on else Color(0.32, 0.26, 0.20), 2 if on else 1, 8))
		b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
		b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("normal"))
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


func _play() -> void:
	if GameState.select_character(_selected):
		get_tree().change_scene_to_file(_first_scene())


## New characters (and ones who quit midway) go to the tutorial map first.
static func _first_scene() -> String:
	return TOWN_SCENE if GameState.tutorial_stage >= GameState.TUTORIAL_DONE else TutorialMap.SCENE


# ---------- right: creating a character ----------

func _build_create() -> void:
	UIKit.clear(_right)
	_right.add_child(UIKit.label("CREATE A CHARACTER", 26, Color(1.0, 0.90, 0.60)))
	_right.add_child(UIKit.label("CLASS", 14, UIKit.TEXT_DIM))
	var classes := HBoxContainer.new()
	classes.add_theme_constant_override("separation", 10)
	_right.add_child(classes)
	for id in ClassLibrary.CLASS_IDS:
		var cls := ClassLibrary.get_class_def(id)
		var on: bool = id == _new_class
		var b := UIKit.button(cls.display_name, Color(0.24, 0.16, 0.09) if on else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.80, 0.40) if on else Color(0.32, 0.26, 0.20), Vector2(150, 56), 18)
		b.pressed.connect(func():
			_new_class = id
			_refresh()
		)
		classes.add_child(b)
	var cls := ClassLibrary.get_class_def(_new_class)
	_right.add_child(UIKit.label(cls.description, 15, UIKit.TEXT_DIM, true))

	_right.add_child(UIKit.label("NAME", 14, UIKit.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.max_length = GameState.NAME_MAX_LEN
	_name_edit.placeholder_text = "Enter a name"
	_name_edit.custom_minimum_size = Vector2(0, 56)
	_name_edit.add_theme_font_size_override("font_size", 22)
	for st in [["normal", Color(0.55, 0.45, 0.30)], ["focus", Color(0.95, 0.80, 0.40)]]:
		var sb := UIKit.box(Color(0.05, 0.04, 0.06), st[1], 2, 6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		_name_edit.add_theme_stylebox_override(st[0], sb)
	_name_edit.text_submitted.connect(func(_t): _create())
	_name_edit.text_changed.connect(func(_t): _name_error.text = "")
	_right.add_child(_name_edit)
	_name_error = UIKit.label("", 14, Color(1.0, 0.45, 0.45))
	_right.add_child(_name_error)
	_right.add_child(_spacer())

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
	if GameState.create_character(_name_edit.text, _new_class) != "":
		get_tree().change_scene_to_file(_first_scene())


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s
