class_name InstanceChoice
extends CanvasLayer
## "Carry on, or start over?": asked when you are about to enter somewhere that is still as you left it (a zone
## kept by ZoneInstances, a rift you left through a town portal). The game is paused while it is up.
## ask() takes on_pick (called with "continue" or "reset") and on_cancel (backing out: stay where you are).

var _title := ""
var _text := ""
var _continue_text := "Continue"
var _reset_text := "Reset"
var _hint := ""
var _on_pick: Callable
var _on_cancel: Callable
var _done := false


static func ask(tree: SceneTree, title: String, text: String, on_pick: Callable, on_cancel := Callable(),
		continue_text := "Continue", reset_text := "Reset", hint := "") -> InstanceChoice:
	var ui := InstanceChoice.new()
	ui._title = title
	ui._text = text
	ui._continue_text = continue_text
	ui._reset_text = reset_text
	ui._hint = hint
	ui._on_pick = on_pick
	ui._on_cancel = on_cancel
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(ui)
	return ui


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.03, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.window_box(22, Color.WHITE, true))
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	UIKit.window_header(box, _title, UIKit.GOLD)
	var text := UIKit.label(_text, 17, Color(0.92, 0.88, 0.8), true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	if _hint != "":
		var hint := UIKit.label(_hint, 14, UIKit.TEXT_DIM, true)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var go := UIKit.button(_continue_text, Color(0.16, 0.12, 0.08), Color(0.95, 0.80, 0.30), Vector2(0, 52), 18)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func(): _pick("continue"))
	row.add_child(go)
	var reset := UIKit.button(_reset_text, Color(0.20, 0.08, 0.06), Color(0.95, 0.45, 0.35), Vector2(0, 52), 18)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func(): _pick("reset"))
	row.add_child(reset)
	var cancel := UIKit.button("Cancel", Color(0.10, 0.10, 0.12), Color(0.6, 0.6, 0.65), Vector2(0, 52), 18)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_cancel)
	row.add_child(cancel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()


func _pick(mode: String) -> void:
	if _done:
		return
	_done = true
	var tree := get_tree()
	tree.paused = false
	queue_free()
	if _on_pick.is_valid():
		_on_pick.call_deferred(mode)


func _cancel() -> void:
	if _done:
		return
	_done = true
	get_tree().paused = false
	queue_free()
	if _on_cancel.is_valid():
		_on_cancel.call_deferred()
