class_name MiniDungeon
extends Node
## What happens inside one of the mini-dungeons (MiniDungeons, ActDB "mini_*"; a child of its Zone). The map names the spots with
## "marker" objects:
##   cellar    - a mimic chest ("chest") on a hoard: open it and it bites; the mimic's hoard is its drop
##   bonepit   - the "pit" in the middle: step into it and portcullises slam over each "gate", shutting you in with an elite
##               Skeleton Champion; kill it and they rise
##   sanctum   - an abandoned crafting "bench": one free reroll (HermitBench)
##   fissure   - black but for a pool of light round you; a Tainted Chest ("chest") bound to three elite "guardian"s by tethers: it
##               opens when they are dead

const PIT_NEAR := 230.0

var zone: Zone
var kind := ""
var sprung := false  # bonepit
var used := false  # sanctum's bench
var guardians: Array = []  # fissure: the elites still alive
var chest_open := false

var _gates: Array = []
var _chest: Interactable
var _tether: Node2D
var _dark: ColorRect
var _dark_mat: ShaderMaterial


static func attach(z: Zone, kind_: String) -> MiniDungeon:
	var m := MiniDungeon.new()
	m.name = "MiniDungeon"
	m.zone = z
	m.kind = kind_
	z.add_child(m)
	return m


func _ready() -> void:
	match kind:
		"cellar":
			_cellar()
		"sanctum":
			_sanctum()
		"fissure":
			_fissure()


func _marks(id: String) -> Array:
	return zone.maze.markers.get(id, [])


func _thing(at: Vector2, prompt: String, art_fn: Callable, action: Callable) -> Interactable:
	var it := Interactable.new()
	it.position = at
	it.prompt = prompt
	it.radius = 150.0
	it.action = action
	zone.add_child(it)
	var art := Node2D.new()
	art.draw.connect(art_fn.bind(art))
	it.add_child(art)
	return it


func _sprite_at(path: String, at: Vector2, scale_: float) -> Sprite2D:
	var tex: Texture2D = load(path)
	var s := Sprite2D.new()
	s.texture = tex
	s.position = at
	s.offset = Vector2(0, -tex.get_height() * 0.45)
	s.scale = Vector2.ONE * scale_
	zone.add_child(s)
	return s


# ---------- the cellar ----------

func _cellar() -> void:
	var at: Vector2 = _marks("chest")[0] if not _marks("chest").is_empty() else zone.maze.start_pos
	_sprite_at("res://assets/tiles/crypt/decor_24.png", at + Vector2(-110, 40), 0.55)  # a hoard beside it, to be sure
	_sprite_at("res://assets/tiles/crypt/decor_25.png", at + Vector2(120, 30), 0.5)
	_chest = _thing(at, "Open the chest", _art_chest, _mimic)


func _art_chest(n: Node2D) -> void:
	n.draw_rect(Rect2(-34, -44, 68, 44), Color(0.45, 0.28, 0.12))
	n.draw_rect(Rect2(-36, -58, 72, 16), Color(0.55, 0.36, 0.16))
	n.draw_rect(Rect2(-7, -42, 14, 14), Color(1.0, 0.85, 0.3))
	n.draw_rect(Rect2(-36, -58, 72, 58), Color(0.12, 0.08, 0.04), false, 3.0)


func _mimic() -> void:
	_chest.remove_from_group("interactables")
	_chest.visible = false
	zone._flash("The chest has teeth: a mimic!", Color(1.0, 0.5, 0.4))
	var e: Enemy = zone._spawn_enemy(_chest.position, "mimic", "mimic", MonsterAffix.Tier.ELITE)
	e.display_name = "Mimic"
	e.aggro_range = 2000.0
	e.rig.visible = false
	var tex: Texture2D = load("res://assets/tiles/crypt/decor_19.png")
	var s := Sprite2D.new()
	s.texture = tex
	s.offset = Vector2(0, -tex.get_height() * 0.45)
	s.scale = Vector2.ONE * 0.6
	e.add_child(s)
	e.died.connect(func(at: Vector2): _hoard(at))


func _hoard(at: Vector2) -> void:
	zone._flash("The mimic's hoard spills out!", Color(1.0, 0.85, 0.4))
	for k in 3:
		zone._drop_item(LootGenerator.roll_item(zone.area_level + 2, ItemInstance.Rarity.RARE if k < 2 else ItemInstance.Rarity.MAGIC), at + Vector2(-70 + k * 70, 60))
	CurrencyPickup.drop(zone, ["orb", "alteration", 8], at)
	CurrencyPickup.drop(zone, ["orb", "alchemy", 3], at + Vector2(0, 20))
	CurrencyPickup.drop(zone, ["orb", "chaos", 1], at + Vector2(20, 40))
	_sprite_at("res://assets/tiles/crypt/decor_23.png", at, 0.6)


# ---------- the bone pit ----------

func _process(_delta: float) -> void:
	if not is_instance_valid(zone) or not is_instance_valid(zone.player) or zone.player.dead:
		return
	match kind:
		"bonepit":
			if not sprung and not _marks("pit").is_empty() and zone.player.global_position.distance_to(_marks("pit")[0]) < PIT_NEAR:
				_spring()
		"fissure":
			_fissure_tick()


func _spring() -> void:
	sprung = true
	zone._flash("Iron portcullises slam shut: something rises from the bones!", Color(1.0, 0.5, 0.4))
	for g in _marks("gate"):
		_gates.append(_portcullis(g))
	var champion: Enemy = zone._spawn_enemy(_marks("pit")[0] + Vector2(0, -190), "champion", "skeleton_champion", MonsterAffix.Tier.LEGENDARY)
	champion.display_name = "Skeleton Champion"
	champion.aggro_range = 2000.0
	champion.died.connect(func(at: Vector2): _raise(at))


func _portcullis(at: Vector2) -> Node2D:
	var body := StaticBody2D.new()  # a wall as the maze's (layer 1)
	body.position = at
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(150, 150)
	cs.shape = r
	body.add_child(cs)
	var art := Node2D.new()
	art.draw.connect(func():
		art.draw_rect(Rect2(-64, -64, 128, 128), Color(0.0, 0.0, 0.0, 0.35))
		for i in 7:
			art.draw_line(Vector2(-54 + i * 18.0, -62), Vector2(-54 + i * 18.0, 62), Color(0.32, 0.32, 0.36), 6.0)
		art.draw_line(Vector2(-62, -20), Vector2(62, -20), Color(0.28, 0.28, 0.32), 5.0)
		art.draw_line(Vector2(-62, 30), Vector2(62, 30), Color(0.28, 0.28, 0.32), 5.0))
	body.add_child(art)
	zone.add_child(body)
	return body


func _raise(at: Vector2) -> void:
	for g in _gates:
		if is_instance_valid(g):
			g.queue_free()
	_gates.clear()
	zone._flash("The champion falls. The portcullises rise.", Color(1.0, 0.9, 0.6))
	for k in 2:
		zone._drop_item(LootGenerator.roll_item(zone.area_level + 3, ItemInstance.Rarity.RARE), at + Vector2(-40 + k * 80, 40))
	CurrencyPickup.drop(zone, ["orb", "alchemy", 3], at)
	CurrencyPickup.drop(zone, ["orb", "chaos", 1], at + Vector2(0, 30))


# ---------- the hermit's sanctum ----------

func _sanctum() -> void:
	var at: Vector2 = _marks("bench")[0] if not _marks("bench").is_empty() else zone.maze.start_pos
	_chest = _thing(at, "Use the abandoned crafting bench", _art_bench, _bench)


func _art_bench(n: Node2D) -> void:
	n.draw_rect(Rect2(-60, -46, 120, 12), Color(0.5, 0.34, 0.18))
	n.draw_rect(Rect2(-54, -34, 10, 34), Color(0.36, 0.24, 0.12))
	n.draw_rect(Rect2(44, -34, 10, 34), Color(0.36, 0.24, 0.12))
	n.draw_colored_polygon(PackedVector2Array([Vector2(-18, -46), Vector2(-26, -58), Vector2(26, -58), Vector2(18, -46)]), Color(0.45, 0.45, 0.5))  # an anvil
	n.draw_rect(Rect2(32, -56, 6, 12), Color(0.7, 0.4, 0.2))  # a hammer
	if used:
		n.draw_rect(Rect2(-60, -46, 120, 46), Color(0.1, 0.1, 0.1, 0.5))


func _bench() -> void:
	if used:
		zone._flash("The bench has done what it could.", Color(0.8, 0.8, 0.9))
		return
	HermitBench.open(zone, zone.player, func(msg: String):
		used = true
		zone._flash(msg, Color(1.0, 0.9, 0.5))
		_chest.prompt = "The bench is spent"
		_chest.get_child(0).queue_redraw())


# ---------- the weeping fissure ----------

func _fissure() -> void:
	# The dark: a shader that is black but for a pool of light round the player
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_dark = ColorRect.new()
	_dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform vec2 center = vec2(0.5, 0.5);\nuniform float aspect = 1.78;\nuniform float lit = 0.17;\nuniform float fall = 0.30;\nvoid fragment() {\n\tvec2 d = (UV - center) * vec2(aspect, 1.0);\n\tfloat a = smoothstep(lit, lit + fall, length(d));\n\tCOLOR = vec4(0.01, 0.0, 0.03, a * 0.93);\n}\n"
	_dark_mat = ShaderMaterial.new()
	_dark_mat.shader = sh
	_dark.material = _dark_mat
	layer.add_child(_dark)
	# The Tainted Chest and its three tethered guardians
	var at: Vector2 = _marks("chest")[0] if not _marks("chest").is_empty() else zone.maze.start_pos
	_chest = _thing(at, "Open the Tainted Chest", _art_tainted, _open_chest)
	for g in _marks("guardian"):
		var e: Enemy = zone._spawn_enemy(g, "guardian", ["veil_cultist", "bleed_fiend", "blind_crawler"][randi() % 3], MonsterAffix.Tier.ELITE)
		e.display_name = "Tethered " + e.display_name
		e.died.connect(func(_at: Vector2): guardians.erase(e))
		guardians.append(e)
	_tether = Node2D.new()
	_tether.z_index = 3
	zone.add_child(_tether)
	_tether.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		for e in guardians:
			if is_instance_valid(e) and not e._dead:
				var a: Vector2 = _chest.global_position + Vector2(0, -30)
				var b: Vector2 = e.global_position + Vector2(0, -30)
				_tether.draw_line(a, b, Color(1.0, 0.2, 0.3, 0.55 + 0.3 * sin(t * 6.0)), 4.0)
				_tether.draw_line(a, b, Color(1.0, 0.8, 0.85, 0.5), 1.5))


func _art_tainted(n: Node2D) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var col := Color(0.9, 0.15, 0.25) if not guardians.is_empty() else Color(0.95, 0.8, 0.4)
	n.draw_circle(Vector2(0, -26), 52.0 + 4.0 * sin(t * 3.0), Color(col.r, col.g, col.b, 0.25))
	n.draw_rect(Rect2(-36, -44, 72, 44), Color(0.2, 0.08, 0.12))
	n.draw_rect(Rect2(-38, -60, 76, 18), Color(0.3, 0.1, 0.16))
	n.draw_rect(Rect2(-8, -42, 16, 16), col)
	n.draw_rect(Rect2(-38, -60, 76, 60), col, false, 3.0)


func _fissure_tick() -> void:
	if _dark != null:
		var size := _dark.get_viewport().get_visible_rect().size
		var p: Vector2 = _dark.get_viewport().get_canvas_transform() * (zone.player.global_position + Vector2(0, -30))
		_dark_mat.set_shader_parameter("center", p / size)
		_dark_mat.set_shader_parameter("aspect", size.x / size.y)
	if _tether != null:
		_tether.queue_redraw()
	if _chest != null:
		_chest.get_child(0).queue_redraw()


func _open_chest() -> void:
	if chest_open:
		return
	if not guardians.is_empty():
		zone._flash("The Tainted Chest is bound: %d tethered guardian%s remain." % [guardians.size(), "" if guardians.size() == 1 else "s"], Color(1.0, 0.45, 0.5))
		return
	chest_open = true
	_chest.remove_from_group("interactables")
	zone._flash("The tethers snap. The Tainted Chest opens!", Color(1.0, 0.9, 0.5))
	var at := _chest.position
	for k in 3:
		zone._drop_item(LootGenerator.roll_item(zone.area_level + 3, ItemInstance.Rarity.RARE), at + Vector2(-90 + k * 90, 70))
	zone._drop_item(LootGenerator.roll_item(zone.area_level + 3, ItemInstance.Rarity.MAGIC), at + Vector2(0, 130))
	CurrencyPickup.drop(zone, ["orb", "chaos", 2], at)
	CurrencyPickup.drop(zone, ["orb", "alchemy", 4], at + Vector2(0, 20))
	CurrencyPickup.drop(zone, ["orb", "exalt", 1], at + Vector2(30, 40))
