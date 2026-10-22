class_name ChatUI
extends Node
## The chat (Net.say / Net.chat), wherever you are online: Net owns it, so it lasts across scenes.
## Recent lines show at the bottom left, above the 💬 button, and fade after FADE_AFTER seconds; the
## button (or Enter on a computer) opens a box to type in, with Local / Party to pick who hears it.
## While the box has the keyboard, the game ignores its keys (Net.chat_typing). Hidden offline and on
## the character select screen. The button is "touch_exempt": the movement stick leaves it alone.

const KEEP := 40  ## lines remembered
const SHOWN := 6  ## lines shown while the box is shut
const FADE_AFTER := 12.0
const WIDTH := 400.0  ## clear of the life globe
const COLORS := {"local": Color(0.92, 0.90, 0.84), "party": Color(0.55, 0.85, 1.0), "notice": Color(1.0, 0.85, 0.45),
	"server": Color(1.0, 0.62, 0.35)}

var _layer: CanvasLayer
var _log: VBoxContainer
var _btn: Button
var _box: HBoxContainer
var _edit: LineEdit
var _chan_btn: Button
var _channel := "local"
var _lines: Array = []  # [{"text": bbcode, "at": msec}]
var _open := false


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 7
	add_child(_layer)

	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 1)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = 16.0
	_log.offset_right = 16.0 + WIDTH
	_log.offset_bottom = -76.0
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layer.add_child(_log)

	_btn = UIKit.stone_button("💬", Vector2(52, 44), 20)
	_btn.tooltip_text = "Chat (Enter)"
	_btn.anchor_top = 1.0
	_btn.anchor_bottom = 1.0
	_btn.offset_left = 16.0
	_btn.offset_right = 68.0
	_btn.offset_top = -64.0
	_btn.offset_bottom = -20.0
	_btn.add_to_group("touch_exempt")
	_btn.pressed.connect(func(): _set_open(not _open))
	_layer.add_child(_btn)

	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = 76.0
	_box.offset_right = 76.0 + WIDTH
	_box.offset_top = -64.0
	_box.offset_bottom = -20.0
	_box.add_to_group("touch_exempt")
	_box.visible = false
	_layer.add_child(_box)
	_chan_btn = UIKit.button("Local", Color(0.16, 0.16, 0.20), Color(0.6, 0.6, 0.65), Vector2(78, 44), 14)
	_chan_btn.pressed.connect(_toggle_channel)
	_box.add_child(_chan_btn)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.max_length = Net.CHAT_MAX
	_edit.placeholder_text = "Say something..."
	_edit.add_theme_font_size_override("font_size", 16)
	_edit.text_submitted.connect(_send)
	_edit.focus_entered.connect(func(): Net.chat_typing = true)
	_edit.focus_exited.connect(func(): Net.chat_typing = false)
	_box.add_child(_edit)
	var send := UIKit.button("Send", Color(0.12, 0.26, 0.40), Color(0.50, 0.80, 1.0), Vector2(70, 44), 14)
	send.pressed.connect(func(): _send(_edit.text))
	_box.add_child(send)

	Net.chat.connect(_on_chat)
	Net.party_changed.connect(func():
		if not Net.in_party() and _channel == "party":
			_toggle_channel())


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var show := Net.online() and scene != null and not scene is CharacterSelect
	_layer.visible = show
	if not show and _open:
		_set_open(false)
	# Lines fade a while after they came (all of them stay while the box is open)
	var now := Time.get_ticks_msec()
	var kids := _log.get_children()
	for i in kids.size():
		var line: Dictionary = _lines[_lines.size() - kids.size() + i] if _lines.size() >= kids.size() else {}
		var age := (now - int(line.get("at", now))) / 1000.0
		kids[i].modulate.a = 1.0 if _open else clampf((FADE_AFTER + 2.0 - age) / 2.0, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _layer.visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not _open:
		_set_open(true)
		get_viewport().set_input_as_handled()


func _set_open(on: bool) -> void:
	_open = on
	_box.visible = on
	if on:
		_edit.grab_focus.call_deferred()
	else:
		_edit.release_focus()
		Net.chat_typing = false
	_rebuild()


func _toggle_channel() -> void:
	_channel = "party" if _channel == "local" and Net.in_party() else "local"
	_chan_btn.text = "Party" if _channel == "party" else "Local"
	_chan_btn.add_theme_color_override("font_color", COLORS[_channel])


func _send(text: String) -> void:
	if text.strip_edges() != "":
		Net.say(_channel, text)
	_edit.text = ""
	_set_open(false)


func _on_chat(_from: int, from_name: String, channel: String, text: String) -> void:
	var col: Color = COLORS.get(channel, COLORS.local)
	var tag := "[Party] " if channel == "party" else ("[Server] " if channel == "server" else "")
	_lines.append({"text": "[color=#%s]%s[b]%s:[/b] %s[/color]" % [col.to_html(false), tag, _esc(from_name), _esc(text)],
		"at": Time.get_ticks_msec()})
	if _lines.size() > KEEP:
		_lines = _lines.slice(_lines.size() - KEEP)
	_rebuild()


## The newest lines: SHOWN of them, or more while the box is open.
func _rebuild() -> void:
	UIKit.clear(_log)
	var n := mini(_lines.size(), 12 if _open else SHOWN)
	for line in _lines.slice(_lines.size() - n):
		var r := UIKit.rich(line.text, 15)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_color_override("font_outline_color", Color.BLACK)
		r.add_theme_constant_override("outline_size", 5)
		r.custom_minimum_size.x = WIDTH
		_log.add_child(r)


## Text shown as typed (no BBCode from other players).
static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
