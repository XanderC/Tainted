class_name RiftSelectUI
extends CanvasLayer
## Rift gate in town: pick a rift level (1 .. GameState.rift_unlocked) and enter.
## Shows how much tougher the monsters are and how much better the rewards get.

signal enter_requested

var _root: Control
var _level := 1
var _level_lbl: Label
var _info: RichTextLabel
var _prev: Button
var _next: Button


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
	_level = clampi(GameState.rift_level, 1, GameState.rift_unlocked)
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
	var sb := UIKit.window_box(22, Color(0.85, 0.65, 1.0), true)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	UIKit.window_header(v, "🌀 RIFT GATE", Color(0.88, 0.68, 1.0), close, 24)

	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 18)
	v.add_child(picker)
	_prev = UIKit.button("◀", Color(0.16, 0.10, 0.22), Color(0.70, 0.45, 1.0), Vector2(72, 64), 26)
	_prev.pressed.connect(func():
		_level -= 1
		_refresh()
	)
	picker.add_child(_prev)
	_level_lbl = UIKit.label("", 30, Color(1.0, 0.92, 0.6))
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_lbl.custom_minimum_size = Vector2(200, 0)
	picker.add_child(_level_lbl)
	_next = UIKit.button("▶", Color(0.16, 0.10, 0.22), Color(0.70, 0.45, 1.0), Vector2(72, 64), 26)
	_next.pressed.connect(func():
		_level += 1
		_refresh()
	)
	picker.add_child(_next)

	var info_box := PanelContainer.new()
	info_box.add_theme_stylebox_override("panel", UIKit.inset_box(14))
	v.add_child(info_box)
	_info = UIKit.rich("", 17)
	info_box.add_child(_info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var enter := UIKit.button("🌀 Enter Rift", Color(0.20, 0.10, 0.30), Color(0.85, 0.55, 1.0), Vector2(0, 56), 21)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.pressed.connect(func():
		GameState.rift_level = _level
		close()
		enter_requested.emit()
	)
	row.add_child(enter)


func _refresh() -> void:
	_level = clampi(_level, 1, GameState.rift_unlocked)
	_level_lbl.text = "Level %d" % _level
	_prev.disabled = _level <= 1
	_next.disabled = _level >= GameState.rift_unlocked
	var L := _level
	_info.text = ("[color=#bdb6aa]Monster Life[/color]   [color=#f87171][b]×%.2f[/b][/color]\n" +
		"[color=#bdb6aa]Monster Damage[/color]   [color=#f87171][b]×%.2f[/b][/color]\n" +
		"[color=#bdb6aa]Item Level[/color]   [color=#4ade80][b]+%d[/b][/color]\n" +
		"[color=#bdb6aa]Orbs & Shards[/color]   [color=#4ade80][b]+%d%%[/b][/color]\n" +
		"[color=#bdb6aa]Extra Boss Items[/color]   [color=#4ade80][b]+%d[/b][/color]\n\n" +
		"[color=#c084fc]Clear in %s to unlock the next level.[/color]   [color=#888888]Highest unlocked: %d[/color]") % [
		DungeonRun.hp_mult(L), DungeonRun.damage_mult(L), DungeonRun.ILVL_PER_LEVEL * (L - 1),
		int(round((DungeonRun.reward_mult(L) - 1.0) * 100.0)), int((L - 1) / float(DungeonRun.EXTRA_ITEM_EVERY)),
		DungeonRun.fmt_time(DungeonRun.TIME_LIMIT), GameState.rift_unlocked]
