class_name SceneryMap
extends Node2D
## Base for open scenes laid out by hand (TownMap): a theme's ground (MapTheme) and its pictures
## placed as props, plus random scenery from the theme's "scatter" table. Same seed = same map.
## Props are Sprite2Ds whose origin is their base, so the parent's y-sorting puts
## characters correctly in front of / behind them.

const HALF := 3200.0

var theme := MapTheme.DEFAULT
var _rng := RandomNumberGenerator.new()
var _bag: Array = []


func _add_ground() -> void:
	var g := Sprite2D.new()
	g.texture = load(MapTheme.dir(theme) + "bg.png")
	g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	g.region_enabled = true
	g.region_rect = Rect2(0, 0, HALF * 2.0, HALF * 2.0)
	g.scale = Vector2(0.5, 0.5)  # 256px tile drawn at 128px so it doesn't look huge next to the characters
	g.z_index = -100
	add_child(g)


## The theme's scatter pictures, each as often as its weight.
func _build_bag() -> void:
	var scatter: Dictionary = MapTheme.data(theme).scatter
	for n in scatter:
		for i in scatter[n][1]:
			_bag.append(n)


func _prop(name: String, pos: Vector2, scale := 0.5, block := 0.0, inset := 0.9) -> Sprite2D:
	var tex := MapTheme.load_sprite(theme, name)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * inset)
	s.scale = Vector2(scale, scale)
	s.position = pos
	add_child(s)
	PropFader.attach(self, s)  # see-through with the player behind it
	if block > 0.0:
		var body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = block
		cs.shape = c
		body.add_child(cs)
		s.add_child(body)
		body.scale = Vector2(1.0 / scale, 1.0 / scale)  # keep the blocker size in world pixels
	return s
