class_name VeilRealm
extends Node
## Lord Malaphax's Veil Realm (a phase's "veil" in BossDB): the fight is dragged into the dark. The screen dims, shadows tear at
## everyone in the fight a little at a time, and an ambient Rift Soul drifts somewhere in the arena: destroy it and the dark lifts.
## A child of the boss's brain (so it is gone when the fight is: the boss dies or the zone starts the fight over). The brain
## runs only in the game that runs the monster, so a party's other players take the shadows' hits but see no dimming.
##
## "veil": {"interval": seconds from one realm's end to the next, "tick": seconds between the shadows' hits,
##          "share": of the boss's hit each one does, "souls": how many Rift Souls (all must fall)}

signal ended

var brain: BossBrain
var souls: Array = []
var share := 0.08
var tick := 0.5
var age := 0.0

var _tick_t := 0.0
var _layer: CanvasLayer
var _view: Control
var _fade := 0.0
var _over := false


## Starts a realm on `brain`'s fight, from its phase's `cfg`.
static func begin(brain_: BossBrain, cfg: Dictionary) -> VeilRealm:
	var r := VeilRealm.new()
	r.name = "VeilRealm"
	r.brain = brain_
	r.share = float(cfg.get("share", 0.08))
	r.tick = float(cfg.get("tick", 0.5))
	brain_.add_child(r)
	r._open(int(cfg.get("souls", 1)))
	return r


func _open(count: int) -> void:
	var boss := brain.boss
	var parent := boss.get_parent()
	for i in count:
		var at := boss.global_position + Vector2.from_angle(randf() * TAU) * randf_range(300.0, 520.0)
		if boss.maze != null and boss.maze.is_wall(boss.maze.world_to_cell(at)):
			at = boss.maze.random_floor_near(boss.global_position, 250.0, 520.0)
		var s: Enemy = parent.spawn_add("rift_soul", at) if parent.has_method("spawn_add") else null
		if s == null:
			continue
		s.set_meta("veil_soul", true)
		s._tint = Color(0.75, 0.55, 1.0, 0.85)
		s.rig.modulate = s._tint
		souls.append(s)
	_layer = CanvasLayer.new()
	_layer.layer = 0  # over the world, under the HUD
	add_child(_layer)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_paint)
	_layer.add_child(_view)
	brain._say("The Veil takes you. Come to me.")


func alive_souls() -> Array:
	souls = souls.filter(func(s): return is_instance_valid(s) and not s._dead)
	return souls


func _process(delta: float) -> void:
	if _over:
		_fade = maxf(_fade - delta * 1.6, 0.0)
		_view.queue_redraw()
		if _fade <= 0.0:
			queue_free()
		return
	age += delta
	_fade = minf(_fade + delta * 1.2, 1.0)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick
		var dmg := brain.boss.touch_damage * share
		for p in brain._victims():
			p.take_damage(dmg, brain.boss.element)
	if alive_souls().is_empty():
		_over = true
		ended.emit()
	_view.queue_redraw()


func _paint() -> void:
	var size := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.0, 0.07, 0.66 * _fade))
	var font := ThemeDB.fallback_font
	if not _over:
		_view.draw_string(font, Vector2(0, 168), "THE VEIL REALM: destroy the Rift Soul", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(0.9, 0.7, 1.0, _fade))
	var xf := _view.get_viewport().get_canvas_transform()
	var t := Time.get_ticks_msec() / 1000.0
	for s in souls:
		if not is_instance_valid(s) or s._dead:
			continue
		var p: Vector2 = xf * (s.global_position + Vector2(0, -30))
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		if Rect2(Vector2.ZERO, size).grow(-30).has_point(p):
			_view.draw_arc(p, 46.0 + pulse * 8.0, 0.0, TAU, 40, Color(0.85, 0.6, 1.0, 0.9 * _fade), 3.0)
			_view.draw_circle(p, 10.0, Color(1.0, 0.9, 1.0, 0.5 * _fade))
		else:
			# off screen: an arrow at the edge, towards it
			var c := size * 0.5
			var dir := (p - c).normalized()
			var edge := c + dir * minf(c.x / maxf(absf(dir.x), 0.01), c.y / maxf(absf(dir.y), 0.01)) * 0.9
			var side := dir.orthogonal()
			_view.draw_colored_polygon(PackedVector2Array([edge + dir * 22.0, edge - dir * 14.0 + side * 16.0, edge - dir * 14.0 - side * 16.0]),
				Color(0.9, 0.7, 1.0, (0.7 + 0.3 * pulse) * _fade))
