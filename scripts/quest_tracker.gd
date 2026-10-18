class_name QuestTracker
extends PanelContainer
## The HUD's quest list (top left): each active quest and what to do next. Tap it for the quest log.

signal open_log

var _text: RichTextLabel


func _ready() -> void:
	add_theme_stylebox_override("panel", UIKit.inset_box(10, Color(1, 1, 1, 0.92)))
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_text = UIKit.rich("", 14)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	GameState.quests_changed.connect(refresh)
	refresh()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		open_log.emit()
		accept_event()


func refresh() -> void:
	var lines := Quests.tracker_lines()
	visible = not lines.is_empty()
	var t := "[color=#c9a55c][b]QUESTS[/b][/color]  [color=#7d746a](tap for log)[/color]"
	for l in lines:
		var col := "#ffd54a" if l["kind"] == "main" else "#9fd3ff"
		t += "\n[color=%s]%s[/color]\n  [color=#e8e0d0]%s[/color]" % [col, l["title"], l["text"]]
	_text.text = t
