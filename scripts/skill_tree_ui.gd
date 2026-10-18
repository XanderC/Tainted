class_name SkillTreeUI
extends CanvasLayer
## The class's passive tree (Path of Exile style, one tree per class, see PassiveTree). Spend the
## points you earn from levelling on nodes linked to ones you already have; refund
## any node that isn't holding others up (an Orb of Regret each), or Respec the whole tree for
## free in town (tap twice to confirm). Active skills are skill gems (inventory Skills tab).

var player: Player
## Only the town's tree can Respec; in a rift or the tutorial the button says to go to town.
var can_respec := false

var _root: Control
var _selected_id := ""
var _points_label: Label
var _respec_btn: Button
var _respec_armed := false
var _btn_open: Button
var _tree_canvas: SkillTreeCanvas
var _detail_vbox: VBoxContainer


func _ready() -> void:
	layer = 12  # below the inventory (25); the HUD button also hides while any window is open
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("skill_tree_ui")
	_build_ui()
	GameState.skills_changed.connect(_refresh)
	GameState.changed.connect(_refresh)


func _process(_delta: float) -> void:
	if _btn_open != null:
		_btn_open.visible = not get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K or event.keycode == KEY_P:
			toggle()
		elif event.keycode == KEY_ESCAPE and is_open():
			close()


func is_open() -> bool:
	return _root != null and _root.visible


func open(_unused: String = "") -> void:
	layer = 28
	_root.visible = true
	get_tree().paused = true
	_refresh()
	_render_tree.call_deferred()  # again once the layout knows the panel width


func close() -> void:
	if _root != null:
		_root.visible = false
	layer = 12
	get_tree().paused = false


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func _build_ui() -> void:
	_btn_open = UIKit.stone_button("✦ PASSIVES", Vector2(120, 56), 17)
	_btn_open.pressed.connect(open)
	add_child(_btn_open)
	_btn_open.anchor_left = 1.0
	_btn_open.anchor_right = 1.0
	_btn_open.offset_left = -256.0
	_btn_open.offset_right = -136.0
	_btn_open.offset_top = 16.0
	_btn_open.offset_bottom = 72.0

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.03, 0.05, 0.92)
	_root.add_child(bg)

	var win := PanelContainer.new()
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	win.clip_contents = true
	var win_sb := UIKit.window_box(20, Color.WHITE, true)
	win.add_theme_stylebox_override("panel", win_sb)
	_root.add_child(win)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	win.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.custom_minimum_size = Vector2(0, UIKit.HEADER_ROW_H)
	outer.add_child(header)
	outer.add_child(UIKit.header_gap())
	var cls_name := player.class_def.display_name if player != null and player.class_def != null else "Warrior"
	header.add_child(UIKit.label("✦ %s PASSIVE TREE" % cls_name.to_upper(), 22, Color(0.95, 0.85, 0.55)))
	_points_label = UIKit.label("", 19, Color(1.0, 0.85, 0.30))
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_points_label)
	_respec_btn = UIKit.button("", Color(0.12, 0.18, 0.30), Color(0.55, 0.75, 1.0), Vector2(150, 43), 17)
	_respec_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_respec_btn.pressed.connect(_on_respec)
	header.add_child(_respec_btn)
	var close_btn := UIKit.close_button(1.0)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var workspace := HBoxContainer.new()
	workspace.add_theme_constant_override("separation", 14)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(workspace)

	var tree_panel := PanelContainer.new()
	tree_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_panel.size_flags_stretch_ratio = 1.4
	var tp_sb := UIKit.inset_box(8)
	tp_sb.set_content_margin_all(8)
	tree_panel.add_theme_stylebox_override("panel", tp_sb)
	workspace.add_child(tree_panel)
	var tree_box := Control.new()
	tree_panel.add_child(tree_box)
	_tree_canvas = SkillTreeCanvas.new()
	tree_box.add_child(_tree_canvas)
	_tree_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tree_canvas.node_selected.connect(func(id: String):
		_selected_id = id
		_refresh()
	)
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 6)
	tree_box.add_child(zoom_row)
	zoom_row.position = Vector2(8, 8)
	for z in [["＋", 1.25], ["－", 0.8], ["◎", 0.0]]:
		var zb := UIKit.button(z[0], Color(0.12, 0.10, 0.14, 0.9), Color(0.6, 0.5, 0.3), Vector2(48, 44), 20)
		var f: float = z[1]
		zb.pressed.connect(func():
			if f == 0.0:
				_tree_canvas.center()
			else:
				_tree_canvas.zoom_by(f)
		)
		zoom_row.add_child(zb)

	var detail := PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dt_sb := UIKit.inset_box(12, Color(1.0, 0.85, 0.85))
	dt_sb.set_content_margin_all(12)
	detail.add_theme_stylebox_override("panel", dt_sb)
	workspace.add_child(detail)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(scroll)
	_detail_vbox = VBoxContainer.new()
	_detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_detail_vbox)


func _refresh() -> void:
	if not is_open():
		return
	_points_label.text = "%d UNSPENT POINTS     %d spent" % [GameState.skill_points, GameState.points_spent()]
	_respec_btn.text = "⚠ Tap to confirm" if _respec_armed else ("↺ Respec" if can_respec else "↺ Respec in town")
	_respec_btn.disabled = not can_respec or GameState.points_spent() <= 0
	_render_tree()
	_render_inspector()


## Free full reset of the passive tree. The first tap arms it, the second (within 3 s) resets.
func _on_respec() -> void:
	if not can_respec:
		return
	if not _respec_armed:
		_respec_armed = true
		_refresh()
		await get_tree().create_timer(3.0, true).timeout
		if _respec_armed:
			_respec_armed = false
			_refresh()
		return
	_respec_armed = false
	GameState.reset_all_skills()
	_selected_id = ""
	_refresh()


func _render_tree() -> void:
	if player != null and player.class_def != null:
		_tree_canvas.class_id = player.class_def.id
	_tree_canvas.selected_id = _selected_id
	_tree_canvas.rebuild()


func _render_inspector() -> void:
	UIKit.clear(_detail_vbox)
	var n := PassiveTree.get_node(_tree_canvas.class_id, _selected_id) if _selected_id != "" else {}
	if n.is_empty():
		_detail_vbox.add_child(UIKit.rich("[color=#8a7f6e]Drag to move around the tree, pinch or use ＋ / － to zoom.\n\n" +
			"Tap a node to see it. You can take any node linked to one you already have (1 point each), " +
			"starting from the Warrior in the middle.\n\n" +
			"[color=#d6c08a]Small[/color] nodes give a little, [color=#d6c08a]notables[/color] (bigger rings) a lot, and " +
			"[color=#d6c08a]keystones[/color] (double rings, at the end of each branch) change how you play, with a drawback.[/color]", 15))
		return
	var on := GameState.is_node_allocated(_selected_id)
	var kind_name := {"start": "CLASS START", "small": "PASSIVE", "notable": "NOTABLE PASSIVE", "keystone": "KEYSTONE"}
	_detail_vbox.add_child(UIKit.label(String(n.name).to_upper(), 20, Color(1.0, 0.88, 0.45)))
	_detail_vbox.add_child(UIKit.label(kind_name.get(n.kind, ""), 12, Color(0.70, 0.65, 0.60)))
	if n.kind == "start":
		_detail_vbox.add_child(UIKit.label("Where your tree begins.", 14, Color(0.9, 0.88, 0.82), true))
		return
	_detail_vbox.add_child(UIKit.rich("[color=#%s]%s[/color]" % ["34d399" if on else "e2d9c8", PassiveTree.stat_text(n.stats)], 16))
	if on:
		var regrets := GameState.orb_count("regret")
		var refund := UIKit.button("↺ Refund: 1 Orb of Regret (have %d)" % regrets, Color(0.25, 0.12, 0.10), Color(0.85, 0.45, 0.30), Vector2(0, 46), 16)
		var connected := GameState.can_refund_node(_selected_id)
		refund.disabled = not connected or regrets <= 0
		refund.pressed.connect(func():
			if GameState.refund_node(_selected_id):
				_refresh()
		)
		_detail_vbox.add_child(refund)
		if not connected:
			_detail_vbox.add_child(UIKit.label("Other nodes you have connect through this one.", 13, UIKit.TEXT_DIM, true))
		elif regrets <= 0:
			_detail_vbox.add_child(UIKit.label("You need an Orb of Regret (or Respec the whole tree for free in town).", 13, UIKit.TEXT_DIM, true))
	else:
		var btn := UIKit.button("➕ Allocate (1 point)", Color(0.12, 0.35, 0.18), Color(0.35, 1.0, 0.50), Vector2(0, 46), 16)
		var why := GameState.node_block_reason(_selected_id)
		btn.disabled = why != ""
		btn.pressed.connect(func():
			if GameState.allocate_node(_selected_id):
				_refresh()
		)
		_detail_vbox.add_child(btn)
		if why != "":
			_detail_vbox.add_child(UIKit.label("🔒 " + why, 13, Color(1.0, 0.45, 0.45), true))
