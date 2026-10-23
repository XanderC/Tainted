class_name HirelingArrow
extends Node2D
## A projectile: an arrow (your hireling's, or yours from a bow), a bolt of fire or a thrown knife
## (`style`). Flies straight, and calls `on_hit` for the first enemy it reaches (or, piercing, for
## every enemy along its line, once each). Stops at a maze wall or after `life` seconds. Without
## on_hit it only shows (another player's, drawn in your game: RemotePlayer).

const SPEED := 720.0
const HIT_RADIUS := 30.0
const LIFE := 0.9

var texture: Texture2D
var dir := Vector2.RIGHT
var pierce := false
var maze: MazeMap = null
var color := Color(0.85, 0.75, 0.55)
var on_hit: Callable
var style := "arrow"  ## "arrow", "orb" (a bolt of fire or magic) or "knife"
var speed := SPEED
var life := LIFE

var _t := 0.0
var _hit := {}  # enemies already hit (piercing)


func _ready() -> void:
	z_index = 5
	rotation = dir.angle()
	if texture != null:
		var s := Sprite2D.new()
		s.texture = texture
		s.scale = Vector2.ONE * 0.22
		add_child(s)
	queue_redraw()


func _process(_delta: float) -> void:
	if style == "orb":
		queue_redraw()  # it flickers


func _draw() -> void:
	match style:
		"orb":
			var f := 1.0 + 0.12 * sin(_t * 40.0)
			draw_circle(Vector2(-14, 0), 7.0 * f, Color(color.r, color.g, color.b, 0.25))
			draw_circle(Vector2.ZERO, 11.0 * f, Color(color.r, color.g, color.b, 0.45))
			draw_circle(Vector2.ZERO, 6.5 * f, color.lightened(0.4))
			draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 0.9))
		"knife":
			draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(0, -3), Vector2(-4, 0), Vector2(0, 3)]), Color(0.85, 0.88, 0.92))
			draw_line(Vector2(-4, 0), Vector2(-11, 0), Color(0.35, 0.25, 0.18), 3.0)
			draw_line(Vector2(-12, 0), Vector2(-3, 0), Color(color.r, color.g, color.b, 0.5), 6.0)
		_:
			if texture == null:
				draw_line(Vector2(-18, 0), Vector2(14, 0), Color(0.55, 0.40, 0.25), 3.0)
				draw_line(Vector2(10, -3), Vector2(16, 0), Color(0.8, 0.8, 0.85), 2.0)
				draw_line(Vector2(10, 3), Vector2(16, 0), Color(0.8, 0.8, 0.85), 2.0)
	if pierce:
		draw_line(Vector2(-40, 0), Vector2(-14, 0), Color(color.r, color.g, color.b, 0.6), 5.0)


func _physics_process(delta: float) -> void:
	_t += delta
	global_position += dir * speed * delta
	if _t > life or (maze != null and maze.is_wall(maze.world_to_cell(global_position))):
		queue_free()
		return
	if not on_hit.is_valid():
		return  # only shown
	for e in get_tree().get_nodes_in_group("enemies"):
		if _hit.has(e) or global_position.distance_to(e.global_position + Vector2(0, -16)) > HIT_RADIUS * e.size_mult:
			continue
		_hit[e] = true
		on_hit.call(e)
		if not pierce:
			queue_free()
			return
