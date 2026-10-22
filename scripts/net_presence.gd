class_name NetPresence
extends Node
## Puts the other players of an instance (Net) into a scene: add it to a scene with `instance`
## set (Net.TOWN in town), and while online it enters that instance, shows each player there as a
## RemotePlayer in its parent (the y-sorted world), and leaves the instance when the scene goes.
## A small line at the top of the screen says you're online and who is about.

var instance := Net.TOWN
var _remotes := {}  # peer id -> RemotePlayer
var _line: Label
var _toast: Label


func _ready() -> void:
	Net.peer_joined.connect(_on_joined)
	Net.peer_left.connect(_on_left)
	Net.peer_state.connect(_on_state)
	Net.peer_looks.connect(_on_looks)
	Net.status_changed.connect(_on_status)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_line = UIKit.label("", 14, Color(0.60, 0.85, 1.0))
	_line.add_theme_color_override("font_outline_color", Color.BLACK)
	_line.add_theme_constant_override("outline_size", 5)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_line.offset_top = 6.0
	_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_line)
	_toast = UIKit.label("", 15, Color(0.85, 0.95, 1.0))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 28.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_toast)
	_refresh_line()
	Net.enter.call_deferred(instance)  # once the player is in the scene, so it arrives where it stands


func _exit_tree() -> void:
	if Net.instance == instance:
		Net.enter("")


func _on_joined(id: int, info: Dictionary, state: Dictionary) -> void:
	if _remotes.has(id):
		_remotes[id].queue_free()
	var r := RemotePlayer.new()
	get_parent().add_child(r)
	r.setup(id, info, state)
	_remotes[id] = r
	_refresh_line()


func _on_left(id: int) -> void:
	if _remotes.has(id):
		var r: RemotePlayer = _remotes[id]
		_say("%s left" % r._name.text.get_slice("\n", 0))
		r.queue_free()
		_remotes.erase(id)
	_refresh_line()


func _on_state(id: int, state: Dictionary) -> void:
	if _remotes.has(id):
		_remotes[id].apply_state(state)


func _on_looks(id: int, info: Dictionary) -> void:
	if _remotes.has(id):
		_remotes[id].apply_looks(info)


func _on_status() -> void:
	if not Net.online():
		for id in _remotes.keys():
			_remotes[id].queue_free()
		_remotes.clear()
		if Net.status != "":
			_say(Net.status)
	_refresh_line()


func _refresh_line() -> void:
	if not Net.online():
		_line.text = ""
		return
	var n := _remotes.size()
	_line.text = "🌐 %s   •   %s" % [Net.server_name, "you're the only one here" if n == 0 else "%d other player%s here" % [n, "" if n == 1 else "s"]]


func _say(text: String) -> void:
	_toast.text = text
	get_tree().create_timer(4.0, true, false, true).timeout.connect(func():
		if is_instance_valid(_toast) and _toast.text == text:
			_toast.text = ""
	)
