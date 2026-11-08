class_name BossArena
extends Node2D
## The ring of fire that seals round a boss fight: once the boss is awake and the player is inside it,
## the monsters and the players can't get in or out (they are stopped by it as by a wall) until the boss is
## dead. Your hireling, pet and allies walk straight through it, so one left outside is never stuck. It reads the boss's own `_aggro`, so every game in a party seals it the same way
## (a follower's copy of the boss reports it too), and a player who dies is back at the waypoint with the
## zone made again, the boss at full life.
## The ring is drawn here and its collision is a row of circles on its own physics layer (LAYER), which the
## players and the monsters collide with (Player, Enemy add it to their masks) and the followers don't.

const LAYER := 2  ## the ring's physics layer (bit 2; walls are bit 1)

static var current: BossArena = null  ## the one sealed now, if any

var boss: Enemy
var player: Player
var radius := 560.0
var sealed := false

var _body: StaticBody2D
var _t := 0.0
var _fade := 0.0
var _opening := false


func _ready() -> void:
	z_index = 4
	add_to_group("boss_arena")


func _process(delta: float) -> void:
	_t += delta
	if _opening:
		_fade = maxf(_fade - delta * 1.6, 0.0)
		queue_redraw()
		if _fade <= 0.0:
			queue_free()
		return
	if not is_instance_valid(boss) or boss._dead:
		_open()
		return
	if not sealed and boss._aggro and is_instance_valid(player) and not player.dead \
			and player.global_position.distance_to(global_position) < radius - 30.0:
		_seal()
	if sealed:
		_fade = minf(_fade + delta * 1.8, 1.0)
		queue_redraw()


func _seal() -> void:
	sealed = true
	current = self
	_body = StaticBody2D.new()
	_body.collision_layer = LAYER
	_body.collision_mask = 0
	add_child(_body)
	var n := int(ceil(TAU * radius / 56.0))
	for i in n:
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 36.0
		cs.shape = c
		cs.position = Vector2.from_angle(TAU * i / n) * radius
		_body.add_child(cs)


func _open() -> void:
	if _opening:
		return
	_opening = true
	if current == self:
		current = null
	if _body != null:
		_body.queue_free()
		_body = null
	if not sealed:
		queue_free()


func _exit_tree() -> void:
	if current == self:
		current = null


func _draw() -> void:
	if _fade <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 128, Color(1.0, 0.35, 0.1, (0.10 + 0.06 * pulse) * _fade), 34.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 128, Color(1.0, 0.5, 0.15, (0.45 + 0.25 * pulse) * _fade), 9.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 128, Color(1.0, 0.85, 0.5, 0.7 * _fade), 3.0)
	# Embers drifting up off the ring
	for i in 36:
		var a := TAU * i / 36.0 + _t * 0.15
		var lift := fmod(_t * 40.0 + i * 17.0, 60.0)
		draw_circle(Vector2.from_angle(a) * radius + Vector2(0, -lift), 3.0 - lift / 30.0, Color(1.0, 0.7, 0.3, 0.6 * _fade * (1.0 - lift / 60.0)))
