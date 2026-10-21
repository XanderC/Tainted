class_name HirelingArrow
extends Node2D
## An arrow your hireling shoots: flies straight, and calls `on_hit` for the first enemy it reaches
## (or, piercing, for every enemy along its line, once each). Stops at a maze wall or after a while.

const SPEED := 720.0
const HIT_RADIUS := 30.0
const LIFE := 0.9

var texture: Texture2D
var dir := Vector2.RIGHT
var pierce := false
var maze: MazeMap = null
var color := Color(0.85, 0.75, 0.55)
var on_hit: Callable

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


func _draw() -> void:
	if texture == null:
		draw_line(Vector2(-18, 0), Vector2(14, 0), Color(0.55, 0.40, 0.25), 3.0)
		draw_line(Vector2(10, -3), Vector2(16, 0), Color(0.8, 0.8, 0.85), 2.0)
		draw_line(Vector2(10, 3), Vector2(16, 0), Color(0.8, 0.8, 0.85), 2.0)
	if pierce:
		draw_line(Vector2(-40, 0), Vector2(-14, 0), Color(color.r, color.g, color.b, 0.6), 5.0)


func _physics_process(delta: float) -> void:
	_t += delta
	global_position += dir * SPEED * delta
	if _t > LIFE or (maze != null and maze.is_wall(maze.world_to_cell(global_position))):
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if _hit.has(e) or global_position.distance_to(e.global_position + Vector2(0, -16)) > HIT_RADIUS * e.size_mult:
			continue
		_hit[e] = true
		if on_hit.is_valid():
			on_hit.call(e)
		if not pierce:
			queue_free()
			return
