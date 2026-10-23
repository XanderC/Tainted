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
# Their skills' looks (show_fx), drawn as their game draws them (Player.draw_swing and so on)
var _swing_t := 0.0
var _swing_dir := Vector2.RIGHT
var _swing_arc := 120.0
var _swing_radius := 100.0
var _swing_color := Color.WHITE
var _ring_t := 0.0
var _ring_radius := 100.0
var _ring_color := Color.WHITE
var _spin_t := 0.0
var revive_frac := 0.0  ## you are reviving them: how far along (PartyDeath), drawn as a ring
var _allies := {}  # "h" / "a0".. -> RemoteAlly: their hireling and Ancients, in your world beside them
var _hl := {}      # their hireling's looks (Net.my_info "hl")


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
	var hl: Dictionary = info.get("hl", {})
	if hl != _hl:
		_hl = hl
		if is_instance_valid(_allies.get("h")):
			_allies["h"].queue_free()  # dressed again by the next state
		_allies.erase("h")


## Where they are and what they are doing now.
func apply_state(state: Dictionary) -> void:
	if state.has("p"):
		_target = state.p
	_facing = float(state.get("f", _facing))
	dead = float(state.get("h", 1.0)) <= 0.0
	var a := String(state.get("a", "Idle"))
	_speed = float(state.get("s", 1.0))
	if a in ["Idle", "Walking", "Running", "Slashing in The Air"]:
		if _oneshot == "Dying":
			rig.stop_once()  # back on their feet
		_anim = a
		_oneshot = ""
	elif a != _oneshot:
		_oneshot = a  # a swing or a leap: once (a fall: they stay down)
		rig.play_once(a, _speed, a == "Dying")
	_sync_allies(state.get("al", []))


## Their hireling and Ancients as they are now: new ones appear, gone ones (dismissed, fallen,
## their time up) go.
func _sync_allies(al: Array) -> void:
	var seen := {}
	for e in al:
		var k := String(e[0])
		seen[k] = true
		var ally = _allies.get(k)  # untyped: it may have been freed
		if not is_instance_valid(ally):
			if get_parent() == null:
				continue
			ally = RemoteAlly.new()
			get_parent().add_child(ally)
			ally.setup(k, _hl)
			ally.position = e[1]
			_allies[k] = ally
		ally.apply(e)
	for k in _allies.keys():
		if not seen.has(k):
			if is_instance_valid(_allies[k]):
				_allies[k].queue_free()
			_allies.erase(k)


func _exit_tree() -> void:
	for k in _allies:
		if is_instance_valid(_allies[k]):
			_allies[k].queue_free()
	_allies.clear()


## A monster hit them: their game takes it (their own armour and so on applies there).
func take_damage(amount: float, _crit := false, _dtype = 0, _ailment := "") -> void:
	if not dead:
		Coop.hurt_player(peer_id, amount)


func apply_slow(seconds: float) -> void:
	Coop.slow_player(peer_id, seconds)


## One of their skills' looks (Coop.player_fx from their Player): a swing, a ring, Whirlwind's spin,
## Earthquake's broken ground, a battle standard.
func show_fx(d: Array) -> void:
	if d.is_empty():
		return
	match [String(d[0]), d.size()]:
		["swing", 6]:
			_swing_dir = Vector2.from_angle(float(d[1]))
			_swing_arc = clampf(float(d[2]), 0.0, 360.0)
			_swing_radius = clampf(float(d[3]), 0.0, 600.0)
			_swing_color = Color.from_string(String(d[4]), Color.WHITE)
			_swing_t = clampf(float(d[5]), 0.0, 2.0)
		["ring", 4]:
			_ring_radius = clampf(float(d[1]), 0.0, 600.0)
			_ring_color = Color.from_string(String(d[2]), Color.WHITE)
			_ring_t = clampf(float(d[3]), 0.0, 2.0)
		["spin", 4]:
			_ring_radius = clampf(float(d[1]), 0.0, 600.0)
			_ring_color = Color.from_string(String(d[2]), Color.WHITE)
			_spin_t = clampf(float(d[3]), 0.0, 1.0)
			SpellFx.attach(self, "typhoon", _spin_t + 0.1, _ring_radius / 125.0, 10.0, false, 0.55)
		["sfx", 6]:  # a spell effect where it happened (Player._sfx)
			if SpellFx.TUNE.has(String(d[1])) and get_parent() != null:
				SpellFx.spawn(get_parent(), String(d[1]), Vector2(float(d[2]), float(d[3])), clampf(float(d[4]), 0.1, 4.0), bool(d[5]))
		["sfx_on", 7]:  # one kept on them a while (Player._sfx_on)
			if SpellFx.TUNE.has(String(d[1])):
				SpellFx.attach(self, String(d[1]), clampf(float(d[2]), 0.0, 30.0), clampf(float(d[3]), 0.1, 4.0),
					clampf(float(d[4]), 0.0, 200.0), bool(d[5]), clampf(float(d[6]), 0.0, 1.0))
		["ground", 6], ["banner", 6]:
			_ground(String(d[0]) == "banner", Vector2(float(d[1]), float(d[2])), clampf(float(d[3]), 0.0, 600.0),
				Color.from_string(String(d[4]), Color.WHITE), clampf(float(d[5]), 0.0, 30.0))
	queue_redraw()


## Earthquake's broken ground or a battle standard, where they left it, for as long as it lasts.
func _ground(banner: bool, at: Vector2, radius: float, col: Color, secs: float) -> void:
	if get_parent() == null:
		return
	var n := Node2D.new()
	n.z_index = -1
	get_parent().add_child(n)
	n.global_position = at
	n.draw.connect(func():
		if banner:
			n.draw_circle(Vector2.ZERO, 16.0, col)
			n.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.4), 2.5)
		else:
			n.draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, 0.15))
			n.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(col.r, col.g, col.b, 0.6), 3.0))
	n.queue_redraw()
	var t := n.create_tween()
	t.tween_interval(secs)
	t.tween_property(n, "modulate:a", 0.0, 0.4)
	t.tween_callback(n.queue_free)


func _draw() -> void:
	if _swing_t > 0.0:
		Player.draw_swing(self, _swing_dir, _swing_arc, _swing_radius, _swing_color, _swing_t / Player.SWING_TIME)
	if _ring_t > 0.0:
		Player.draw_ring(self, _ring_radius, _ring_color, _ring_t / (Player.SWING_TIME * 2.5))
	if _spin_t > 0.0:
		Player.draw_spin(self, _ring_color)
	if revive_frac > 0.0:
		draw_arc(Vector2(0, -20), 46.0, 0.0, TAU, 48, Color(0, 0, 0, 0.5), 7.0)
		draw_arc(Vector2(0, -20), 46.0, -PI / 2.0, -PI / 2.0 + TAU * revive_frac, 48, Color(0.55, 1.0, 0.6), 5.0)


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
	if _swing_t > 0.0 or _ring_t > 0.0 or _spin_t > 0.0 or revive_frac > 0.0:
		_swing_t = maxf(_swing_t - delta, 0.0)
		_ring_t = maxf(_ring_t - delta, 0.0)
		_spin_t = maxf(_spin_t - delta, 0.0)
		queue_redraw()
