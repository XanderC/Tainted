class_name RemotePlayer
extends Interactable
## Another player, seen in your instance (Net): their character as it looks, its name and level
## over its head, gliding to where they are and playing what they play. It has no collision and
## takes no part in the game here; walk up to it and tap the Talk button for its card (invite them
## to your party, and so on: PartyUI.show_card).
## In a party rift the monsters (run by the instance's host, Coop) go for it like for you: what
## hits it is sent to that player's game (take_damage, apply_slow), whose character takes it.

const NAME_COLOR := Color(0.55, 0.85, 1.0)  # light blue, so players stand out from NPCs (gold)

var peer_id := 0
var dead := false  ## their life is at 0 (from their state): monsters leave them be
var rig: RigSprite
var _name: Label
var _target := Vector2.ZERO
var _facing := 1.0
var _anim := "Idle"
var _speed := 1.0
var _oneshot := ""


func setup(id: int, info: Dictionary, state: Dictionary) -> void:
	peer_id = id
	var sh := Node2D.new()
	sh.draw.connect(func(): RigSprite.draw_shadow(sh, 22.0))
	add_child(sh)
	rig = RigSprite.new()
	rig.base_scale = 0.2
	rig.weapon_from_gear = true
	add_child(rig)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 16)
	_name.add_theme_color_override("font_color", NAME_COLOR)
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 6)
	_name.custom_minimum_size = Vector2(200, 0)
	_name.position = Vector2(-100, -128)
	_name.z_index = 5
	add_child(_name)
	add_to_group("remote_players")
	radius = 110.0
	action = func():
		if Net.party_ui != null:
			Net.party_ui.show_card(peer_id)
	apply_looks(info)
	apply_state(state)
	if state.has("p"):
		position = state.p  # appear where they are, not slide in from the corner


## Their looks, gear, name and level.
func apply_looks(info: Dictionary) -> void:
	Appearance.apply(rig, info.get("look", {}))
	var gear: Dictionary = info.get("gear", {})
	for slot in Player.VISIBLE_SLOTS:
		var g = gear.get(slot)
		rig.set_gear(slot, String(g[0]) if g is Array else "", String(g[1]) if g is Array and slot in DyeDB.SLOTS else "")
	var off = gear.get("offhand")
	rig.set_offhand(String(off[0]) if off is Array else "", off is Array and bool(off[1]))
	var cd := ClassLibrary.get_class_def(String(info.get("class", "warrior")))
	_name.text = "%s\nLv %d %s" % [info.get("name", "?"), int(info.get("level", 1)), cd.display_name if cd != null else ""]
	prompt = "👥 %s" % info.get("name", "?")


## Where they are and what they are doing now.
func apply_state(state: Dictionary) -> void:
	if state.has("p"):
		_target = state.p
	_facing = float(state.get("f", _facing))
	dead = float(state.get("h", 1.0)) <= 0.0
	var a := String(state.get("a", "Idle"))
	_speed = float(state.get("s", 1.0))
	if a in ["Idle", "Walking", "Running", "Slashing in The Air"]:
		_anim = a
		_oneshot = ""
	elif a != _oneshot:
		_oneshot = a  # a swing or a leap: once
		rig.play_once(a, _speed)


## A monster hit them: their game takes it (their own armour and so on applies there).
func take_damage(amount: float, _crit := false, _dtype = 0, _ailment := "") -> void:
	if not dead:
		Coop.hurt_player(peer_id, amount)


func apply_slow(seconds: float) -> void:
	Coop.slow_player(peer_id, seconds)


func thorns() -> float:
	return 0.0  # their thorns hit back in their own game


func on_enemy_killed(_pos: Vector2) -> void:
	pass


func _process(delta: float) -> void:
	if position.distance_to(_target) > 400.0:
		position = _target  # too far behind (they took a waypoint, say): jump there
	else:
		position = position.lerp(_target, 1.0 - exp(-12.0 * delta))
	rig.set_facing(_facing)
	rig.play_loop(_anim, _speed)
