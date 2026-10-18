class_name WaypointUI
extends CanvasLayer
## The waypoint menu: travel to Ashfall Outpost or any zone whose waypoint you've touched.

var here := ""  # the zone (or ActDB.TOWN) this waypoint is in: not listed as a destination

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
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", UIKit.window_box(22, Color(0.8, 0.95, 1.0), true))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	UIKit.window_header(v, "✦ WAYPOINTS", Color(0.6, 0.9, 1.0), close)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	UIKit.clear(_list)
	var dests: Array = [ActDB.TOWN] + ActDB.known_waypoints()
	var act := 0
	for z in dests:
		if z == here:
			continue
		var zact: int = 1 if z == ActDB.TOWN else int(ActDB.zone(z).get("act", 1))
		if zact != act:
			act = zact
			_list.add_child(UIKit.label("ACT %d" % act, 15, Color(0.79, 0.65, 0.36)))
		var b := UIKit.button(ActDB.zone_name(z), Color(0.10, 0.14, 0.18), Color(0.55, 0.85, 1.0), Vector2(0, 48), 18)
		var dest: String = z
		b.pressed.connect(func():
			close()
			ActDB.travel(get_tree(), dest, "waypoint")
		)
		_list.add_child(b)
	if _list.get_child_count() <= 1:
		_list.add_child(UIKit.label("Touch the waypoint stones you find out in the world to travel between them.", 15, UIKit.TEXT_DIM, true))
	_root.visible = true
	get_tree().paused = true


func close() -> void:
	_root.visible = false
	get_tree().paused = false
