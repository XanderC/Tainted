class_name BossTelegraph
extends Node2D
## A warning on the ground for a boss's attack (BossBrain): a circle, a cone or a line that fills in red
## over `t` seconds and is gone when the hit lands. It only shows; the host's game does the hurting.
## The host makes them with warn(), which has the party's games make the same (Coop.host_fx "tele").
##
## Params: s ("circle" | "cone" | "line"), x, y (where it starts), a (its direction, radians), r (circle
## radius, or the length of a cone or line), w (a cone's arc in radians, a line's width), t (seconds), c (colour).

var p := {}
var _t := 0.0
var _dur := 1.0


## Warns here and in the party. `boss` is who it is for (its net id goes with it).
static func warn(boss: Enemy, params: Dictionary) -> void:
	make(boss.get_parent(), params)
	var d := params.duplicate()
	d["id"] = boss.net_id
	Coop.host_fx("tele", d)


## One here only.
static func make(parent: Node, params: Dictionary) -> BossTelegraph:
	var t := BossTelegraph.new()
	t.p = params
	t.position = Vector2(float(params.get("x", 0.0)), float(params.get("y", 0.0)))
	parent.add_child(t)
	return t


func _ready() -> void:
	add_to_group("boss_telegraphs")
	z_index = -1  # under what stands on it
	_dur = clampf(float(p.get("t", 1.0)), 0.1, 6.0)
	rotation = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _dur + 0.12:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / _dur, 0.0, 1.0)
	var col := Color.from_string(String(p.get("c", "ff3a1a")), Color(1.0, 0.23, 0.1))
	var fill := Color(col, 0.10 + 0.32 * k)
	var edge := Color(col.lightened(0.25), 0.55 + 0.4 * k)
	var a := float(p.get("a", 0.0))
	var r := clampf(float(p.get("r", 100.0)), 4.0, 1500.0)
	match String(p.get("s", "circle")):
		"circle":
			draw_circle(Vector2.ZERO, r, fill)
			draw_circle(Vector2.ZERO, r * k, Color(col, 0.16 + 0.2 * k))  # fills in as the hit nears
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, edge, 3.0)
		"cone":
			var arc := clampf(float(p.get("w", 1.0)), 0.05, TAU)
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 17:
				pts.append(Vector2.from_angle(a - arc * 0.5 + arc * i / 16.0) * r)
			draw_colored_polygon(pts, fill)
			var inner := PackedVector2Array([Vector2.ZERO])
			for i in 17:
				inner.append(Vector2.from_angle(a - arc * 0.5 + arc * i / 16.0) * r * k)
			draw_colored_polygon(inner, Color(col, 0.16 + 0.2 * k))
			draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), edge, 3.0)
		"line":
			var w := clampf(float(p.get("w", 60.0)), 4.0, 600.0)
			var dir := Vector2.from_angle(a)
			var side := dir.orthogonal() * w * 0.5
			var far := dir * r
			draw_colored_polygon(PackedVector2Array([-side, side, far + side, far - side]), fill)
			var near := dir * r * k
			draw_colored_polygon(PackedVector2Array([-side, side, near + side, near - side]), Color(col, 0.16 + 0.2 * k))
			draw_polyline(PackedVector2Array([-side, far - side, far + side, side, -side]), edge, 3.0)
