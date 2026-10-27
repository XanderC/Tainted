class_name PropFader
extends Node
## Makes big scenery (a tree, a house) see-through while the player stands behind it, so they are
## never lost: a prop is a Sprite2D whose origin is its base, so the player is behind it when they are
## above that line and inside its picture. Small props never hide anyone and aren't faded. A map
## registers its props with PropFader.attach (SceneryMap, MazeMap); anything else hidden behind a big
## prop (a passage, a chest) gets the same treatment for free.

const MIN_SIZE := Vector2(60.0, 90.0)  # a prop at least this big, as drawn
const SEE_THROUGH := 0.35  # its opacity with the player behind it
const SPEED := 5.0  # opacity per second
const NEAR := 700.0  # only props this near the player are looked at

var sprites: Array[Sprite2D] = []


## Registers `s` (a prop of `map`) if it is big enough to hide someone.
static func attach(map: Node, s: Sprite2D) -> void:
	if s.texture == null:
		return
	var size := s.texture.get_size() * s.scale.abs()
	if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y:
		return
	var f := map.get_node_or_null("PropFader") as PropFader
	if f == null:
		f = PropFader.new()
		f.name = "PropFader"
		map.add_child(f)
	f.sprites.append(s)


func _process(delta: float) -> void:
	var p := GameState.player
	if not is_instance_valid(p):
		return
	var at: Vector2 = p.global_position
	for s in sprites:
		if not is_instance_valid(s) or not s.is_inside_tree():
			continue
		var base := s.global_position
		if absf(base.x - at.x) > NEAR or absf(base.y - at.y) > NEAR:
			continue
		var target := SEE_THROUGH if covers(s, at) else 1.0
		if not is_equal_approx(s.modulate.a, target):
			s.modulate.a = move_toward(s.modulate.a, target, delta * SPEED)


## True when a player standing at `at` is behind prop `s`: above its base and inside its picture.
static func covers(s: Sprite2D, at: Vector2) -> bool:
	var sc := s.global_scale.abs()
	var top_left := s.global_position + s.offset * sc
	var rect := Rect2(top_left, s.texture.get_size() * sc)
	return at.y < s.global_position.y - 2.0 and rect.has_point(at + Vector2(0.0, -30.0))
