class_name TownMap
extends DesertMap
## Ashfall Outpost: the hub. Buildings, camp dressing and a ring of scenery, with invisible walls.
## Reuses DesertMap's prop helpers and the CraftPix desert art.

const BOUNDS := Rect2(-1000, -720, 2000, 1420)   # walkable area (world px)
const CAM_LIMIT := Rect2(-1180, -900, 2360, 1800)

var keepouts: Array[Vector3] = []  # x, y, radius: no random props inside these


func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rng.seed = 424242
	_add_ground()
	_build_bag()
	_layout()
	_scatter_town()
	_add_walls()


func _layout() -> void:
	# Plaza and camp
	_prop("decor_7", Vector2(0, 60), 0.6, 0, 0.8)           # central campfire
	_prop("decor_3", Vector2(110, 150), 0.5, 6)              # signpost
	_prop("decor_6", Vector2(-120, 200), 0.5, 0, 0.8)        # skull
	# Stash keeper: the big building at the north
	_prop("building_1", Vector2(0, -330), 0.55, 70, 0.95)
	_prop("building_4", Vector2(340, -330), 0.5, 40, 0.95)
	# Blacksmith: wide building on the west, forge fire and rock pile
	_prop("building_2", Vector2(-560, -270), 0.6, 80, 0.95)
	_prop("decor_7", Vector2(-420, -200), 0.45, 0, 0.8)
	_prop("stones_4", Vector2(-700, -170), 0.5, 26, 0.85)
	_prop("decor_4", Vector2(-640, -150), 0.5, 0, 0.8)
	# Merchant: building on the east, tent and wagon
	_prop("building_5", Vector2(580, -240), 0.55, 50, 0.95)
	_prop("decor_8", Vector2(760, -120), 0.45, 40, 0.8)
	_prop("decor_2", Vector2(450, -130), 0.42, 34, 0.85)
	# Dungeon gate area
	_prop("decor_1", Vector2(820, 120), 0.55, 50, 0.85)      # pyramid
	# Dressing
	_prop("building_3", Vector2(-840, -20), 0.55, 40, 0.95)
	var lake := _prop("lake", Vector2(-700, 420), 0.7, 0, 0.5)
	lake.z_index = -50
	_prop("tree_2", Vector2(-900, 400), 0.55, 12)
	_prop("tree_3", Vector2(-560, 400), 0.55, 12)
	_prop("tree_5", Vector2(-780, 340), 0.55, 12)
	_prop("tree_9", Vector2(-480, 470), 0.55, 16)
	for spot in [Vector2(0, 60), Vector2(0, -280), Vector2(-560, -200), Vector2(580, -190), Vector2(820, 180),
			Vector2(-700, 420), Vector2(-420, -200), Vector2(0, 380)]:
		keepouts.append(Vector3(spot.x, spot.y, 170.0))
	for b in [Vector2(-560, -270), Vector2(580, -240), Vector2(0, -330), Vector2(340, -330), Vector2(-840, -20)]:
		keepouts.append(Vector3(b.x, b.y, 230.0))


func _scatter_town() -> void:
	var placed: Array[Vector2] = []
	var tries := 0
	var target := 520
	while placed.size() < target and tries < target * 8:
		tries += 1
		var pos := Vector2(_rng.randf_range(CAM_LIMIT.position.x, CAM_LIMIT.end.x),
			_rng.randf_range(CAM_LIMIT.position.y, CAM_LIMIT.end.y))
		var inside := BOUNDS.grow(-30).has_point(pos)
		# Dense outside the walls; only sparse, small things inside.
		if inside and _rng.randf() > 0.012:
			continue
		if inside:
			var blocked := false
			for k in keepouts:
				if pos.distance_to(Vector2(k.x, k.y)) < k.z:
					blocked = true
					break
			if blocked or pos.distance_to(Vector2(0, 360)) < 160.0:
				continue
		var ok := true
		for q in placed:
			if q.distance_squared_to(pos) < 75.0 * 75.0:
				ok = false
				break
		if not ok:
			continue
		var n: String = _bag[_rng.randi() % _bag.size()]
		if inside and (n.begins_with("tree_") or n == "stones_6" or n == "stones_4"):
			continue  # keep the town floor open; only small scenery inside the walls
		var d: Array = PROPS[n]
		_prop(n, pos, d[0] * _rng.randf_range(0.9, 1.15), d[2] if not inside else 0.0, d[3])
		placed.append(pos)


func _add_walls() -> void:
	var t := 60.0
	var r := BOUNDS
	var rects := [
		Rect2(r.position.x - t, r.position.y - t, r.size.x + 2 * t, t),
		Rect2(r.position.x - t, r.end.y, r.size.x + 2 * t, t),
		Rect2(r.position.x - t, r.position.y, t, r.size.y),
		Rect2(r.end.x, r.position.y, t, r.size.y),
	]
	for rc in rects:
		var body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rc.size
		cs.shape = shape
		body.position = rc.get_center()
		body.add_child(cs)
		add_child(body)
