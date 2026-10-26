class_name Hireling
extends CharacterBody2D
## Your hireling in the world (Hirelings holds what it is; HirelingDB its type). It follows you,
## goes after enemies near you, and fights with its skill gems and their linked supports: melee
## types swing, strike and shout, archers keep their distance and shoot. Enemies attack it as well
## as you (Enemy picks the nearer). Its stats are its type's at its level plus the gear it wears.
## It drinks from its own two flasks (Hirelings.flask): a life flask when below half life, a
## utility flask as soon as it is fighting. When it falls it stays down: the Captain revives it.

const FLASK_LIFE_BELOW := 0.5  ## drinks a life flask below this share of its life

const FOLLOW_DIST := 110.0
const LEASH := 520.0       ## goes after enemies this close to you
const SEEK := 700.0        ## ... and this close to itself
const WARP := 1100.0       ## further from you than this, it catches up at once
const MELEE_REACH := 0.9   ## of a skill's radius
const KEEP_AWAY := 200.0   ## archers back off inside this
const BUFF_RANGE := 320.0  ## shouts and skins wait for enemies this close
const WHIRL_TIME := 2.0
const WHIRL_TICK := 0.25

var owner_player: Player
var stats := StatBlock.new()
var hp := 1.0
var dead := false
var rig: RigSprite
var skills: Array[SkillDef] = []
var _cd: Array[float] = []
var _facing := Vector2.RIGHT
var _ranged := false
var _busy := false         # mid-leap
var _whirl_t := 0.0
var _whirl_tick := 0.0
var _whirl_skill: SkillDef = null
var _buffs := {}           # source -> seconds left
var _swing_t := 0.0
var _swing := {}           # {dir, radius, arc, color} for the drawn arc
var _ring_t := 0.0
var _ring := {}            # {radius, color}
var _warped := false
var _flask_cd: Array[float] = [0.0, 0.0]
var _flask_cd_max: Array[float] = [1.0, 1.0]
## Flasks in effect: {slot, t, life_rate, source, mods: [[stat, mod, value]]}
var _flask_fx: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("hireling")
	# Walls stop it; nothing bumps into it (it never blocks you or the enemies)
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 15.0
	shape.shape = c
	shape.position = Vector2(0, -6)
	add_child(shape)
	rig = RigSprite.new()
	rig.base_scale = 0.2
	rig.weapon_from_gear = true
	var skin := String(GameState.hireling.get("skin", ""))
	if skin != "":
		rig.skin = skin
	add_child(rig)
	if skin == "":
		Appearance.apply(rig, GameState.hireling.get("look", Appearance.default_look()))
	refresh()
	hp = stats.get_stat("max_life")
	rig.play_loop("Idle")


## Its stats, skills and looks again (gear, supports or level changed). Keeps its share of life.
func refresh() -> void:
	var frac := hp / maxf(stats.get_stat("max_life"), 1.0) if stats.base.has("max_life") else 1.0
	stats = Hirelings.build_stats()
	for src in _buffs:
		_apply_buff(String(src))
	for fx in _flask_fx:
		for m in fx.mods:
			stats.add_mod(String(m[0]), int(m[1]), float(m[2]), fx.source)
	hp = clampf(stats.get_stat("max_life") * frac, 1.0, stats.get_stat("max_life"))
	_ranged = bool(Hirelings.type_def().get("ranged", false))
	skills.clear()
	_cd.clear()
	for i in Hirelings.skill_ids().size():
		var sk := Hirelings.skill_def(i)
		if sk != null:
			skills.append(sk)
			_cd.append(randf_range(0.5, 2.0) if i > 0 else 0.0)  # it doesn't open with everything at once
	_dress()
	Net.update_looks()  # others see its gear too


func on_level_up() -> void:
	refresh()
	hp = stats.get_stat("max_life")
	_float_text("Level %d!" % Hirelings.level(), Color(1.0, 0.85, 0.35))


## Its gear on the rig: a dressed figure wears it all; an archer holds the bow it has on.
func _dress() -> void:
	if rig == null:
		return
	if rig.skin == "":
		var w: ItemInstance = GameState.hireling_gear.get("weapon")
		var want := RigSprite.rig_for_weapon(w.base.id if w != null else "")
		if rig.rig_dir != want:  # a bow, a spear, a dagger, a weapon in both hands: its rig
			rig = RigSprite.swap_rig(rig, want)
			Appearance.apply(rig, GameState.hireling.get("look", Appearance.default_look()))
			rig.play_loop("Idle")
		Player.dress_rig(rig, GameState.hireling_gear)
		return
	var bow: ItemInstance = GameState.hireling_gear.get("weapon")
	var art := "res://assets/gear/weapon/%s/Bow.png" % Wardrobe.look_of(bow)  # in the look it has
	var parts := RigSprite.skin_parts(rig.skin).duplicate()  # its own look, holding the bow
	if bow != null and ResourceLoader.exists(art):
		parts["Bow"] = load(art)
	rig.set_part_overrides(parts)


# ---------- combat stats ----------

func take_damage(amount: float, _dtype := 0) -> void:
	if dead:
		return
	hp -= amount * 100.0 / (100.0 + stats.get_stat("armor"))
	if hp <= 0.0:
		_die()
	elif not rig.is_busy():
		rig.play_once("Hurt", 1.4)


## Nothing reflected back at attackers (Enemy asks every target).
func thorns() -> float:
	return 0.0


## A share of its life back.
func heal_fraction(f: float) -> void:
	if not dead:
		hp = minf(hp + stats.get_stat("max_life") * f, stats.get_stat("max_life"))


func _die() -> void:
	dead = true
	hp = 0.0
	velocity = Vector2.ZERO
	remove_from_group("hireling")
	Hirelings.on_died()
	rig.play_once("Dying", 1.0, true)
	_float_text("%s has fallen" % String(GameState.hireling.get("name", "")), Color(1.0, 0.45, 0.4))
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(self, "modulate:a", 0.0, 0.8)
	t.tween_callback(func():
		if Hirelings.node == self:
			Hirelings.node = null
		queue_free())


# ---------- thinking ----------

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(owner_player):
		return
	if not _warped or global_position.distance_to(owner_player.global_position) > WARP:
		_warp_to_owner()
	hp = minf(hp + stats.get_stat("life_regen") * delta, stats.get_stat("max_life"))
	for i in _cd.size():
		_cd[i] = maxf(_cd[i] - delta, 0.0)
	_tick_buffs(delta)
	_swing_t = maxf(_swing_t - delta, 0.0)
	_ring_t = maxf(_ring_t - delta, 0.0)
	queue_redraw()
	if _busy:
		return

	var foe: Enemy = null
	if owner_player.can_fight and not owner_player.dead:
		foe = _pick_target()
	_tick_flasks(delta, foe != null)
	if _whirl_t > 0.0:
		_whirl(delta, foe)
		return
	if foe == null:
		_follow()
		return
	if _ranged:
		_archer(foe)
	else:
		_melee(foe)


## Beside you: when it first arrives in a scene, and whenever you get far ahead (a leap, a portal).
func _warp_to_owner() -> void:
	_warped = true
	var spot := owner_player.global_position + Vector2(-70, 40)
	var maze := _maze()
	if maze != null and maze.is_wall(maze.world_to_cell(spot)):
		spot = owner_player.global_position
	global_position = spot


func _pick_target() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(owner_player.global_position) > LEASH:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d and d < SEEK:
			best_d = d
			best = e
	return best


func _follow() -> void:
	var goal := owner_player.global_position + Vector2(-FOLLOW_DIST * 0.6, FOLLOW_DIST * 0.35)
	if global_position.distance_to(goal) < 45.0:
		velocity = Vector2.ZERO
		if not rig.is_busy():
			rig.play_loop("Idle")
		return
	var far := global_position.distance_to(goal) > 260.0
	_walk_to(goal, stats.get_stat("move_speed") * (1.15 if far else 0.9))


## Melee: shouts and skins when enemies close in, other skills when they can land, and the main
## attack between them.
func _melee(foe: Enemy) -> void:
	var dist := global_position.distance_to(foe.global_position)
	for i in range(1, skills.size()):
		if _cd[i] <= 0.0 and _try_skill(i, foe, dist):
			return
	var attack := skills[0] if not skills.is_empty() else null
	var reach := (attack.get_effective_radius() if attack != null else 90.0) * MELEE_REACH
	if dist > reach:
		_walk_to(foe.global_position, stats.get_stat("move_speed"))
		return
	velocity = Vector2.ZERO
	_face(foe.global_position)
	if attack != null and _cd[0] <= 0.0:
		_cd[0] = 1.0 / maxf(stats.get_stat("attack_speed"), 0.2)
		_strike(attack, 0.0)
	elif not rig.is_busy():
		rig.play_loop("Idle")


## Archers: keep between KEEP_AWAY and their range with a clear line, shooting; skills when ready.
func _archer(foe: Enemy) -> void:
	var dist := global_position.distance_to(foe.global_position)
	var shot := skills[0] if not skills.is_empty() else null
	var rng := shot.max_range if shot != null and shot.max_range > 0.0 else 420.0
	var maze := _maze()
	var clear := maze == null or maze.line_clear(global_position + Vector2(0, -20), foe.global_position + Vector2(0, -20))
	if dist > rng or not clear:
		_walk_to(foe.global_position, stats.get_stat("move_speed"))
		return
	if dist < KEEP_AWAY:
		var away := (global_position - foe.global_position).normalized()
		velocity = away * stats.get_stat("move_speed") * 0.85
		move_and_slide()
		if not rig.is_busy():
			rig.play_loop("Running", 1.2)
		rig.set_facing(-away.x)
	else:
		velocity = Vector2.ZERO
	_face(foe.global_position)
	for i in range(1, skills.size()):
		if _cd[i] <= 0.0 and _try_skill(i, foe, dist):
			return
	if shot != null and _cd[0] <= 0.0:
		_cd[0] = 1.0 / maxf(stats.get_stat("attack_speed"), 0.2)
		rig.play_once("Shooting", 1.4)
		_loose(shot, (foe.global_position - global_position).normalized(), false)
	elif velocity == Vector2.ZERO and not rig.is_busy():
		rig.play_loop("Idle")


## Use skill i if it makes sense now. True if it did (and its cooldown started).
func _try_skill(i: int, foe: Enemy, dist: float) -> bool:
	var s := skills[i]
	var cd := maxf(s.get_effective_cooldown(Hirelings.skill_rank()), 0.4)
	var rad := s.get_effective_radius()
	match s.kind:
		SkillDef.Kind.BATTLE_CRY, SkillDef.Kind.IRON_SKIN:
			if dist > BUFF_RANGE:
				return false
			_shout(s)
		SkillDef.Kind.EARTHQUAKE:
			if dist > rad * 0.8:
				return false
			rig.play_once("Slashing", 1.1)
			_ring_fx(rad, s.get_effective_color(), 3.0)
			_spell("ground_hit", global_position, rad / 140.0)
			_spell("earth_fissure", global_position, rad / 160.0)
			_hit_area(global_position, _facing, rad, 360.0, s, s.stun if s.stun > 0.0 else 0.8)
		SkillDef.Kind.SHIELD_SLAM, SkillDef.Kind.SUNDERING_STRIKE, SkillDef.Kind.CLEAVE, SkillDef.Kind.FRENZY:
			if dist > rad * MELEE_REACH:
				return false
			_face(foe.global_position)
			_strike(s, s.stun)
			if s.kind == SkillDef.Kind.SHIELD_SLAM:
				_add_buff("shield_slam", s.duration)
		SkillDef.Kind.WHIRLWIND:
			if dist > rad:
				return false
			_whirl_skill = s
			_whirl_t = WHIRL_TIME
			_whirl_tick = 0.0
			cd = maxf(cd, 6.0)  # a channel: in bursts, not all the time
		SkillDef.Kind.LEAP_SLAM:
			if dist < 120.0 or dist > maxf(s.max_range, 200.0):
				return false
			_leap(s, foe.global_position)
		SkillDef.Kind.POWER_SHOT:
			rig.play_once("Shooting", 1.1)
			_loose(s, (foe.global_position - global_position).normalized(), true)
		SkillDef.Kind.MULTISHOT:
			rig.play_once("Shooting", 1.2)
			var base := (foe.global_position - global_position).angle()
			var spread := deg_to_rad(s.arc_degrees)
			for k in 5:
				_loose(s, Vector2.from_angle(base - spread * 0.5 + spread * k / 4.0), false)
		SkillDef.Kind.ARROW_RAIN:
			rig.play_once("Shooting", 0.9)
			_rain(s, foe.global_position)
		_:
			return false
	_cd[i] = cd
	return true


# ---------- its flasks ----------

## 1 just after drinking from flask slot i, down to 0 when it can drink again.
func flask_cooldown_fraction(i: int) -> float:
	return clampf(_flask_cd[i] / _flask_cd_max[i], 0.0, 1.0) if i >= 0 and i < _flask_cd.size() else 0.0


func _tick_flasks(delta: float, fighting: bool) -> void:
	for i in _flask_cd.size():
		_flask_cd[i] = maxf(_flask_cd[i] - delta, 0.0)
	var max_life := stats.get_stat("max_life")
	for fx in _flask_fx.duplicate():
		var step := minf(delta, float(fx.t))
		hp = minf(hp + float(fx.life_rate) * step, max_life)
		fx.t = float(fx.t) - delta
		if float(fx.t) <= 0.0:
			stats.remove_source(fx.source)
			_flask_fx.erase(fx)
	for i in Hirelings.FLASK_SLOTS:
		var it := Hirelings.flask(i)
		if it == null or _flask_cd[i] > 0.0 or _flask_fx.any(func(f): return int(f.slot) == i):
			continue
		var e := it.flask_effect()
		match String(e.kind):
			"life":
				var healing := _flask_fx.any(func(f): return float(f.life_rate) > 0.0)
				if hp < max_life * FLASK_LIFE_BELOW and not healing:
					_drink(i, e)
			"utility":
				if fighting:
					_drink(i, e)


func _drink(i: int, e: Dictionary) -> void:
	_flask_cd[i] = float(e.cooldown)
	_flask_cd_max[i] = maxf(float(e.cooldown), 0.01)
	var fx := {"slot": i, "t": float(e.duration), "life_rate": 0.0, "source": RefCounted.new(), "mods": []}
	if String(e.kind) == "life":
		var total: float = stats.get_stat("max_life") * float(e.amount)
		if e.instant:
			hp = minf(hp + total, stats.get_stat("max_life"))
		else:
			fx.life_rate = total / maxf(float(e.duration), 0.1)
	elif String(e.kind) == "utility":
		var b: Dictionary = e.buff
		fx.mods.append([String(b.stat), int(b.mod), float(b.value)])
	for d in e.during:
		fx.mods.append([String(d.stat), int(d.mod), float(d.value)])
	for m in fx.mods:
		stats.add_mod(String(m[0]), int(m[1]), float(m[2]), fx.source)
	_flask_fx.append(fx)
	rig.pulse(0.10, 0.3)


# ---------- doing ----------

## A swing: a cone (or circle) in front at the skill's radius.
func _strike(s: SkillDef, stun: float) -> void:
	rig.play_once("Slashing", maxf(1.0, 0.45 * stats.get_stat("attack_speed")))
	var arc := s.get_effective_arc()
	var rad := s.get_effective_radius()
	_swing = {"dir": _facing, "radius": rad, "arc": arc, "color": s.get_effective_color()}
	if arc < 359.0:
		SpellFx.slash(self, _facing, arc, rad, s.get_effective_color(), 0.22)  # the art's slash
	else:
		_swing_t = 0.15
	_hit_area(global_position, _facing, rad, arc, s, stun)
	if s.kind == SkillDef.Kind.SUNDERING_STRIKE:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.global_position.distance_to(global_position) < rad + 14.0:
				e.apply_sunder(5.0)


func _whirl(delta: float, foe: Enemy) -> void:
	_whirl_t -= delta
	_whirl_tick -= delta
	rig.play_loop("Slashing in The Air", 1.6)
	if foe != null:
		_walk_to(foe.global_position, stats.get_stat("move_speed") * 0.6, false)
	if _whirl_tick <= 0.0 and _whirl_skill != null:
		_whirl_tick = WHIRL_TICK
		var rad := _whirl_skill.get_effective_radius()
		_ring_fx(rad, _whirl_skill.get_effective_color(), 1.0)
		SpellFx.attach(self, "typhoon", WHIRL_TICK + 0.1, rad / 125.0, 10.0, false, 0.55)
		_hit_area(global_position, _facing, rad, 360.0, _whirl_skill, 0.0, 0.5)


func _leap(s: SkillDef, to: Vector2) -> void:
	_busy = true
	var land := to - (to - global_position).normalized() * 50.0
	var maze := _maze()
	if maze != null and maze.is_wall(maze.world_to_cell(land)):
		land = to
	_face(to)
	rig.play_once("Jump Loop", 1.0)
	var t := create_tween()
	t.tween_property(self, "global_position", land, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		_busy = false
		if dead:
			return
		rig.play_once("Slashing", 1.3)
		_ring_fx(s.get_effective_radius(), s.get_effective_color(), 2.0)
		_spell("ground_hit", global_position, s.get_effective_radius() / 140.0)
		_hit_area(global_position, _facing, s.get_effective_radius(), 360.0, s, s.stun))


## Shouts help you too (its war cries carry, Diablo II's auras); skins harden only itself.
func _shout(s: SkillDef) -> void:
	rig.pulse()
	_ring_fx(maxf(s.radius, 160.0), s.get_effective_color(), 3.0)
	SpellFx.attach(self, "earth_shield" if s.id in ["iron_skin", "ignore_pain", "colossus"] else "strength_buff",
		0.8, 1.0, 30.0, false, 0.9)
	match s.id:
		"iron_skin", "ignore_pain", "colossus":
			_add_buff("iron_skin", s.duration)
		"taunt", "threatening_shout":
			# Draws the monsters around onto itself for a while
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.global_position.distance_to(global_position) < maxf(s.radius, 180.0):
					e.taunt(self, s.duration * 0.5)
		_:
			_add_buff(s.id, s.duration)
			if is_instance_valid(owner_player) and s.id in ["battle_cry", "war_cry"]:
				owner_player.shout_buff(s.id, s.duration)


## Its own buffs as StatBlock mods (source = the buff's name), dropped when they run out.
func _add_buff(src: String, seconds: float) -> void:
	_buffs[src] = maxf(seconds, 1.0)
	_apply_buff(src)


func _apply_buff(src: String) -> void:
	stats.remove_source(src)
	match src:
		"battle_cry":
			stats.add_mod("damage", StatBlock.ModType.MORE, 0.30, src)
			stats.add_mod("crit_chance", StatBlock.ModType.FLAT, 0.15, src)
		"war_cry":
			stats.add_mod("armor", StatBlock.ModType.FLAT, 65.0, src)
			stats.add_mod("life_regen", StatBlock.ModType.FLAT, 4.0, src)
		"iron_skin":
			stats.add_mod("armor", StatBlock.ModType.FLAT, 90.0, src)
			stats.add_mod("life_regen", StatBlock.ModType.FLAT, 10.0, src)
		"shield_slam":
			stats.add_mod("armor", StatBlock.ModType.FLAT, 30.0, src)


func _tick_buffs(delta: float) -> void:
	for src in _buffs.keys():
		_buffs[src] = float(_buffs[src]) - delta
		if float(_buffs[src]) <= 0.0:
			_buffs.erase(src)
			stats.remove_source(src)


## Damage every enemy in a cone or circle: element, ailment, crits, stun, leech and echo from its
## supports, like your own skills. `dmg_scale` scales the hit (a whirlwind tick).
func _hit_area(origin: Vector2, dir: Vector2, radius: float, arc: float, s: SkillDef, stun := 0.0,
		dmg_scale := 1.0, is_echo := false) -> void:
	var half := deg_to_rad(arc) * 0.5
	var mult := s.get_effective_damage_mult(Hirelings.skill_rank()) * dmg_scale * (0.5 if is_echo else 1.0)
	var dealt := 0.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.global_position - origin
		if to.length() > radius + 14.0 or (arc < 359.0 and absf(dir.angle_to(to)) > half):
			continue
		dealt += _damage(e, s, mult)
		if stun > 0.0:
			e.stun(stun)
	_after_hits(s, dealt)
	if not is_echo and s.has_echo() and dealt > 0.0:
		get_tree().create_timer(0.24, false).timeout.connect(func():
			if is_instance_valid(self) and not dead:
				_hit_area(origin, dir, radius * 0.9, arc, s, 0.0, dmg_scale, true))


## One hit on one enemy; returns the damage dealt.
func _damage(e: Enemy, s: SkillDef, mult: float) -> float:
	var crit := randf() < stats.get_stat("crit_chance") + s.get_execute_bonus() * (1.0 if e.hp / e.max_hp < 0.35 else 0.0)
	var dmg := stats.get_stat("damage") * mult * (2.0 if crit else 1.0)
	e.take_damage(dmg, crit, s.get_effective_damage_type(), s.get_effective_ailment())
	return dmg


## Life leech from its supports.
func _after_hits(s: SkillDef, dealt: float) -> void:
	var leech := s.get_effective_leech()
	if leech > 0.0 and dealt > 0.0:
		hp = minf(hp + dealt * leech, stats.get_stat("max_life"))


## An arrow along `dir`: it stops at the first enemy, or with `pierce` flies through them all.
func _loose(s: SkillDef, dir: Vector2, pierce: bool) -> void:
	if get_parent() == null:
		return
	var a := HirelingArrow.new()
	a.texture = RigSprite.skin_parts(rig.skin).get("Arrow") if rig.skin != "" else null
	a.global_position = global_position + Vector2(0, -26)
	a.dir = dir
	a.pierce = pierce
	a.maze = _maze()
	a.color = s.get_effective_color()
	a.on_hit = func(e: Enemy) -> void:
		if is_instance_valid(self) and not dead and is_instance_valid(e):
			_after_hits(s, _damage(e, s, s.get_effective_damage_mult(Hirelings.skill_rank())))
	get_parent().add_child(a)


## Three volleys where the enemy stood, each hitting everything in the circle.
func _rain(s: SkillDef, at: Vector2) -> void:
	var rad := s.get_effective_radius()
	for k in 3:
		get_tree().create_timer(0.35 * k + 0.25, false).timeout.connect(func():
			if not is_instance_valid(self) or dead or get_parent() == null:
				return
			var fx := Node2D.new()
			fx.global_position = at
			fx.z_index = 4
			get_parent().add_child(fx)
			var col := s.get_effective_color()
			fx.draw.connect(func():
				fx.draw_circle(Vector2.ZERO, rad, Color(col.r, col.g, col.b, 0.18))
				fx.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 3.0)
				for j in 9:
					var p := Vector2.from_angle(j * 2.4) * rad * (0.25 + 0.08 * j)
					fx.draw_line(p + Vector2(-6, -24), p, Color(0.9, 0.85, 0.7), 2.0))
			fx.queue_redraw()
			var tw := fx.create_tween()
			tw.tween_property(fx, "modulate:a", 0.0, 0.35)
			tw.tween_callback(fx.queue_free)
			_hit_area(at, Vector2.RIGHT, rad, 360.0, s))


# ---------- moving ----------

func _maze() -> MazeMap:
	var scene := get_tree().current_scene
	return scene.get("maze") if scene != null else null


func _walk_to(goal: Vector2, spd: float, animate := true) -> void:
	var maze := _maze()
	var step := maze.path_next(global_position, goal) if maze != null else goal
	var move := step - global_position
	velocity = move.normalized() * spd if move.length() > 2.0 else Vector2.ZERO
	move_and_slide()
	if move.length() > 2.0:
		_facing = move.normalized()
		rig.set_facing(_facing.x)
	if animate and not rig.is_busy():
		rig.play_loop("Running", clampf(spd / 220.0, 0.8, 1.4))


func _face(at: Vector2) -> void:
	var d := at - global_position
	if d.length() > 1.0:
		_facing = d.normalized()
		rig.set_facing(_facing.x)


# ---------- drawing ----------

## A spell effect where it happens (SpellFx), beside the hireling.
func _spell(id: String, at: Vector2, size := 1.0) -> void:
	if get_parent() != null:
		SpellFx.spawn(get_parent(), id, at, size)


func _ring_fx(radius: float, col: Color, length := 1.0) -> void:
	_ring = {"radius": radius, "color": col}
	_ring_t = 0.15 * length


func _float_text(text: String, col: Color) -> void:
	if get_parent() == null:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.z_index = 10
	get_parent().add_child(l)
	l.position = global_position + Vector2(-60, -140)
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - 40.0, 1.2)
	t.parallel().tween_property(l, "modulate:a", 0.0, 1.2)
	t.tween_callback(l.queue_free)


func _draw() -> void:
	RigSprite.draw_shadow(self, 24.0)
	if dead:
		return
	draw_arc(Vector2(0, 2), 25.0, 0.0, TAU, 32, Color(0.45, 0.85, 0.55, 0.55), 2.5)
	if _buffs.has("iron_skin") or _buffs.has("war_cry"):
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, Color(0.7, 0.85, 1.0, 0.8), 3.5)
	if _buffs.has("battle_cry"):
		draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(1.0, 0.6, 0.2, 0.8), 3.5)
	if _swing_t > 0.0 and not _swing.is_empty():
		var a := _swing_t / 0.15
		var col: Color = _swing.color
		var arc: float = _swing.arc
		var rad: float = _swing.radius
		if arc >= 359.0:
			draw_arc(Vector2.ZERO, rad, 0.0, TAU, 36, Color(col.r, col.g, col.b, 0.8 * a), 3.0)
		else:
			var half := deg_to_rad(arc) * 0.5
			var start: float = (_swing.dir as Vector2).angle() - half
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				pts.append(Vector2.from_angle(start + half * 2.0 * i / 12.0) * rad)
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.32 * a))
	if _ring_t > 0.0 and not _ring.is_empty():
		var rc: Color = _ring.color
		draw_arc(Vector2.ZERO, float(_ring.radius), 0.0, TAU, 48, Color(rc.r, rc.g, rc.b, clampf(_ring_t * 4.0, 0.0, 1.0)), 5.0)
	# Name and life over its head
	var font := ThemeDB.fallback_font
	var nm := String(GameState.hireling.get("name", ""))
	draw_string_outline(font, Vector2(-60, -124), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color.BLACK)
	draw_string(font, Vector2(-60, -124), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.6, 0.95, 0.65))
	draw_rect(Rect2(-22, -116, 44, 5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-22, -116, 44.0 * clampf(hp / maxf(stats.get_stat("max_life"), 1.0), 0.0, 1.0), 5), Color(0.35, 0.85, 0.4))
