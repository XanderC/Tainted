class_name DialogueUI
extends CanvasLayer
## Talking to an NPC: their name on the title band, what they say, and choices underneath, which are
## the quest options Quests.npc_options gives (take a quest, hand one in, a quest line) plus any
## extras the scene adds (a vendor's "Trade"), and Goodbye. Pauses the game while open.

var player: Player

var _root: Control
var _name_lbl: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _npc := ""
var _extras: Array = []


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override("panel", UIKit.window_box(22, Color.WHITE, true))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := UIKit.window_header(v, "", UIKit.GOLD, close, 22)
	_name_lbl = head.get_child(0)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.inset_box(16))
	v.add_child(box)
	_text = UIKit.rich("", 17)
	_text.custom_minimum_size = Vector2(0, 90)
	box.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	v.add_child(_choices)


func is_open() -> bool:
	return _root.visible


## Talk to `npc_id`. `extras` are more choices: [{"label", "action": Callable}] (they close this first).
func open(npc_id: String, extras: Array = []) -> void:
	_npc = npc_id
	_extras = extras
	var n := QuestDB.npc(npc_id)
	_name_lbl.text = "%s%s" % [n["name"], ("  —  " + String(n["title"])) if n.get("title", "") != "" else ""]
	_root.visible = true
	get_tree().paused = true
	_main_view()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _main_view(text := "") -> void:
	_text.text = text if text != "" else String(QuestDB.npc(_npc).get("greeting", ""))
	UIKit.clear(_choices)
	for o in Quests.npc_options(_npc):
		var accent := Color(1.0, 0.85, 0.4) if o["action"] == "offer" else (Color(0.45, 1.0, 0.55) if o["action"] in ["turn_in", "talk"] else Color(0.7, 0.65, 0.6))
		_choice(String(o["label"]), accent, _pick.bind(o))
	for e in _extras:
		var act: Callable = e["action"]
		_choice(String(e["label"]), Color(0.75, 0.58, 0.30), func():
			close()
			act.call()
		)
	_choice("Goodbye", Color(0.55, 0.40, 0.35), close)


func _pick(o: Dictionary) -> void:
	var q := QuestDB.quest(String(o["quest"]))
	match String(o["action"]):
		"offer":
			_text.text = String(o["text"])
			UIKit.clear(_choices)
			_choice("✔  Accept: " + String(q["name"]), Color(0.45, 1.0, 0.55), func():
				Quests.start(String(o["quest"]))
				_main_view("[color=#ffd54a]Quest accepted: %s[/color]\n%s" % [q["name"], q.get("summary", "")])
			)
			_choice("Not now", Color(0.55, 0.40, 0.35), _main_view)
		"talk":
			Quests.notify("talk", _npc)
			_show(String(o["text"]))
		"turn_in":
			var got := Quests.turn_in(String(o["quest"]), player)
			var t := String(o["text"])
			if not got.is_empty():
				t += "\n\n[color=#ffd54a]Quest complete: %s[/color]\n[color=#9be39b]%s[/color]" % [q["name"], "\n".join(got)]
			_show(t)
		_:
			_show(String(o["text"]))


## A line to read, then back to the choices.
func _show(text: String) -> void:
	_text.text = text
	UIKit.clear(_choices)
	_choice("Continue", Color(0.75, 0.58, 0.30), func(): _main_view())


func _choice(label: String, accent: Color, on_pick: Callable) -> void:
	var b := UIKit.button(label, Color(0.12, 0.10, 0.12), accent, Vector2(0, 46), 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(on_pick)
	_choices.add_child(b)
