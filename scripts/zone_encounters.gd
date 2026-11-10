class_name ZoneEncounters
extends Node
## Random encounters out in the campaign: when you enter a zone there is a chance that one is waiting
## somewhere off the beaten way (a different one, in a different place, every visit):
##   Cottage - a cottage in the woods with someone crying for help. Come close and the zombies inside
##     burst out; clear them all and free the captive, who rewards you.
##   Ritual  - cultists chanting round a summoning circle. Come close and a countdown starts: kill
##     them all before it ends (each death buys time) and the ritual breaks; if it ends, a Summoned
##     Horror tears through, a boss to put down for its loot.
##   Shrine  - a cursed shrine, a bleeding obelisk. Use it and three waves of fiends come in 45 seconds; cleanse it (kill them all) for
##     a rich cluster of loot and a two-minute blessing.
##   Rift    - Tears in Reality: a Bleed Rift opens and swells, pulling you in and vomiting elite monsters. Destroy the three spires tethering
##     it before the time runs out to seal it; if it ends, a Rift Horror tears through.
##   Pilgrim - The Dying Pilgrim: a wounded paladin channels a purification circle against waves of rot fiends. Keep him above half his
##     life and a hidden consecrated reliquary opens.
##   Pyre    - Pyre of the Dead: a heap of contaminated corpses is changing. Light it before it finishes, and the swarm round it enrages: a
##     dense horde brawl in a ring of fire. Too slow, and they rise anyway.
## A party's zones have none yet (their monsters are run by the party host: Coop).

const CHANCE := 0.5  # per visit to a zone
const KINDS := ["cottage", "ritual", "shrine", "rift", "pilgrim", "pyre"]
const MIN_FROM_START := 900.0  # not on top of where you arrive...
const MIN_FROM_EXIT := 500.0  # ...or an exit or NPC
const CLEAR_CELLS := 3  # open floor all round it, this many cells each way
const COTTAGE_NEAR := 420.0  # the zombies break out when you get this close
const RITUAL_NEAR := 650.0  # the chanting starts
const RITUAL_SECONDS := 45.0
const RITUAL_BONUS := 6.0  # seconds a dead cultist buys
const SHRINE_WAVES := 3
const SHRINE_GAP := 15.0  # seconds between waves (a cleared wave brings the next sooner)
const BLESS_SECONDS := 120.0
const RIFT_NEAR := 900.0
const RIFT_SECONDS := 80.0
const RIFT_SPIRES := 3
const PILGRIM_NEAR := 650.0
const PILGRIM_WAVES := 4
const PILGRIM_GAP := 14.0
const PILGRIM_LIFE := 100.0
const PYRE_NEAR := 1100.0
const PYRE_SECONDS := 40.0
const PYRE_RING := 470.0

var zone: Zone
var kind := ""
var pos := Vector2.ZERO
var state := ""  # cottage: "closed" | "fight" | "captive" | "done"; ritual: "waiting" | "chant" | "summoned" | "done"
var foes: Array = []  # the Enemies of the fight still alive
var time_left := 0.0
var _site: Node2D
var _tag: Label  # the countdown, top of the screen
var _hud: CanvasLayer
var wave := 0  # shrine and pilgrim: waves sent
var life := PILGRIM_LIFE  # the pilgrim's
var spires: Array = []  # rift: the spires still standing
var _wave_t := 0.0
var _rift_r := 0.0
var _spawn_t := 0.0
var _it: Interactable  # what you use (the shrine, the pyre, the reliquary)
var _ring: StaticBody2D  # the pyre's wall of fire
var _pilgrim: Node2D


## Rolls whether this visit has one, and sets it up (`force` names one to have). Returns it (null for none).
static func roll(z: Zone, force := "") -> ZoneEncounters:
	if force == "" and randf() >= CHANCE:
		return null
	var e := ZoneEncounters.new()
	e.zone = z
	e.kind = force if force != "" else KINDS[randi() % KINDS.size()]
	var at := e.find_spot()
	if not at.is_finite():
		e.free()
		return null
	e.pos = at
	z.add_child(e)
	e.build()
	return e


func find_spot() -> Vector2:
	return spot(zone)


## Open floor away from where you arrive, the exits and the NPCs (and `also`), and reachable from the start.
static func spot(zone: Zone, also: Array = []) -> Vector2:
	var maze := zone.maze
	var keep_away: Array = also.duplicate()
	for ex in zone._exits:
		keep_away.append(ex["node"].global_position)
	for n in zone.get_tree().get_nodes_in_group("interactables"):
		keep_away.append(n.global_position)
	for i in 300:
		var c := Vector2i(randi_range(CLEAR_CELLS, maze.cols - 1 - CLEAR_CELLS), randi_range(CLEAR_CELLS, maze.rows - 1 - CLEAR_CELLS))
		var ok := true
		for dy in range(-CLEAR_CELLS, CLEAR_CELLS + 1):
			for dx in range(-CLEAR_CELLS, CLEAR_CELLS + 1):
				if maze.is_wall(c + Vector2i(dx, dy)):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		var p := maze.cell_center(c)
		if p.distance_to(maze.start_pos) < MIN_FROM_START:
			continue
		var near := false
		for k in keep_away:
			if p.distance_to(k) < MIN_FROM_EXIT:
				near = true
				break
		if near:
			continue
		if maze._astar.get_id_path(maze.world_to_cell(maze.start_pos), c).is_empty():
			continue  # shut off from the rest of the map
		return p
	return Vector2(INF, INF)


func build() -> void:
	_site = Node2D.new()
	_site.position = pos
	zone.add_child(_site)
	match kind:
		"cottage":
			state = "closed"
			_build_cottage()
		"ritual":
			state = "waiting"
			_build_ritual()
		"shrine":
			state = "idle"
			_build_shrine()
		"rift":
			state = "waiting"
			_build_rift()
		"pilgrim":
			state = "waiting"
			_build_pilgrim()
		"pyre":
			state = "waiting"
			_build_pyre()


# ---------- the cottage ----------

func _build_cottage() -> void:
	var tex := MapTheme.load_sprite(zone.maze.theme, "building_%d" % randi_range(1, 5))
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.9)
		s.scale = Vector2(0.5, 0.5)
		s.position = pos  # (a child of the zone, y-sorted with everything else)
		zone.add_child(s)
		PropFader.attach(zone, s)  # see-through with you behind it
	else:
		_site.draw.connect(func():
			_site.draw_rect(Rect2(-60, -90, 120, 90), Color(0.45, 0.33, 0.22))
			_site.draw_colored_polygon(PackedVector2Array([Vector2(-70, -90), Vector2(0, -150), Vector2(70, -90)]), Color(0.5, 0.2, 0.15)))
	zone._label(_site, "Cottage", Color(1.0, 0.9, 0.6), -190.0)


func _burst() -> void:
	state = "fight"
	zone._flash("The door bursts open: zombies pour out!", Color(1.0, 0.5, 0.4))
	var n := mini(5 + int(zone.area_level / 3.0), 9)
	for i in n:
		var at := pos + Vector2(randf_range(-110.0, 110.0), randf_range(30.0, 130.0))
		var e: Enemy = zone._spawn_enemy(at, "cottage", ["zombie", "villager"][randi() % 2],
			MonsterAffix.roll_tier(zone.area_level) if i == 0 else MonsterAffix.Tier.NORMAL)
		e.aggro_range = 2000.0  # they come for you
		_watch(e)


func _free_captive() -> void:
	state = "captive"
	zone._flash("The zombies are dead. Someone is still calling from inside...", Color(0.7, 1.0, 0.7))
	var who := Interactable.new()
	who.position = pos + Vector2(0, 70)
	who.prompt = "Free the captive"
	zone.add_child(who)
	var rig := RigSprite.new()
	rig.base_scale = 0.2
	rig.skin = "forest_ranger_2"
	who.add_child(rig)
	rig.play_loop("Idle")
	var sh := Node2D.new()
	sh.draw.connect(func(): RigSprite.draw_shadow(sh, 24.0))
	who.add_child(sh)
	who.move_child(sh, 0)
	zone._label(who, "Captive", Color(0.7, 1.0, 0.7), -130.0)
	who.action = func():
		who.remove_from_group("interactables")
		who.visible = false
		zone._flash("\"Thank you, stranger! Take this, it's all I have.\"", Color(0.7, 1.0, 0.7))
		_reward(who.position, false)
		who.queue_free()
		state = "done"


# ---------- the ritual ----------

func _build_ritual() -> void:
	_site.z_index = -1
	_site.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var col := Color(0.35, 0.8, 0.45) if state == "done" else Color(0.85, 0.15, 0.2)
		var glow := 0.55 + 0.25 * sin(t * 3.0)
		_site.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		_site.draw_circle(Vector2.ZERO, 150, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.6))
		_site.draw_arc(Vector2.ZERO, 150, 0, TAU, 64, Color(col.r, col.g, col.b, glow), 4.0)
		_site.draw_arc(Vector2.ZERO, 112, 0, TAU, 64, Color(col.r, col.g, col.b, glow * 0.8), 2.5)
		for i in 5:  # a five-pointed star
			var a := TAU * i / 5.0 - PI * 0.5
			var b := TAU * ((i + 2) % 5) / 5.0 - PI * 0.5
			_site.draw_line(Vector2.from_angle(a) * 130.0, Vector2.from_angle(b) * 130.0, Color(col.r, col.g, col.b, glow), 3.0)
		_site.draw_set_transform(Vector2.ZERO))
	zone._label(_site, "Ritual Circle", Color(1.0, 0.45, 0.45), -80.0)
	var n := mini(3 + int(zone.area_level / 4.0), 6)
	var kinds: Array = ["goblin", "orc_shaman", "dark_elf"].filter(func(k): return int(MonsterKinds.KINDS[k]["min_level"]) <= zone.area_level)
	if kinds.is_empty():
		kinds = ["goblin"]
	for i in n:
		var at := pos + Vector2.from_angle(TAU * i / n) * 105.0
		var e: Enemy = zone._spawn_enemy(at, "cult", kinds[randi() % kinds.size()], MonsterAffix.Tier.NORMAL)
		e.display_name = "Cultist"
		e.aggro_range = 0.0  # chanting: they stand their ground until you are close (_start_chant)
		_watch(e)
	_ensure_tag()


## The line at the top of the screen (the countdown, the waves).
func _ensure_tag() -> void:
	if _tag != null:
		return
	_hud = CanvasLayer.new()
	zone.add_child(_hud)
	_tag = UIKit.label("", 22, Color(1.0, 0.5, 0.5))
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_tag.add_theme_constant_override("outline_size", 6)
	_tag.visible = false
	_hud.add_child(_tag)
	_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 78)


func _start_chant() -> void:
	state = "chant"
	time_left = RITUAL_SECONDS
	zone._flash("Cultists are chanting! Break the ritual before it ends!", Color(1.0, 0.45, 0.45))
	for e in foes:
		if is_instance_valid(e):
			e.aggro_range = 700.0


func _summon() -> void:
	state = "summoned"
	_tag.visible = false
	var kinds: Array = ["orc", "ghoul", "mummy", "skeleton_warrior"].filter(func(k): return int(MonsterKinds.KINDS[k]["min_level"]) <= zone.area_level)
	if kinds.is_empty():
		kinds = ["zombie"]
	zone._flash("The ritual is complete: something answers the call!", Color(1.0, 0.3, 0.3))
	zone._spawn_boss({"x": pos.x, "y": pos.y, "kind": kinds[randi() % kinds.size()], "name": "Summoned Horror",
		"hp": 6.0, "size": 1.7, "id": ""})
	for e in foes:  # the cultists flee the thing they called
		if is_instance_valid(e):
			e.aggro_range = 0.0


func _break_ritual() -> void:
	state = "done"
	_tag.visible = false
	zone._flash("The ritual is broken!", Color(0.6, 1.0, 0.6))
	_reward(pos, true)


# ---------- the cursed shrine ----------

func _build_shrine() -> void:
	_ensure_tag()
	_site.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var spent := state == "done"
		var col := Color(0.95, 0.8, 0.4) if spent else Color(0.9, 0.12, 0.2)
		var glow := 0.5 + 0.3 * sin(t * 3.0)
		_site.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		_site.draw_circle(Vector2.ZERO, 120, Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.55))
		_site.draw_arc(Vector2.ZERO, 120, 0, TAU, 48, Color(col.r, col.g, col.b, glow), 4.0)
		_site.draw_set_transform(Vector2.ZERO)
		var obelisk := PackedVector2Array([Vector2(-34, 0), Vector2(-24, -170), Vector2(0, -215), Vector2(24, -170), Vector2(34, 0)])
		_site.draw_colored_polygon(obelisk, Color(0.12, 0.1, 0.14))
		_site.draw_polyline(PackedVector2Array([obelisk[0], obelisk[1], obelisk[2], obelisk[3], obelisk[4]]), Color(col.r, col.g, col.b, 0.9), 3.0)
		for i in 5:  # veins, and the blood running down
			var x := -16.0 + i * 8.0
			_site.draw_line(Vector2(x, -150 + i * 6.0), Vector2(x + 3.0, -20.0 - fmod(t * 30.0 + i * 23.0, 60.0)), Color(col.r, col.g, col.b, 0.8), 2.0)
		_site.draw_circle(Vector2(0, -190), 10.0 + 3.0 * sin(t * 4.0), Color(col.r, col.g, col.b, 0.9)))
	zone._label(_site, "Cursed Shrine", Color(1.0, 0.45, 0.45), -250.0)
	_it = Interactable.new()
	_it.position = pos
	_it.prompt = "Cleanse the Cursed Shrine"
	_it.radius = 150.0
	_it.action = _shrine_start
	zone.add_child(_it)


func _shrine_start() -> void:
	if state != "idle":
		return
	state = "waves"
	_it.remove_from_group("interactables")
	zone._flash("The shrine bleeds, and the dark answers: cleanse it!", Color(1.0, 0.45, 0.45))
	_wave_t = 0.0


func _shrine_wave() -> void:
	wave += 1
	_wave_t = SHRINE_GAP
	var n := 4 + wave + int(zone.area_level / 5.0)
	_send_wave(n, ["bleed_fiend"], wave == SHRINE_WAVES, 330.0)


## `n` monsters out of the dark round the site, after you; the first an elite when `lead`.
func _send_wave(n: int, kinds: Array, lead: bool, dist: float) -> void:
	for i in n:
		var at := pos + Vector2.from_angle(TAU * (float(i) + randf() * 0.6) / float(n)) * randf_range(dist, dist + 140.0)
		if zone.maze.is_wall(zone.maze.world_to_cell(at)):
			at = zone.maze.random_floor_near(pos, 150.0, dist + 100.0)
		var e: Enemy = zone._spawn_enemy(at, "event", String(kinds[randi() % kinds.size()]),
			MonsterAffix.Tier.ELITE if (lead and i == 0) else MonsterAffix.Tier.NORMAL)
		e.aggro_range = 2000.0
		_watch(e)


func _shrine_done() -> void:
	state = "done"
	_tag.visible = false
	zone._flash("The shrine is cleansed! You feel its blessing.", Color(1.0, 0.9, 0.5))
	_reward(pos, true)
	zone._drop_item(LootGenerator.roll_item(zone.area_level + 3, ItemInstance.Rarity.RARE), pos + Vector2(0, 90))
	CurrencyPickup.drop(zone, ["orb", "chaos", 1], pos + Vector2(60, 60))
	zone.player.bless(BLESS_SECONDS)


# ---------- tears in reality ----------

func _build_rift() -> void:
	_ensure_tag()
	_site.z_index = -1
	_rift_r = 70.0
	_site.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var sealed_ := state == "done"
		var r := _rift_r * (0.35 if sealed_ else 1.0)
		_site.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
		_site.draw_circle(Vector2.ZERO, r, Color(0.25, 0.02, 0.2, 0.55))
		for i in 4:
			var rr := r - i * (r * 0.2) + sin(t * 2.0 + i) * 4.0
			var a0 := t * (1.0 + i * 0.3)
			_site.draw_arc(Vector2.ZERO, rr, a0, a0 + TAU * 0.78, 40, Color(0.95, 0.25, 0.4, 0.85 - i * 0.15), 5.0)
		_site.draw_circle(Vector2.ZERO, r * 0.22, Color(1.0, 0.8, 0.9, 0.55 + 0.25 * sin(t * 3.0)))
		_site.draw_set_transform(Vector2.ZERO))
	zone._label(_site, "Bleed Rift", Color(1.0, 0.45, 0.6), -70.0)


func _rift_open() -> void:
	state = "open"
	time_left = RIFT_SECONDS
	zone._flash("Tears in Reality! A rift is opening: destroy the spires that hold it!", Color(1.0, 0.45, 0.6))
	for i in RIFT_SPIRES:
		var at := pos + Vector2.from_angle(TAU * (float(i) + randf() * 0.4) / float(RIFT_SPIRES)) * 380.0
		if zone.maze.is_wall(zone.maze.world_to_cell(at)):
			at = zone.maze.random_floor_near(pos, 250.0, 420.0)
		spires.append(_make_spire(at))
	_spawn_t = 3.0


func _make_spire(at: Vector2) -> Enemy:
	var e: Enemy = zone._spawn_enemy(at, "spire", "rift_spire", MonsterAffix.Tier.NORMAL)
	e.aggro_range = 0.0
	e.display_name = "Rift Spire"
	e.rig.visible = false
	var tex: Texture2D = load("res://assets/tiles/crypt/rift_2.png")
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.offset = Vector2(0, -tex.get_height() * 0.45)
		s.scale = Vector2.ONE * 1.1
		e.add_child(s)
	e.died.connect(func(_at: Vector2): spires.erase(e))
	return e


## The rift draws you in, as it widens.
func _rift_pull(delta: float) -> void:
	var p := zone.player
	var to := pos - p.global_position
	var reach := 260.0 + _rift_r * 2.0
	var d := to.length()
	if d > reach or d < 50.0:
		return
	var step := (30.0 + 120.0 * (1.0 - d / reach)) * delta
	var at: Vector2 = p.global_position + to.normalized() * step
	if not zone.maze.is_wall(zone.maze.world_to_cell(at)):
		p.global_position = at


func _rift_tick(delta: float) -> void:
	time_left -= delta
	_rift_r = 70.0 + 230.0 * (1.0 - clampf(time_left / RIFT_SECONDS, 0.0, 1.0))
	_rift_pull(delta)
	_spawn_t -= delta
	if _spawn_t <= 0.0 and foes.size() < 9:
		_spawn_t = 9.0
		for i in 3:
			var at := pos + Vector2.from_angle(randf() * TAU) * _rift_r * 0.6
			var e: Enemy = zone._spawn_enemy(at, "event", ["bleed_fiend", "ghoul"][randi() % 2],
				MonsterAffix.Tier.ELITE if i == 0 else MonsterAffix.Tier.NORMAL)
			e.aggro_range = 2000.0
			_watch(e)
	_tag.visible = true
	_tag.text = "Tears in Reality  %d s   (%d spires)" % [maxi(0, ceili(time_left)), spires.size()]
	if spires.is_empty():
		state = "done"
		_tag.visible = false
		zone._flash("The spires are down: the rift seals!", Color(0.6, 1.0, 0.6))
		_reward(pos, true)
	elif time_left <= 0.0:
		state = "burst"
		_tag.visible = false
		zone._flash("The rift bursts: something comes through!", Color(1.0, 0.3, 0.3))
		zone._spawn_boss({"x": pos.x, "y": pos.y, "kind": "ghoul", "name": "Rift Horror", "hp": 6.0, "size": 1.8, "id": ""})


# ---------- the dying pilgrim ----------

func _build_pilgrim() -> void:
	_ensure_tag()
	_pilgrim = Node2D.new()
	_pilgrim.position = pos
	zone.add_child(_pilgrim)
	var rig := RigSprite.new()
	rig.base_scale = 0.2
	rig.skin = "caravan_guard"
	_pilgrim.add_child(rig)
	rig.play_loop("Idle Blinking")
	rig.modulate = Color(1.0, 0.85, 0.85)
	_site.z_index = -1
	_site.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var col := Color(1.0, 0.9, 0.5) if state in ["defend", "done"] else Color(0.7, 0.7, 0.8)
		var glow := 0.5 + 0.3 * sin(t * 2.5)
		_site.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		_site.draw_circle(Vector2.ZERO, 130, Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.45))
		_site.draw_arc(Vector2.ZERO, 130, 0, TAU, 56, Color(col.r, col.g, col.b, glow), 4.0)
		_site.draw_arc(Vector2.ZERO, 95, 0, TAU, 56, Color(col.r, col.g, col.b, glow * 0.8), 2.5)
		_site.draw_set_transform(Vector2.ZERO)
		# his life, over his head
		var frac := clampf(life / PILGRIM_LIFE, 0.0, 1.0)
		_site.draw_rect(Rect2(-40, -150, 80, 8), Color(0.1, 0.05, 0.05, 0.85))
		_site.draw_rect(Rect2(-40, -150, 80 * frac, 8), Color(0.4, 0.9, 0.5) if frac > 0.5 else Color(0.95, 0.5, 0.3)))
	zone._label(_site, "Dying Pilgrim", Color(1.0, 0.9, 0.6), -190.0)


func _pilgrim_wave() -> void:
	wave += 1
	_wave_t = PILGRIM_GAP
	_send_wave(4 + int(wave / 2) + int(zone.area_level / 6.0), ["bleed_fiend", "leechfiend", "fen_crawler"], wave == PILGRIM_WAVES, 360.0)


func _pilgrim_tick(delta: float) -> void:
	# the fiends that reach him tear at him
	for e in foes:
		if is_instance_valid(e) and not e._dead and e.global_position.distance_to(pos) < 170.0:
			life -= 7.0 * delta
	_site.queue_redraw()
	_tag.visible = true
	_tag.text = "Defend the Pilgrim  %d%%   (wave %d / %d)" % [maxi(0, int(ceil(life))), wave, PILGRIM_WAVES]
	if life <= 0.0:
		state = "failed"
		_tag.visible = false
		zone._flash("The pilgrim falls. The circle goes dark.", Color(1.0, 0.4, 0.4))
		_pilgrim.modulate = Color(0.5, 0.5, 0.55)
		return
	_wave_t -= delta
	if wave < PILGRIM_WAVES and (_wave_t <= 0.0 or foes.is_empty()):
		_pilgrim_wave()
	elif wave >= PILGRIM_WAVES and foes.is_empty():
		_pilgrim_done()


func _pilgrim_done() -> void:
	_tag.visible = false
	state = "done"
	if life > PILGRIM_LIFE * 0.5:
		zone._flash("\"You held the line. Take what the Order left here.\" A hidden reliquary glows open.", Color(1.0, 0.9, 0.5))
		_it = Interactable.new()
		_it.position = pos + Vector2(0, 120)
		_it.prompt = "Open the consecrated reliquary"
		_it.radius = 150.0
		var chest := Node2D.new()
		chest.draw.connect(func():
			chest.draw_rect(Rect2(-30, -40, 60, 40), Color(0.85, 0.75, 0.4))
			chest.draw_rect(Rect2(-32, -52, 64, 14), Color(0.95, 0.85, 0.5))
			chest.draw_rect(Rect2(-6, -34, 12, 12), Color(1.0, 1.0, 0.8))
			chest.draw_rect(Rect2(-32, -52, 64, 52), Color(0.3, 0.22, 0.08), false, 2.5))
		_it.add_child(chest)
		_it.action = func():
			_it.remove_from_group("interactables")
			_it.visible = false
			zone._flash("The reliquary opens.", Color(1.0, 0.9, 0.5))
			_reward(_it.position, true)
			zone._drop_item(LootGenerator.roll_item(zone.area_level + 3, ItemInstance.Rarity.RARE), _it.position + Vector2(-50, 40))
		zone.add_child(_it)
	else:
		zone._flash("The pilgrim lives, but too little of him: the reliquary stays sealed.", Color(0.8, 0.8, 0.9))
		_reward(pos, false)


# ---------- the pyre of the dead ----------

func _build_pyre() -> void:
	_ensure_tag()
	_site.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var burning := state in ["burning", "done"]
		for i in 9:  # the heap: corpses under a rag
			var a := TAU * i / 9.0
			var r := 25.0 + 22.0 * float(i % 3)
			var c := Vector2.from_angle(a) * r * Vector2(1.0, 0.55) + Vector2(0, -8.0 * float(i % 2))
			_site.draw_circle(c, 22.0, Color(0.30, 0.28, 0.22) if i % 2 else Color(0.38, 0.34, 0.26))
			_site.draw_line(c + Vector2(-14, 0), c + Vector2(14, -6), Color(0.78, 0.75, 0.65), 3.0)
		if state == "stirring":  # the corpses twitch, a sick green
			for i in 4:
				_site.draw_circle(Vector2(sin(t * 5.0 + i) * 36.0, -14.0 + cos(t * 4.0 + i * 2.0) * 10.0), 6.0, Color(0.5, 0.95, 0.3, 0.55))
		if burning and state != "done":
			for i in 7:
				var x := -40.0 + i * 13.0
				var h := 50.0 + 30.0 * sin(t * 9.0 + i * 1.7)
				_site.draw_colored_polygon(PackedVector2Array([Vector2(x - 9, -6), Vector2(x, -6 - h), Vector2(x + 9, -6)]), Color(1.0, 0.55, 0.1, 0.85))
				_site.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, -6), Vector2(x, -6 - h * 0.6), Vector2(x + 5, -6)]), Color(1.0, 0.9, 0.4, 0.9))
			var pulse := 0.5 + 0.5 * sin(t * 3.0)
			_site.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.7))
			_site.draw_arc(Vector2.ZERO, PYRE_RING, 0.0, TAU, 96, Color(1.0, 0.4, 0.1, 0.25 + 0.15 * pulse), 30.0)
			_site.draw_arc(Vector2.ZERO, PYRE_RING, 0.0, TAU, 96, Color(1.0, 0.6, 0.2, 0.8), 7.0)
			_site.draw_set_transform(Vector2.ZERO))
	zone._label(_site, "Pile of the Dead", Color(0.75, 0.85, 0.55), -110.0)
	_it = Interactable.new()
	_it.position = pos
	_it.prompt = "Ignite the pyre"
	_it.radius = 150.0
	_it.action = _pyre_ignite
	zone.add_child(_it)


func _pyre_ignite() -> void:
	if state not in ["waiting", "stirring"]:
		return
	state = "burning"
	_it.remove_from_group("interactables")
	_tag.visible = false
	zone._flash("The pyre catches. The dead scream, and the swarm round it goes wild!", Color(1.0, 0.6, 0.2))
	_ring = _make_ring(PYRE_RING)
	_horde(true)


func _pyre_risen() -> void:
	state = "risen"
	_it.remove_from_group("interactables")
	_tag.visible = false
	zone._flash("Too late: the dead rise!", Color(0.7, 1.0, 0.4))
	_horde(false)


func _horde(ringed: bool) -> void:
	var n := mini(12 + int(zone.area_level / 2.0), 18)
	var kinds := ["zombie", "villager", "ghoul"]
	for i in n:
		var at := pos + Vector2.from_angle(TAU * (float(i) + randf() * 0.6) / float(n)) * randf_range(170.0, PYRE_RING - 90.0 if ringed else 320.0)
		var e: Enemy = zone._spawn_enemy(at, "event", kinds[randi() % kinds.size()], MonsterAffix.Tier.ELITE if i < 2 else MonsterAffix.Tier.NORMAL)
		e.aggro_range = 2000.0
		e.speed *= 1.2 if ringed else 1.0  # enraged
		_watch(e)


## A wall of fire round `pos` that nothing crosses (BossArena's ring), until it is taken down.
func _make_ring(r: float) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = BossArena.LAYER
	b.collision_mask = 0
	b.position = pos
	zone.add_child(b)
	var n := int(ceil(TAU * r / 56.0))
	for i in n:
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 36.0
		cs.shape = c
		cs.position = Vector2.from_angle(TAU * i / n) * r
		b.add_child(cs)
	return b


# ---------- shared ----------

func _watch(e: Enemy) -> void:
	foes.append(e)
	e.died.connect(func(_at: Vector2): _foe_died(e))


func _foe_died(e: Enemy) -> void:
	foes.erase(e)
	if kind == "ritual" and state == "chant":
		time_left += RITUAL_BONUS


## What an encounter pays: a rare, orbs (one pile of currency) and a Town Portal scroll; the ritual
## pays more for facing a threat.
func _reward(at: Vector2, big: bool) -> void:
	zone._drop_item(LootGenerator.roll_item(zone.area_level + 1, ItemInstance.Rarity.RARE), at + Vector2(-40, 30))
	if big:
		zone._drop_item(LootGenerator.roll_item(zone.area_level + 1, ItemInstance.Rarity.MAGIC), at + Vector2(40, 30))
	CurrencyPickup.drop(zone, ["orb", "alteration", 2], at)
	CurrencyPickup.drop(zone, ["shard", "alchemy", 6 if big else 3], at)
	zone.spawn_currency("scroll", "town_portal", 1, at + Vector2(0, 60))


func _process(delta: float) -> void:
	if not is_instance_valid(zone) or not is_instance_valid(zone.player) or zone.player.dead:
		return
	var d := zone.player.global_position.distance_to(pos)
	if kind == "shrine":
		_site.queue_redraw()
		if state == "waves":
			_wave_t -= delta
			if wave < SHRINE_WAVES and (_wave_t <= 0.0 or (wave > 0 and foes.is_empty())):
				_shrine_wave()
			elif wave >= SHRINE_WAVES and foes.is_empty():
				_shrine_done()
			_tag.visible = state == "waves"
			_tag.text = "Cursed Shrine  wave %d / %d   (%d left)" % [wave, SHRINE_WAVES, foes.size()]
		elif state == "done" and zone.player.blessing_t > 0.0:
			_tag.visible = true
			_tag.text = "Shrine's blessing  %d:%02d" % [int(zone.player.blessing_t) / 60, int(zone.player.blessing_t) % 60]
		elif state == "done":
			_tag.visible = false
	elif kind == "rift":
		_site.queue_redraw()
		match state:
			"waiting":
				if d < RIFT_NEAR:
					_rift_open()
			"open":
				_rift_tick(delta)
			"burst":
				if is_instance_valid(zone._boss) and zone._boss._dead and zone._boss.display_name == "Rift Horror":
					state = "done"
	elif kind == "pilgrim":
		match state:
			"waiting":
				if d < PILGRIM_NEAR:
					state = "defend"
					zone._flash("A wounded paladin: \"Hold them off while I finish the rite!\"", Color(1.0, 0.9, 0.5))
					_wave_t = 0.0
			"defend":
				_pilgrim_tick(delta)
	elif kind == "pyre":
		_site.queue_redraw()
		match state:
			"waiting":
				if d < PYRE_NEAR:
					state = "stirring"
					time_left = PYRE_SECONDS
					zone._flash("The corpses are changing! Burn them before they finish!", Color(0.7, 1.0, 0.4))
			"stirring":
				time_left -= delta
				_tag.visible = true
				_tag.text = "The dead are stirring  %d s" % maxi(0, ceili(time_left))
				if time_left <= 0.0:
					_pyre_risen()
			"burning":
				if foes.is_empty():
					state = "done"
					if is_instance_valid(_ring):
						_ring.queue_free()
					zone._flash("The fire dies down. The dead are ash.", Color(1.0, 0.8, 0.5))
					_reward(pos, true)
					zone._drop_item(LootGenerator.roll_item(zone.area_level + 2, ItemInstance.Rarity.RARE), pos + Vector2(0, 100))
			"risen":
				if foes.is_empty():
					state = "done"
					_reward(pos, false)
	elif kind == "cottage":
		match state:
			"closed":
				if d < COTTAGE_NEAR:
					_burst()
			"fight":
				if foes.is_empty():
					_free_captive()
	else:
		_site.queue_redraw()
		match state:
			"waiting":
				if d < RITUAL_NEAR:
					_start_chant()
			"chant":
				time_left -= delta
				_tag.visible = true
				_tag.text = "Ritual  %d s   (%d cultists)" % [maxi(0, ceili(time_left)), foes.size()]
				if foes.is_empty():
					_break_ritual()
				elif time_left <= 0.0:
					_summon()
			"summoned":
				if is_instance_valid(zone._boss) and zone._boss._dead and zone._boss.display_name == "Summoned Horror":
					state = "done"
