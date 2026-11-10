class_name Breakable
extends Node2D
## A barrel, crate or urn standing in a zone (Breakables places them): the player's skills break it, and it
## may spill a little loot. It is in the "breakables" group, not "enemies": the monsters, the minimap, the quests
## and the hirelings never see it, only what the player swings, shoots or casts does (Player._hit_area, a dash,
## a player's arrow). It looks like an Enemy to those: take_damage, hp, max_hp, _dead.
## Its hit points count hits, not damage: one hit for an urn, two for a barrel or a crate.

signal broken(at: Vector2)  ## it broke (the zone rolls what it held)

const KINDS := ["barrel", "crate", "urn"]
const HIT_POINTS := {"barrel": 2.0, "crate": 2.0, "urn": 1.0}
const BURST_TIME := 0.55

var kind := "barrel"
var hp := 2.0
var max_hp := 2.0
var _dead := false
var _wobble := 0.0
var _burst := 0.0
var _chunks: Array = []  # [direction, speed, size, colour index]


func _ready() -> void:
	add_to_group("breakables")
	max_hp = float(HIT_POINTS.get(kind, 1.0))
	hp = max_hp
	set_process(false)  # (a hundred of them stand about: only a wobbling or bursting one needs a frame)


func _process(delta: float) -> void:
	if _dead:
		_burst += delta
		if _burst >= BURST_TIME:
			queue_free()
	elif _wobble > 0.0:
		_wobble = maxf(_wobble - delta, 0.0)
		if _wobble == 0.0:
			set_process(false)
	queue_redraw()


## One hit (what is passed is what an Enemy takes: it does not matter here).
func take_damage(_amount := 0.0, _crit := false, _dtype := 0, _ailment := "") -> void:
	if _dead:
		return
	hp -= 1.0
	set_process(true)
	if hp > 0.0:
		_wobble = 0.25
		queue_redraw()
		return
	_dead = true
	remove_from_group("breakables")
	for i in 7:
		_chunks.append([Vector2.from_angle(randf() * TAU), randf_range(50.0, 120.0), randf_range(3.0, 7.0), randi() % 2])
	broken.emit(global_position)
	queue_redraw()


func _colors() -> Array[Color]:
	match kind:
		"crate":
			return [Color(0.55, 0.38, 0.19), Color(0.36, 0.24, 0.11)]
		"urn":
			return [Color(0.66, 0.43, 0.30), Color(0.40, 0.24, 0.16)]
	return [Color(0.50, 0.32, 0.16), Color(0.30, 0.19, 0.10)]


func _draw() -> void:
	var cols := _colors()
	if _dead:  # it bursts into pieces that fly out and fade
		var f := clampf(_burst / BURST_TIME, 0.0, 1.0)
		for c in _chunks:
			var at: Vector2 = Vector2(0, -14) + c[0] * float(c[1]) * f + Vector2(0, 40.0 * f * f)
			var col: Color = cols[int(c[3])]
			col.a = 1.0 - f
			draw_rect(Rect2(at - Vector2(c[2], c[2]) * 0.5, Vector2(c[2], c[2])), col)
		return
	var shake := sin(_wobble * 60.0) * 3.0 * (_wobble / 0.25) if _wobble > 0.0 else 0.0
	draw_set_transform(Vector2(shake, 0.0))
	draw_colored_polygon(_shadow(), Color(0, 0, 0, 0.28))
	var base: Color = cols[0]
	var dark: Color = cols[1]
	match kind:
		"crate":
			draw_rect(Rect2(-17, -32, 34, 32), base)
			draw_rect(Rect2(-17, -32, 34, 32), dark, false, 2.5)
			draw_line(Vector2(-17, -32), Vector2(17, 0), dark, 2.5)
			draw_line(Vector2(17, -32), Vector2(-17, 0), dark, 2.5)
			draw_line(Vector2(-17, -16), Vector2(17, -16), dark, 1.5)
		"urn":
			var body := PackedVector2Array([Vector2(-7, -36), Vector2(7, -36), Vector2(13, -24), Vector2(15, -12),
				Vector2(9, 0), Vector2(-9, 0), Vector2(-15, -12), Vector2(-13, -24)])
			draw_colored_polygon(body, base)
			draw_polyline(body + PackedVector2Array([body[0]]), dark, 2.5)
			draw_line(Vector2(-14, -20), Vector2(14, -20), dark, 2.5)
			draw_line(Vector2(-12, -9), Vector2(12, -9), dark.lightened(0.15), 2.0)
			draw_rect(Rect2(-8, -40, 16, 5), dark)
		_:  # a barrel: a bulging body between two iron hoops
			var body := PackedVector2Array([Vector2(-12, -36), Vector2(12, -36), Vector2(16, -22), Vector2(16, -10),
				Vector2(12, 0), Vector2(-12, 0), Vector2(-16, -10), Vector2(-16, -22)])
			draw_colored_polygon(body, base)
			draw_polyline(body + PackedVector2Array([body[0]]), dark, 2.5)
			for y in [-28.0, -8.0]:
				draw_line(Vector2(-15, y), Vector2(15, y), Color(0.32, 0.32, 0.36), 3.0)
			for x in [-6.0, 0.0, 6.0]:
				draw_line(Vector2(x, -35), Vector2(x, -1), dark.lightened(0.1), 1.0)
	draw_set_transform(Vector2.ZERO)


func _shadow() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(Vector2(cos(a) * 20.0, sin(a) * 8.0))
	return pts
