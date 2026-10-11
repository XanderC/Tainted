class_name RespecUI
extends CanvasLayer
## The respec NPC's dialog: unlearn every passive in the passive tree and get all the points back
## (free). Skill gems and their supports are not touched; rearrange those in the Skills tab.

var _root: Control
var _body: RichTextLabel
var _btn: Button


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _root.visible:
		close()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := UIKit.box(Color(0.07, 0.06, 0.10, 0.98), Color(0.55, 0.75, 0.95), 3, 12)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := UIKit.label("🔮 FORGET YOUR TRAINING", 24, Color(0.70, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_body = UIKit.rich("", 17)
	v.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cancel := UIKit.button("Cancel", Color(0.18, 0.12, 0.14), Color(0.60, 0.30, 0.30), Vector2(140, 56), 19)
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_btn = UIKit.button("🔮 Reset Passives", Color(0.12, 0.18, 0.30), Color(0.55, 0.75, 1.0), Vector2(0, 56), 20)
	_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn.pressed.connect(func():
		GameState.reset_all_skills()
		_body.text = "[center][color=#4ade80]Your mind is clear.[/color]\n\nYou have [b]%d[/b] points to spend.\nOpen the Passive Tree to choose again.[/center]" % GameState.skill_points
		_btn.disabled = true
	)
	row.add_child(_btn)


## Points a reset would hand back.
static func refundable_points() -> int:
	return GameState.points_spent()


func _refresh() -> void:
	var n := refundable_points()
	_btn.disabled = n <= 0
	if n <= 0:
		_body.text = "[center]You have nothing to unlearn yet.[/center]"
		return
	_body.text = ("[center]Unlearn every passive and get [b][color=#ffd75a]%d[/color][/b] points back.\n\n" +
		"[color=#bdb6aa]Your skill gems and supports stay as they are.\nThis is free.[/color][/center]") % n
