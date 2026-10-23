class_name EnemyArrow
extends Node2D
## An arrow shot by an archer monster: flies straight, hurts who it was shot at (you or your
## hireling) when it reaches them, and stops at a maze wall or after a while.

const SPEED := 560.0
const HIT_RADIUS := 26.0
const LIFE := 1.4

var texture: Texture2D
var dir := Vector2.RIGHT
var damage := 8.0
var element := RuneDef.DamageType.PHYSICAL  ## its archer's
var target: Node2D  ## a Player or a Hireling: anything with `dead` and take_damage()
var maze: MazeMap = null

var _t := 0.0


func _ready() -> void:
	z_index = 5
	rotation = dir.angle()
	if texture != null:
		var s := Sprite2D.new()
		s.texture = texture
		s.scale = Vector2.ONE * 0.22
		add_child(s)
	else:
		queue_redraw()


func _draw() -> void:
	if texture == null:
		draw_line(Vector2(-18, 0), Vector2(14, 0), Color(0.55, 0.40, 0.25), 3.0)


func _physics_process(delta: float) -> void:
	_t += delta
	global_position += dir * SPEED * delta
	if _t > LIFE or (maze != null and maze.is_wall(maze.world_to_cell(global_position))):
		queue_free()
		return
	if is_instance_valid(target) and not target.dead \
			and global_position.distance_to(target.global_position + Vector2(0, -14)) < HIT_RADIUS:
		target.take_damage(damage, element)
		queue_free()
