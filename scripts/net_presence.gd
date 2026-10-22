class_name NetPresence
extends Node
## Puts the other players of an instance (Net) into a scene: add it to a scene with `instance`
## set (Net.TOWN in town), and while online it enters that instance, shows each player there as a
## RemotePlayer in its parent (the y-sorted world), and leaves the instance when the scene goes.
## A small line at the top of the screen says you're online and who is about. Party members off
## screen get an arrow at the edge pointing to them, and going to one (Net.go_to) puts you beside
## them once they appear here.

var instance := Net.TOWN
var _remotes := {}  # peer id -> RemotePlayer
var _line: Label
var _toast: Label
var _layer: CanvasLayer
var _arrows := {}  # peer id -> PortalArrow: party members, pointed at while off screen


func _ready() -> void:
	Net.peer_joined.connect(_on_joined)
	Net.peer_left.connect(_on_left)
	Net.peer_state.connect(_on_state)
	Net.peer_looks.connect(_on_looks)
	Net.status_changed.connect(_on_status)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_layer = layer
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


func _process(_delta: float) -> void:
	var members: Array = Net.party.get("members", []).map(func(m): return int(m.id)) if Net.in_party() else []
	for id in _remotes:
		var want: bool = members.has(id) and is_instance_valid(GameState.player)
		if want and not _arrows.has(id):
			var a := PortalArrow.new()
			a.player = GameState.player
			a.target = _remotes[id]
			a.label_text = _remotes[id]._name.text.get_slice("\n", 0)
			a.color = RemotePlayer.NAME_COLOR
			_layer.add_child(a)
			_arrows[id] = a
		elif not want and _arrows.has(id):
			_arrows[id].queue_free()
			_arrows.erase(id)
	for id in _arrows.keys():
		if not _remotes.has(id):
			_arrows[id].queue_free()
			_arrows.erase(id)
	_arrive_beside()


## Going to a party member (Net.go_to): once they're here and so is the ground (a rift's maze comes
## from its host), stand beside them.
func _arrive_beside() -> void:
	var id := Net.go_to_peer
	if id == 0:
		return
	if Time.get_ticks_msec() > Net.go_to_until:
		Net.go_to_peer = 0
		return
	var world := get_parent()
	var p = GameState.player
	if not _remotes.has(id) or not is_instance_valid(p) or not p.is_inside_tree() or ("maze" in world and world.maze == null):
		return
	if "run" in world and world.run is DungeonRun and world.get("_travelling"):
		return
	Net.go_to_peer = 0
	p.global_position = _remotes[id]._target + Vector2(30, 0)
	p.velocity = Vector2.ZERO


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
		if Net.status != "" and Net.mode != Net.Mode.RECONNECTING:
			_say(Net.status)
	elif Net.status.begins_with("Reconnected"):
		_say(Net.status)
	_refresh_line()


func _refresh_line() -> void:
	if Net.mode == Net.Mode.RECONNECTING:
		_line.text = "⚠ " + Net.status
		return
	if not Net.online() or Net.party_of_instance(instance) != 0:  # a party's rift: the party list says who's there
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
