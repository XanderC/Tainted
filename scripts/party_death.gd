class_name PartyDeath
extends Node
## Falling in a party's rift or zone (Coop): you stay down where you fell, and a party member who
## stands beside you for REVIVE_TIME brings you back at half life. After GET_UP_AFTER you may get up
## yourself (at the maze's start, or the zone's waypoint), and from a rift you can always go back to
## town. A rift fails only when everyone in it is down: the host's game decides, the others follow.
## While you stand, it also does your reviving: the ring filling round a fallen party member.

const REVIVE_REACH := 110.0
const REVIVE_TIME := 3.0
const GET_UP_AFTER := 20.0

var main: Node2D  ## main.gd or zone.gd: `player`, `coop`, get_up(), and (a rift) return_to_town()
var _down_t := 0.0
var _reviving := {}  # peer id -> seconds you have stood beside them
var _layer: CanvasLayer
var _hint: Label
var _get_up: Button
var _town: Button


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	_layer.visible = false
	add_child(_layer)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(box)
	var title := UIKit.label("YOU HAVE FALLEN", 30, Color(1.0, 0.4, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIKit.title_font())
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	_hint = UIKit.label("", 16, Color(0.9, 0.88, 0.82))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_get_up = UIKit.stone_button("", Vector2(260, 50))
	_get_up.pressed.connect(func():
		if main.player.dead:
			_layer.visible = false
			main.get_up())
	row.add_child(_get_up)
	_town = UIKit.stone_button("Back to town", Vector2(200, 50))
	_town.visible = main.has_method("return_to_town")
	_town.pressed.connect(func(): main.return_to_town())
	row.add_child(_town)
	main.player.died.connect(_on_died)
	Net.event.connect(_on_event)


func _on_died() -> void:
	_down_t = 0.0
	_layer.visible = true
	_refresh()


func _on_event(from: int, kind: String, _data) -> void:
	if kind != "revive" or not main.player.dead:
		return
	main.player.revive(0.5)
	_layer.visible = false
	var who := String(Net.others.get(from, {}).get("name", "A party member"))
	Net.notice.emit("%s revived you" % who)


func _process(delta: float) -> void:
	var p: Player = main.player
	if p.dead:
		_down_t += delta
		_refresh()
		_check_wipe()
		return
	var near := {}
	for rp in get_tree().get_nodes_in_group("remote_players"):
		var t := 0.0
		if rp.dead and rp.global_position.distance_to(p.global_position) < REVIVE_REACH:
			t = float(_reviving.get(rp.peer_id, 0.0)) + delta
			if t >= REVIVE_TIME:
				Net.send_event(rp.peer_id, "revive", {})
				t = -1.0  # a moment for their state to say they're up
			near[rp.peer_id] = t
		rp.revive_frac = clampf(t / REVIVE_TIME, 0.0, 1.0)
	_reviving = near


func _refresh() -> void:
	var failed := _run_failed()
	var left := GET_UP_AFTER - _down_t
	if failed:
		_hint.text = "Everyone is down: the rift has failed."
	else:
		_hint.text = "A party member can revive you: they stand beside you for %d seconds." % int(REVIVE_TIME)
	_get_up.visible = not failed
	var where := "the start" if main.has_method("return_to_town") else "the waypoint"
	_get_up.disabled = left > 0.0
	_get_up.text = "Get up at %s" % where + ("  (%d)" % int(ceil(left)) if left > 0.0 else "")


func _run() -> DungeonRun:
	var r = main.get("run")
	return r if r is DungeonRun else null


func _run_failed() -> bool:
	return _run() != null and _run().state == DungeonRun.State.FAILED


## The host's game: everyone in the rift is down, so it has failed (the others' runs follow).
func _check_wipe() -> void:
	var run := _run()
	if run == null or main.coop == null or not main.coop.is_host:
		return
	if run.state != DungeonRun.State.FIGHTING and run.state != DungeonRun.State.BOSS:
		return
	for rp in get_tree().get_nodes_in_group("remote_players"):
		if not rp.dead:
			return
	run.party_wiped()
