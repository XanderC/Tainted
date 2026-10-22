class_name InspectUI
extends Node
## Another player's gear and stats (Net.inspect -> Net.inspected): their worn items in a grid by
## slot, a few stats, and, tapping an item, its card beside what you wear in that slot (ItemTip).
## Net owns it; it shows over everything until closed.

const CELL := Vector2(64, 64)
const STAT_NAMES := {"damage": "Damage", "attack_speed": "Attacks / s", "crit_chance": "Critical chance",
	"armor": "Armour", "max_life": "Life", "move_speed": "Move speed"}

var _layer: CanvasLayer
var _win: PanelContainer
var _tip: ItemTip


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 31
	add_child(_layer)
	_tip = ItemTip.new()
	_tip.z_index = 60
	Net.inspected.connect(show_data)
	Net.status_changed.connect(func():
		if not Net.online():
			close())


func close() -> void:
	if _win != null:
		_win.queue_free()
		_win = null
	if _tip.get_parent() != null:
		_tip.close()


func show_data(_id: int, data: Dictionary) -> void:
	close()
	_win = PanelContainer.new()
	_win.add_theme_stylebox_override("panel", UIKit.window_box(20, Color.WHITE, true))
	_win.custom_minimum_size = Vector2(560, 0)
	_win.set_anchors_preset(Control.PRESET_CENTER)
	_win.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_win.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_win)
	if _tip.get_parent() == null:
		_layer.add_child(_tip)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_win.add_child(v)
	var cd := ClassLibrary.get_class_def(String(data.get("class", "warrior")))
	var head := UIKit.window_header(v, "%s  •  Level %d %s" % [String(data.get("name", "?")), int(data.get("level", 1)), cd.display_name],
		RemotePlayer.NAME_COLOR, close, 20)
	(head.get_node("Title") as Label).add_theme_font_override("font", UIKit.body_font(700))  # Cinzel's 1 reads as I

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var eq = data.get("equipment", {})
	for slot in Player.SLOTS:
		var it: ItemInstance = ItemInstance.from_dict(eq[slot]) if eq is Dictionary and eq.get(slot) is Dictionary else null
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		grid.add_child(col)
		var cell := UIKit.item_cell(it, false, CELL)
		if it == null:
			cell.set_placeholder(UIKit.slot_icon(slot))
		else:
			var mine: ItemInstance = GameState.player.equipment.get(slot) if is_instance_valid(GameState.player) else null
			cell.clicked.connect(func():
				var deltas := UIKit.equip_deltas(GameState.player, it) if mine != null and is_instance_valid(GameState.player) else {}
				_tip.show_card(it, _win.get_viewport().get_mouse_position(), {}, Callable(), mine, deltas))
		col.add_child(cell)
		var l := UIKit.label(String(UIKit.SLOT_NAMES.get(slot, slot)), 11, UIKit.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = CELL.x
		col.add_child(l)

	var stats = data.get("stats", {})
	if stats is Dictionary and not stats.is_empty():
		var sec := UIKit.section(v, "STATS")
		var sg := GridContainer.new()
		sg.columns = 2
		sg.add_theme_constant_override("h_separation", 24)
		sec.add_child(sg)
		for k in STAT_NAMES:
			if stats.has(k):
				var val := float(stats[k])
				var txt := ("%d%%" % int(round(val * 100.0))) if k == "crit_chance" else ("%.2f" % val if k == "attack_speed" else "%d" % int(val))
				sg.add_child(UIKit.label(STAT_NAMES[k], 14, UIKit.TEXT_DIM))
				sg.add_child(UIKit.label(txt, 14, Color(0.92, 0.90, 0.84)))
	v.add_child(UIKit.label("Tap an item to see it beside what you wear.", 12, UIKit.TEXT_DIM))
