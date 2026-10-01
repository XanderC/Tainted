class_name Enemy
extends CharacterBody2D

signal died(pos: Vector2)
signal hp_changed(hp: float, max_hp: float)

const TINT := Color(1.0, 0.86, 0.86)  # slight red so zombies read as hostile next to the player

var target: Player
var max_hp := 30.0
var hp := 30.0
var speed := 110.0
var touch_damage := 8.0
var rig: RigSprite
var is_boss := false
var size_mult := 1.0  # boss = 2.0
var display_name := "Zombie"

var _touch_cd := 0.0
var _stun_t := 0.0
var _dead := false
var _shape: CollisionShape2D
var _slam_cd := 4.0
var _slam_t := 0.0  # > 0 while winding up the ground slam
var _tint := TINT

const SLAM_WINDUP := 0.9
const SLAM_RADIUS := 150.0


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0 * size_mult
	_shape.shape = circle
	_shape.position = Vector2(0, -6)
	add_child(_shape)

	rig = RigSprite.new()
	rig.base_scale = 0.18 * size_mult
	rig.frame_skip = 2  # 30 fps is plenty for a crowd
	if is_boss:
		_tint = Color(0.75, 0.55, 1.0)
	rig.modulate = _tint
	add_child(rig)
	rig.play_loop("Walking")
	rig.randomize_phase()  # so a group doesn't march in lockstep


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _slam_t > 0.0:
		_slam_t -= delta
		velocity = Vector2.ZERO
		queue_redraw()
		if _slam_t <= 0.0:
			_do_slam()
		return
	if _stun_t > 0.0:
		_stun_t -= delta
		if _stun_t <= 0.0:
			rig.modulate = _tint
		velocity = Vector2.ZERO
		rig.play_loop("Idle Blinking")
		return
	if not is_instance_valid(target) or target.dead:
		velocity = Vector2.ZERO
		rig.play_loop("Idle")
		return
	var to_player := target.global_position - global_position
	velocity = to_player.normalized() * speed
	move_and_slide()
	if not rig.is_busy():
		rig.set_facing(to_player.x)
	rig.play_loop("Walking")
	_touch_cd -= delta
	if is_boss:
		_slam_cd -= delta
		if _slam_cd <= 0.0 and to_player.length() < SLAM_RADIUS * 1.6:
			_slam_cd = 5.0
			_slam_t = SLAM_WINDUP
			rig.play_once("Slashing", 0.9)
			return
	if to_player.length() < 46.0 * size_mult and _touch_cd <= 0.0:
		target.take_damage(touch_damage)
		_touch_cd = 1.0
		rig.play_once("Slashing", 1.4)


func stun(seconds: float) -> void:
	if _dead or is_boss:  # bosses can't be stunlocked
		return
	_stun_t = maxf(_stun_t, seconds)
	rig.modulate = Color(1.0, 1.0, 0.5)


func take_damage(amount: float, crit: bool = false) -> void:
	if _dead:
		return
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(amount, crit)
	queue_redraw()
	if hp <= 0.0:
		_die()
	elif not is_boss and _stun_t <= 0.0 and not rig.is_busy():
		rig.play_once("Hurt", 1.6)


func _die() -> void:
	_dead = true
	_slam_t = 0.0
	remove_from_group("enemies")  # no longer targetable or hittable
	_shape.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	died.emit(global_position)  # loot drops right away
	rig.modulate = _tint
	rig.play_once("Dying", 1.0, true)
	queue_redraw()
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(rig, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)


func _do_slam() -> void:
	queue_redraw()
	if is_instance_valid(target) and not target.dead \
			and target.global_position.distance_to(global_position) < SLAM_RADIUS:
		target.take_damage(touch_damage * 2.0)
	var ring := Node2D.new()
	get_parent().add_child(ring)
	ring.global_position = global_position
	ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, SLAM_RADIUS, 0.0, TAU, 48, Color(1, 0.5, 0.2, 0.9), 6.0))
	ring.queue_redraw()
	var t := ring.create_tween()
	t.tween_property(ring, "modulate:a", 0.0, 0.4)
	t.tween_callback(ring.queue_free)


func _spawn_number(amount: float, crit: bool) -> void:
	var l := Label.new()
	l.text = str(int(amount)) + ("!" if crit else "")
	l.modulate = Color(1.0, 0.85, 0.2) if crit else Color.WHITE
	l.z_index = 10
	get_parent().add_child(l)
	l.position = global_position + Vector2(-10, -118 * size_mult)
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - 40.0, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _draw() -> void:
	RigSprite.draw_shadow(self, 24.0 * size_mult)
	if _slam_t > 0.0:
		var k := 1.0 - _slam_t / SLAM_WINDUP
		draw_circle(Vector2.ZERO, SLAM_RADIUS, Color(1, 0.2, 0.1, 0.12))
		draw_circle(Vector2.ZERO, SLAM_RADIUS * k, Color(1, 0.2, 0.1, 0.28))
		draw_arc(Vector2.ZERO, SLAM_RADIUS, 0.0, TAU, 48, Color(1, 0.3, 0.1, 0.8), 3.0)
	if _dead or is_boss:  # the boss uses the big bar in the HUD
		return
	draw_rect(Rect2(-18, -112, 36, 5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-18, -112, 36.0 * clampf(hp / max_hp, 0.0, 1.0), 5), Color(0.9, 0.15, 0.15))
