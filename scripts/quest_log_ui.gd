class_name QuestLogUI
extends CanvasLayer
## Every quest you've taken (main quests first): what it's about and each step, done or to do.
## Opens from the quest tracker or with J.

var _root: Control
var _list: VBoxContainer


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", UIKit.window_box(20, Color.WHITE, true))
	_root.add_child(win)
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	UIKit.window_header(v, "📜 QUEST LOG", UIKit.GOLD, close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	_build()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


func toggle() -> void:
	if _root.visible:
		close()
	elif not get_tree().paused:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_J:
		toggle()
	elif event.keycode == KEY_ESCAPE and _root.visible:
		close()


func _build() -> void:
	UIKit.clear(_list)
	var any := false
	for kind in ["main", "side"]:
		for id in QuestDB.QUESTS:
			var q := QuestDB.quest(id)
			var st := Quests.state(id)
			if q.get("kind", "side") != kind or st == "":
				continue
			any = true
			_card(id, q, st)
	if not any:
		_list.add_child(UIKit.label("No quests yet. People in Ashfall Outpost with a gold ! over their heads have work for you.", 16, UIKit.TEXT_DIM, true))


func _card(id: String, q: Dictionary, st: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.inset_box(14))
	_list.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var kind_txt := "ACT %d  •  %s" % [int(q.get("act", 1)), "MAIN QUEST" if q.get("kind", "") == "main" else "SIDE QUEST"]
	var state_txt: String = {"active": "", "ready": "  •  [color=#9be39b]Ready to hand in[/color]", "done": "  •  [color=#7d746a]Complete[/color]"}[st]
	var col := "#ffd54a" if q.get("kind", "") == "main" else "#9fd3ff"
	var t := "[color=%s][b]%s[/b][/color]   [color=#7d746a]%s[/color]%s\n[color=#bdb6aa]%s[/color]\n" % [col, q["name"], kind_txt, state_txt, q.get("summary", "")]
	var steps: Array = q.get("steps", [])
	var at := Quests.step_index(id)
	for i in steps.size():
		var done := st != "active" or i < at
		if not done and i > at:
			break  # later steps stay hidden until you get there
		t += "\n%s %s" % ["[color=#7fbf7f]✔[/color]" if done else "[color=#ffd54a]•[/color]",
			("[color=#8a8278]%s[/color]" if done else "[color=#f3e6c4]%s[/color]") % steps[i]["text"]]
	if st == "ready":
		t += "\n[color=#ffd54a]•[/color] [color=#f3e6c4]Return to %s[/color]" % QuestDB.npc(String(q.get("turn_in", ""))).get("name", "")
	v.add_child(UIKit.rich(t, 16))
