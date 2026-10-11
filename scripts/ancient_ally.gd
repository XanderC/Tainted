class_name AncientAlly
extends CharacterBody2D
## A barbarian spirit summoned by Call of the Ancients. Fights at the player's side for `lifetime`
## seconds, going after enemies near the player (staying by the player otherwise). Each Ancient
## has his own fighting style (`style`):
##   "whirlwind" (Talic)   - spins through enemies, hitting everything around him several times a second
##   "frenzy"    (Korlic)  - leaps onto far enemies with a landing slam, then attacks faster and faster
##   "upheaval"  (Madawc)  - heavy blows, and every few seconds tears up the ground in front: big hit + stun
## `damage` is his base hit; each style scales it. Kills count like the player's own.

const SPEED := 250.0
const MELEE_RANGE := 70.0
const LEASH := 520.0  ## only goes after enemies this close to the player
const GHOST := Color(0.65, 0.88, 1.0, 0.82)

# Talic: Whirlwind
const WW_RADIUS := 135.0
const WW_TICK := 0.25
const WW_DAMAGE := 0.40        # x damage per tick to everything around him
const WW_SPEED := 150.0
# Korlic: Leap + Frenzy
const LEAP_MIN := 220.0
const LEAP_CD := 4.0
const LEAP_RADIUS := 120.0
const LEAP_DAMAGE := 1.5
const FRENZY_CD := 0.85        # first swing; each stack makes the next 15% faster (max 5)
const FRENZY_MAX := 5
# Madawc: Upheaval
const UPHEAVAL_CD := 4.0
const UPHEAVAL_WINDUP := 0.45
const UPHEAVAL_RADIUS := 200.0
const UPHEAVAL_ARC := 140.0
const UPHEAVAL_DAMAGE := 2.2
const UPHEAVAL_STUN := 1.0
const HEAVY_CD := 1.1

var owner_player: Player
var ancient_name := "Ancient"
var style := "whirlwind"
var damage := 10.0
var lifetime := 15.0
var weapon_id := "battle_axe"
var follow_offset := Vector2.ZERO

var rig: RigSprite
var _cd := 0.0
var _facing := Vector2.RIGHT
var _leaving := false
var _life0 := 1.0
var _spin := false         # Talic is whirling
var _frenzy := 0           # Korlic's stacks
var _frenzy_t := 0.0
var _leap_cd := 0.0  # Korlic can open with a leap
var _leaping := false
var _upheaval_cd := 1.5
var _windup := 0.0         # Madawc winding up
var _quake_t := 0.0        # Madawc's slam effect
var _quake_dir := Vector2.RIGHT


func _ready() -> void:
	_life0 = maxf(lifetime, 0.1)
	# Walls stop it, but nothing bumps into it (it never blocks the player or enemies)
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 14.0
	shape.shape = c
	shape.position = Vector2(0, -6)
	add_child(shape)

	rig = RigSprite.new()
	rig.base_scale = 0.21
	rig.weapon_from_gear = true
	rig.modulate = GHOST
	add_child(rig)
	rig.set_gear("weapon", weapon_id)
	rig.set_gear("helmet", "iron_helm")
	rig.set_gear("chest", "chain_mail")
	rig.play_loop("Idle")
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _physics_process(delta: float) -> void:
	if _leaving or _leaping:
		return
	lifetime -= delta
	if lifetime <= 0.0 or not is_instance_valid(owner_player) or owner_player.dead:
		_leave()
		return
	_cd = maxf(_cd - delta, 0.0)
	_leap_cd = maxf(_leap_cd - delta, 0.0)
	_upheaval_cd = maxf(_upheaval_cd - delta, 0.0)
	_quake_t = maxf(_quake_t - delta, 0.0)
	_frenzy_t -= delta
	if _frenzy_t <= 0.0:
		_frenzy = 0
	queue_redraw()

	# Madawc mid-windup: stand still, then split the ground
	if _windup > 0.0:
		_windup -= delta
		velocity = Vector2.ZERO
		if _windup <= 0.0:
			_upheaval()
		return

	var foe := _pick_target()
	_spin = false
	if foe == null:
		_follow_player()
		return
	var dist := global_position.distance_to(foe.global_position)
	match style:
		"whirlwind": _talic(foe, dist, delta)
		"frenzy": _korlic(foe, dist)
		"upheaval": _madawc(foe, dist)


# ---------- the three Ancients ----------

## Talic: walks into the pack while spinning, hitting everything around him.
func _talic(foe: Enemy, dist: float, _delta: float) -> void:
	if dist > WW_RADIUS * 1.4:
		_walk_to(foe.global_position, SPEED)
		return
	_spin = true
	_walk_to(foe.global_position, WW_SPEED)
	rig.play_loop("Slashing in The Air", 1.6)
	if _cd <= 0.0:
		_cd = WW_TICK
		_hit_circle(WW_RADIUS, damage * WW_DAMAGE)


## Korlic: leaps onto enemies that are far away, then frenzies (each swing faster).
func _korlic(foe: Enemy, dist: float) -> void:
	if dist > LEAP_MIN and _leap_cd <= 0.0:
		_leap(foe.global_position)
		return
	if dist > MELEE_RANGE:
		_walk_to(foe.global_position, SPEED)
		return
	_face(foe.global_position)
	velocity = Vector2.ZERO
	if _cd <= 0.0:
		_cd = FRENZY_CD / (1.0 + 0.15 * _frenzy)
		_frenzy = mini(_frenzy + 1, FRENZY_MAX)
		_frenzy_t = 2.0
		rig.play_once("Slashing", 1.4 + 0.25 * _frenzy)
		_hit_arc(115.0, 150.0, damage)
	elif not rig.is_busy():
		rig.play_loop("Idle")


## Madawc: heavy swings, and an Upheaval every few seconds that hits a wide area and stuns.
func _madawc(foe: Enemy, dist: float) -> void:
	if dist > MELEE_RANGE * 1.6:
		_walk_to(foe.global_position, SPEED)
		return
	_face(foe.global_position)
	velocity = Vector2.ZERO
	if _upheaval_cd <= 0.0:
		_upheaval_cd = UPHEAVAL_CD
		_windup = UPHEAVAL_WINDUP
		_quake_dir = _facing
		rig.play_once("Slashing in The Air", 0.8)
		return
	if _cd <= 0.0:
		_cd = HEAVY_CD
		rig.play_once("Slashing", 1.1)
		_hit_arc(120.0, 130.0, damage * 1.2)
	elif not rig.is_busy():
		rig.play_loop("Idle")


func _leap(to: Vector2) -> void:
	_leaping = true
	_leap_cd = LEAP_CD
	var land := to - (to - global_position).normalized() * 40.0
	var maze: MazeMap = _maze()
	if maze != null and maze.is_wall(maze.world_to_cell(land)):
		land = to
	_face(to)
	rig.play_once("Slashing in The Air", 1.0)
	var t := create_tween()
	t.tween_property(self, "global_position", land, 0.4).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(rig, "position:y", -70.0, 0.2).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(rig, "position:y", 0.0, 0.2).set_ease(Tween.EASE_IN).set_delay(0.2)
	t.tween_callback(func():
		_leaping = false
		_hit_circle(LEAP_RADIUS, damage * LEAP_DAMAGE)
		_quake_t = 0.3
		_quake_dir = Vector2.ZERO)


func _upheaval() -> void:
	_quake_t = 0.45
	var half := deg_to_rad(UPHEAVAL_ARC) * 0.5
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.global_position - global_position
		if to.length() < UPHEAVAL_RADIUS and absf(_quake_dir.angle_to(to)) <= half:
			_strike(e, damage * UPHEAVAL_DAMAGE)
			e.stun(UPHEAVAL_STUN)


# ---------- helpers ----------

func _maze() -> MazeMap:
	var scene := get_tree().current_scene
	return scene.get("maze") if scene != null else null


func _pick_target() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(owner_player.global_position) > LEASH:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _follow_player() -> void:
	var goal := owner_player.global_position + follow_offset
	if global_position.distance_to(goal) < 40.0:
		velocity = Vector2.ZERO
		rig.play_loop("Idle")
		return
	_walk_to(goal, SPEED)


## Walk towards `goal`, around maze walls when in a rift maze.
func _walk_to(goal: Vector2, spd: float) -> void:
	var maze := _maze()
	var step := maze.path_next(global_position, goal) if maze != null else goal
	var move := step - global_position
	velocity = move.normalized() * spd
	move_and_slide()
	if move.length() > 2.0:
		_facing = move.normalized()
		rig.set_facing(_facing.x)
	if not _spin:
		rig.play_loop("Running", 1.2)


func _face(at: Vector2) -> void:
	var d := at - global_position
	if d.length() > 1.0:
		_facing = d.normalized()
		rig.set_facing(_facing.x)


func _hit_circle(radius: float, amount: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(global_position) < radius:
			_strike(e, amount)


func _hit_arc(radius: float, arc_deg: float, amount: float) -> void:
	var half := deg_to_rad(arc_deg) * 0.5
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.global_position - global_position
		if to.length() < radius and absf(_facing.angle_to(to)) <= half:
			_strike(e, amount)


func _strike(e: Enemy, amount: float) -> void:
	var crit := randf() < owner_player.stats.get_stat("crit_chance")
	e.take_damage(amount * (2.0 if crit else 1.0), crit)


func _leave() -> void:
	_leaving = true
	velocity = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(queue_free)


func _draw() -> void:
	RigSprite.draw_shadow(self, 22.0)
	draw_arc(Vector2(0, 2), 26.0, 0.0, TAU, 32, Color(0.6, 0.85, 1.0, 0.6), 3.0)
	# Talic's cyclone
	if _spin:
		var a := Time.get_ticks_msec() * 0.012
		for i in 3:
			var s := a + i * TAU / 3.0
			draw_arc(Vector2(0, -20), WW_RADIUS * 0.8, s, s + 1.0, 14, Color(0.75, 0.92, 1.0, 0.7), 3.0)
	# Korlic's frenzy pips
	for i in _frenzy:
		draw_circle(Vector2(-12 + i * 6, -100), 2.5, Color(1.0, 0.75, 0.3))
	# Madawc's windup and the torn-up ground (also Korlic's landing)
	if _windup > 0.0:
		var k := 1.0 - _windup / UPHEAVAL_WINDUP
		_draw_cone(UPHEAVAL_RADIUS * k, Color(0.9, 0.6, 0.3, 0.25))
	if _quake_t > 0.0:
		var col := Color(0.95, 0.65, 0.3, _quake_t * 1.6)
		if _quake_dir == Vector2.ZERO:
			draw_arc(Vector2.ZERO, LEAP_RADIUS, 0.0, TAU, 40, col, 5.0)
		else:
			_draw_cone(UPHEAVAL_RADIUS, col)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-60, -122), ancient_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color.BLACK)
	draw_string(font, Vector2(-60, -122), ancient_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.7, 0.9, 1.0))
	draw_rect(Rect2(-20, -112, 40, 4), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-20, -112, 40.0 * clampf(lifetime / _life0, 0.0, 1.0), 4), Color(0.6, 0.85, 1.0))


func _draw_cone(radius: float, col: Color) -> void:
	var half := deg_to_rad(UPHEAVAL_ARC) * 0.5
	var start := _quake_dir.angle() - half
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 13:
		pts.append(Vector2.from_angle(start + half * 2.0 * i / 12.0) * radius)
	draw_colored_polygon(pts, col)
