class_name ZoneEncounters
extends Node
## Random encounters out in the campaign: when you enter a zone there is a chance that one is waiting
## somewhere off the beaten way (a different one, in a different place, every visit):
##   Cottage - a cottage in the woods with someone crying for help. Come close and the zombies inside
##     burst out; clear them all and free the captive, who rewards you.
##   Ritual  - cultists chanting round a summoning circle. Come close and a countdown starts: kill
##     them all before it ends (each death buys time) and the ritual breaks; if it ends, a Summoned
##     Horror tears through, a boss to put down for its loot.
## A party's zones have none yet (their monsters are run by the party host: Coop).

const CHANCE := 0.45  # per visit to a zone
const KINDS := ["cottage", "ritual"]
const MIN_FROM_START := 900.0  # not on top of where you arrive...
const MIN_FROM_EXIT := 500.0  # ...or an exit or NPC
const CLEAR_CELLS := 3  # open floor all round it, this many cells each way
const COTTAGE_NEAR := 420.0  # the zombies break out when you get this close
const RITUAL_NEAR := 650.0  # the chanting starts
const RITUAL_SECONDS := 45.0
const RITUAL_BONUS := 6.0  # seconds a dead cultist buys

var zone: Zone
var kind := ""
var pos := Vector2.ZERO
var state := ""  # cottage: "closed" | "fight" | "captive" | "done"; ritual: "waiting" | "chant" | "summoned" | "done"
var foes: Array = []  # the Enemies of the fight still alive
var time_left := 0.0
var _site: Node2D
var _tag: Label  # the countdown, top of the screen
var _hud: CanvasLayer


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


## Open floor away from where you arrive, the exits and the NPCs, and reachable from the start.
func find_spot() -> Vector2:
	var maze := zone.maze
	var keep_away: Array = []
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
	if kind == "cottage":
		state = "closed"
		_build_cottage()
	else:
		state = "waiting"
		_build_ritual()


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
	CurrencyPickup.add_to_bundle(zone, "Currency", ["orb", "alteration", 2], at)
	CurrencyPickup.add_to_bundle(zone, "Currency", ["shard", "alchemy", 6 if big else 3], at)
	zone.spawn_currency("scroll", "town_portal", 1, at + Vector2(0, 60))


func _process(delta: float) -> void:
	if not is_instance_valid(zone) or not is_instance_valid(zone.player) or zone.player.dead:
		return
	var d := zone.player.global_position.distance_to(pos)
	if kind == "cottage":
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
