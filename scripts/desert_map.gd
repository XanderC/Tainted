class_name DesertMap
extends Node2D
## Scatters desert scenery around the origin. Same seed = same map.
## Art: assets/tiles/desert/ (CraftPix 2D RPG Desert Tileset).
## Props are Sprite2Ds whose origin is their base, so the parent's y-sorting puts
## characters correctly in front of / behind them.

const DIR := "res://assets/tiles/desert/"
const HALF := 3200.0
const SAFE_RADIUS := 320.0

# name: [scale, weight, blocker radius in px (0 = walk-through), base inset fraction]
const PROPS := {
	"tree_1": [0.5, 3, 14, 0.9], "tree_2": [0.5, 3, 12, 0.9], "tree_3": [0.5, 3, 12, 0.9],
	"tree_5": [0.5, 3, 12, 0.9], "tree_6": [0.5, 3, 12, 0.9], "tree_9": [0.5, 2, 16, 0.9],
	"tree_4": [0.5, 1, 8, 0.9], "tree_7": [0.5, 2, 22, 0.9], "tree_8": [0.5, 1, 30, 0.9],
	"tree_10": [0.5, 3, 12, 0.9], "tree_11": [0.5, 2, 10, 0.9], "tree_12": [0.5, 2, 12, 0.9],
	"greenery_1": [0.4, 3, 8, 0.93], "greenery_3": [0.4, 3, 10, 0.93], "greenery_4": [0.4, 3, 10, 0.93],
	"greenery_5": [0.4, 3, 8, 0.93], "greenery_9": [0.4, 2, 12, 0.93],
	"greenery_2": [0.5, 3, 0, 0.9], "greenery_7": [0.5, 2, 0, 0.9], "greenery_8": [0.5, 2, 0, 0.9],
	"greenery_6": [0.5, 6, 0, 0.9], "greenery_10": [0.5, 6, 0, 0.9],
	"stones_1": [0.5, 4, 0, 0.85], "stones_7": [0.5, 4, 0, 0.85], "stones_8": [0.5, 3, 0, 0.85],
	"stones_9": [0.5, 3, 0, 0.85], "stones_5": [0.5, 2, 24, 0.85], "stones_6": [0.5, 1, 30, 0.85],
	"stones_4": [0.5, 1, 30, 0.85],
	"decor_6": [0.5, 1, 0, 0.8],
}

var _rng := RandomNumberGenerator.new()
var _bag: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rng.seed = 1337
	_add_ground()
	_build_bag()
	_place_camp()
	_place_oasis()
	_scatter(900)


func _add_ground() -> void:
	var g := Sprite2D.new()
	g.texture = load(DIR + "bg.png")
	g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	g.region_enabled = true
	g.region_rect = Rect2(0, 0, HALF * 2.0, HALF * 2.0)
	g.scale = Vector2(0.5, 0.5)  # 256px tile drawn at 128px so it doesn't look huge next to the characters
	g.z_index = -100
	add_child(g)


func _build_bag() -> void:
	for n in PROPS:
		for i in PROPS[n][1]:
			_bag.append(n)


func _prop(name: String, pos: Vector2, scale := 0.5, block := 0.0, inset := 0.9) -> Sprite2D:
	var tex: Texture2D = load(DIR + name + ".png")
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * inset)
	s.scale = Vector2(scale, scale)
	s.position = pos
	add_child(s)
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


func _scatter(count: int) -> void:
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < count and tries < count * 6:
		tries += 1
		var pos := Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-HALF, HALF))
		if pos.length() < SAFE_RADIUS or pos.distance_to(Vector2(900, 500)) < 330.0:
			continue
		var ok := true
		for q in placed:
			if q.distance_squared_to(pos) < 70.0 * 70.0:
				ok = false
				break
		if not ok:
			continue
		var n: String = _bag[_rng.randi() % _bag.size()]
		var d: Array = PROPS[n]
		var sc: float = d[0] * _rng.randf_range(0.9, 1.15)
		_prop(n, pos, sc, d[2], d[3])
		placed.append(pos)


func _place_camp() -> void:
	_prop("decor_2", Vector2(-330, -170), 0.45, 40, 0.85)   # tent
	_prop("decor_7", Vector2(-230, -110), 0.5, 0, 0.8)      # campfire
	_prop("decor_8", Vector2(-150, -230), 0.45, 40, 0.8)    # wagon
	_prop("decor_3", Vector2(150, -160), 0.5, 6, 0.9)       # signpost


func _place_oasis() -> void:
	# Kept far enough from the start that it doesn't block the first fights.
	var c := Vector2(900, 500)
	var lake := _prop("lake", c, 0.7, 0, 0.5)
	lake.z_index = -50  # water lies flat on the ground
	_prop("tree_2", c + Vector2(-230, 30), 0.55, 12)
	_prop("tree_3", c + Vector2(240, 10), 0.55, 12)
	_prop("tree_5", c + Vector2(-60, -80), 0.55, 12)
	_prop("building_1", Vector2(-1100, -800), 0.6, 60, 0.95)
	_prop("building_3", Vector2(-880, -760), 0.6, 40, 0.95)
	_prop("decor_1", Vector2(1500, -900), 0.6, 50, 0.85)    # pyramid
