class_name Enemy
extends CharacterBody2D

signal died(pos: Vector2)
signal hp_changed(hp: float, max_hp: float)

const TINT := Color(1.0, 0.86, 0.86)  # slight red so zombies read as hostile next to the player

var target: Player
var max_hp := 30.0
var hp := 30.0
var speed := 110.0
var touch_damage := 8.0
var rig: RigSprite
var is_boss := false
var size_mult := 1.0  # boss = 2.0
var display_name := "Zombie"
var kind := "zombie"  # MonsterKinds id (set_kind)
var skin := ""  # the character art (RigSprite.skin); "" = the rig's own zombie
## Maze rifts: path around walls via the maze, and wait until the player comes near.
var maze: MazeMap = null
var aggro_range := 0.0  # 0 = always hunting the player
var pack := ""          # monsters of one group share this; when one wakes, the pack wakes
var _aggro := false
var _path_t := 0.0
var _waypoint := Vector2.ZERO

## Elite / Legendary (MonsterAffix): tougher, with affixes. Set up with make_elite() before adding.
var tier := 0  # MonsterAffix.Tier
var affixes: Array[String] = []
var _ab_t := {}          # ability timers by affix id
var _shield_t := 0.0     # Shielding: immune while > 0
var _minions: Array = [] # Summoner

signal minion_spawned(m: Enemy)

var _touch_cd := 0.0
var _stun_t := 0.0
var _dead := false
var _shape: CollisionShape2D
var _slam_cd := 4.0
var _slam_t := 0.0  # > 0 while winding up the ground slam
var _tint := TINT

# Ailments and elemental statuses
var _chill_t := 0.0
var _freeze_t := 0.0
var _burn_t := 0.0
var _burn_dps := 0.0
var _burn_tick := 0.0
var _shock_t := 0.0
var _poison_t := 0.0
var _poison_dps := 0.0
var _poison_tick := 0.0
var _sunder_t := 0.0

const SLAM_WINDUP := 0.9
const SLAM_RADIUS := 150.0


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0 * size_mult
	_shape.shape = circle
	_shape.position = Vector2(0, -6)
	add_child(_shape)

	rig = RigSprite.new()
	rig.base_scale = 0.18 * size_mult
	rig.frame_skip = 2  # 30 fps is plenty for a crowd
	rig.skin = skin
	if skin != "":
		_tint = Color.WHITE  # the pack art reads as hostile on its own
	if is_boss and skin == "":
		_tint = Color(0.75, 0.55, 1.0)
	elif tier != MonsterAffix.Tier.NORMAL:
		_tint = Color(MonsterAffix.TIERS[tier].color).lerp(Color.WHITE, 0.55)
	rig.modulate = _tint
	add_child(rig)
	rig.play_loop("Walking")
	rig.randomize_phase()  # so a group doesn't march in lockstep


func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Handle status effect timers and DoTs
	_process_ailments(delta)
	if _dead:
		return

	if _slam_t > 0.0:
		_slam_t -= delta
		velocity = Vector2.ZERO
		queue_redraw()
		if _slam_t <= 0.0:
			_do_slam()
		return

	if _freeze_t > 0.0 or _stun_t > 0.0:
		velocity = Vector2.ZERO
		if _freeze_t > 0.0:
			rig.modulate = Color(0.5, 0.85, 1.0)
			rig.play_loop("Idle")
		else:
			rig.play_loop("Idle Blinking")
		return

	if not is_instance_valid(target) or target.dead:
		velocity = Vector2.ZERO
		rig.play_loop("Idle")
		return

	# Calculate current movement speed (slowed if chilled)
	var cur_speed := speed
	if _chill_t > 0.0:
		cur_speed *= 0.60

	var to_player := target.global_position - global_position
	if not _aggro:
		if aggro_range <= 0.0 or to_player.length() < aggro_range:
			wake()
		else:
			velocity = Vector2.ZERO
			rig.play_loop("Idle")
			return

	if tier != MonsterAffix.Tier.NORMAL:
		_tick_affixes(delta, to_player.length())
		if _dead:
			return

	# In a maze, follow the grid path around walls; otherwise walk straight at the player
	var goal := target.global_position
	if maze != null:
		_path_t -= delta
		if _path_t <= 0.0:
			_path_t = 0.35
			_waypoint = maze.path_next(global_position, goal)
		goal = _waypoint
	var move := goal - global_position
	velocity = move.normalized() * cur_speed if move.length() > 4.0 else Vector2.ZERO
	move_and_slide()
	if not rig.is_busy():
		rig.set_facing(move.x if absf(move.x) > 1.0 else to_player.x)
	rig.play_loop("Walking")

	_touch_cd -= delta
	if is_boss:
		_slam_cd -= delta
		if _slam_cd <= 0.0 and to_player.length() < SLAM_RADIUS * 1.6:
			_slam_cd = 5.0
			_slam_t = SLAM_WINDUP
			rig.play_once("Slashing", 0.9)
			return

	if to_player.length() < 46.0 * size_mult and _touch_cd <= 0.0:
		target.take_damage(touch_damage)
		if has_affix("vampiric"):
			_heal(max_hp * 0.04)
		if target.thorns() > 0.0:
			take_damage(target.thorns())
		_touch_cd = 1.0
		rig.play_once("Slashing", 1.4)


func _process_ailments(delta: float) -> void:
	if _stun_t > 0.0:
		_stun_t = maxf(_stun_t - delta, 0.0)

	if _freeze_t > 0.0:
		_freeze_t = maxf(_freeze_t - delta, 0.0)

	if _chill_t > 0.0:
		_chill_t = maxf(_chill_t - delta, 0.0)

	if _shock_t > 0.0:
		_shock_t = maxf(_shock_t - delta, 0.0)

	if _sunder_t > 0.0:
		_sunder_t = maxf(_sunder_t - delta, 0.0)

	# Burning DoT
	if _burn_t > 0.0:
		_burn_t = maxf(_burn_t - delta, 0.0)
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.5
			_apply_dot(_burn_dps * 0.5, RuneDef.DamageType.FIRE)

	# Poison / Chaos DoT
	if _poison_t > 0.0:
		_poison_t = maxf(_poison_t - delta, 0.0)
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = 0.5
			_apply_dot(_poison_dps * 0.5, RuneDef.DamageType.CHAOS)

	# Visual tint based on priority
	if _freeze_t > 0.0:
		rig.modulate = Color(0.4, 0.85, 1.0)
	elif _chill_t > 0.0:
		rig.modulate = Color(0.65, 0.88, 1.0)
	elif _burn_t > 0.0:
		rig.modulate = Color(1.0, 0.5, 0.2)
	elif _shock_t > 0.0:
		rig.modulate = Color(1.0, 0.95, 0.4)
	elif _poison_t > 0.0:
		rig.modulate = Color(0.7, 0.3, 0.95)
	elif _sunder_t > 0.0:
		rig.modulate = Color(1.0, 0.4, 0.4)
	elif _stun_t > 0.0:
		rig.modulate = Color(1.0, 1.0, 0.5)
	else:
		rig.modulate = _tint


func _apply_dot(amount: float, dtype: RuneDef.DamageType) -> void:
	if _dead:
		return
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(amount, false, dtype)
	queue_redraw()
	if hp <= 0.0:
		_die()


func stun(seconds: float) -> void:
	if _dead or is_boss:
		return
	_stun_t = maxf(_stun_t, seconds)


func apply_sunder(seconds: float) -> void:
	_sunder_t = maxf(_sunder_t, seconds)


## Start hunting the player, and wake the rest of the pack.
func wake() -> void:
	if _aggro:
		return
	_aggro = true
	_path_t = 0.0
	if pack != "":
		for e in get_tree().get_nodes_in_group(pack):
			if e != self and is_instance_valid(e):
				e.wake()


func take_damage(amount: float, crit: bool = false,
		dtype: RuneDef.DamageType = RuneDef.DamageType.PHYSICAL,
		ailment: String = "") -> void:
	if _dead:
		return
	wake()
	if _shield_t > 0.0:
		_spawn_text("Immune", Color(0.85, 0.85, 1.0))
		return

	# Shock and Sunder damage vulnerability multipliers
	var final_dmg := amount * _resist(dtype)
	if _shock_t > 0.0:
		final_dmg *= 1.25
	if _sunder_t > 0.0:
		final_dmg *= 1.35

	hp -= final_dmg
	hp_changed.emit(hp, max_hp)
	_spawn_number(final_dmg, crit, dtype)

	# Ailment logic
	match ailment:
		"chill":
			_chill_t = 3.5
			if crit and not is_boss:
				_freeze_t = 1.2
		"burn":
			_burn_t = 3.0
			_burn_dps = maxf(_burn_dps, final_dmg * 0.35)
		"shock":
			_shock_t = 4.0
		"poison":
			_poison_t = 3.0
			_poison_dps = maxf(_poison_dps, final_dmg * 0.30)

	if dtype == RuneDef.DamageType.COLD and crit and not is_boss:
		_freeze_t = 1.2

	# Electrified: sparks jump to an attacker standing close
	if has_affix("electrified") and randf() < 0.3 and is_instance_valid(target) \
			and target.global_position.distance_to(global_position) < 160.0:
		target.take_damage(touch_damage * 0.5)
		_flash_ring(global_position, 160.0, Color(1.0, 0.95, 0.4))

	queue_redraw()
	if hp <= 0.0:
		_die()
	elif not is_boss and _stun_t <= 0.0 and _freeze_t <= 0.0 and not rig.is_busy():
		rig.play_once("Hurt", 1.6)


func _die() -> void:
	_dead = true
	_slam_t = 0.0
	remove_from_group("enemies")
	_shape.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	died.emit(global_position)
	if is_instance_valid(target):
		target.on_enemy_killed(global_position)
	GameState.add_xp(max_hp * (0.6 if is_boss else 0.4))
	if has_affix("molten"):
		_molten_explosion()
	rig.modulate = _tint
	rig.play_once("Dying", 1.0, true)
	queue_redraw()
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(rig, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)


func _do_slam() -> void:
	queue_redraw()
	if is_instance_valid(target) and not target.dead \
			and target.global_position.distance_to(global_position) < SLAM_RADIUS:
		target.take_damage(touch_damage * 2.0)
	var ring := Node2D.new()
	get_parent().add_child(ring)
	ring.global_position = global_position
	ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, SLAM_RADIUS, 0.0, TAU, 48, Color(1, 0.5, 0.2, 0.9), 6.0))
	ring.queue_redraw()
	var t := ring.create_tween()
	t.tween_property(ring, "modulate:a", 0.0, 0.4)
	t.tween_callback(ring.queue_free)


func _spawn_number(amount: float, crit: bool, dtype: RuneDef.DamageType = RuneDef.DamageType.PHYSICAL) -> void:
	var l := Label.new()
	l.text = str(maxi(int(amount), 1)) + ("!" if crit else "")

	# Color code by damage type
	var col := Color.WHITE
	match dtype:
		RuneDef.DamageType.COLD:
			col = Color(0.4, 0.88, 1.0)
		RuneDef.DamageType.FIRE:
			col = Color(1.0, 0.52, 0.18)
		RuneDef.DamageType.LIGHTNING:
			col = Color(1.0, 0.95, 0.35)
		RuneDef.DamageType.CHAOS:
			col = Color(0.85, 0.35, 1.0)
		_:
			col = Color.WHITE

	if crit:
		col = Color(1.0, 0.85, 0.1)
		l.add_theme_font_size_override("font_size", 22)
	else:
		l.add_theme_font_size_override("font_size", 16)

	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.z_index = 10
	get_parent().add_child(l)
	l.position = global_position + Vector2(-12, -118 * size_mult)
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - 45.0, 0.65)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.65)
	t.tween_callback(l.queue_free)


func _draw() -> void:
	RigSprite.draw_shadow(self, 24.0 * size_mult)
	if _slam_t > 0.0:
		var k := 1.0 - _slam_t / SLAM_WINDUP
		draw_circle(Vector2.ZERO, SLAM_RADIUS, Color(1, 0.2, 0.1, 0.12))
		draw_circle(Vector2.ZERO, SLAM_RADIUS * k, Color(1, 0.2, 0.1, 0.28))
		draw_arc(Vector2.ZERO, SLAM_RADIUS, 0.0, TAU, 48, Color(1, 0.3, 0.1, 0.8), 3.0)
	if _dead or is_boss:
		return
	var top := -112.0 * size_mult
	if tier != MonsterAffix.Tier.NORMAL:
		var tc: Color = MonsterAffix.TIERS[tier].color
		# Glowing ring under elites, shield bubble, molten heat
		draw_arc(Vector2(0, 2), 30.0 * size_mult, 0.0, TAU, 40, Color(tc.r, tc.g, tc.b, 0.85), 4.0)
		if has_affix("molten"):
			draw_circle(Vector2.ZERO, MOLTEN_RADIUS, Color(1.0, 0.35, 0.05, 0.10))
		if _shield_t > 0.0:
			draw_circle(Vector2(0, -50 * size_mult), 55.0 * size_mult, Color(0.8, 0.85, 1.0, 0.25))
			draw_arc(Vector2(0, -50 * size_mult), 55.0 * size_mult, 0.0, TAU, 40, Color(0.9, 0.95, 1.0, 0.8), 3.0)
		# Name plate: name in tier colour, affixes underneath
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-120, top - 26), display_name, HORIZONTAL_ALIGNMENT_CENTER, 240, 15, 5, Color.BLACK)
		draw_string(font, Vector2(-120, top - 26), display_name, HORIZONTAL_ALIGNMENT_CENTER, 240, 15, tc)
		var names: Array = affixes.map(func(a): return MonsterAffix.AFFIXES[a].name)
		var line := "  ".join(PackedStringArray(names))
		draw_string_outline(font, Vector2(-120, top - 10), line, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, 4, Color.BLACK)
		draw_string(font, Vector2(-120, top - 10), line, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, Color(0.92, 0.88, 0.80))
		draw_rect(Rect2(-32, top, 64, 7), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-32, top, 64.0 * clampf(hp / max_hp, 0.0, 1.0), 7), tc.darkened(0.15))
		return
	draw_rect(Rect2(-18, top, 36, 5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-18, top, 36.0 * clampf(hp / max_hp, 0.0, 1.0), 5), Color(0.9, 0.15, 0.15))


# ---------- Elite / Legendary ----------

const MOLTEN_RADIUS := 90.0
const FROST_ORB_RADIUS := 110.0


## Turn this monster into an Elite or Legendary with the given affixes. Call before add_child.
func make_elite(new_tier: int, new_affixes: Array[String]) -> void:
	tier = new_tier
	affixes = new_affixes
	var t: Dictionary = MonsterAffix.TIERS[tier]
	max_hp *= float(t.hp)
	touch_damage *= float(t.damage)
	size_mult *= float(t.size)
	if has_affix("fast"):
		speed *= 1.5
	display_name = MonsterAffix.legendary_name() if tier == MonsterAffix.Tier.LEGENDARY else "Elite " + display_name


## Make this a monster of MonsterKinds `id`: its name, art and stat multipliers. Call after the
## base stats are set and before make_elite and adding it.
func set_kind(id: String) -> void:
	var k: Dictionary = MonsterKinds.KINDS.get(id, MonsterKinds.KINDS["zombie"])
	kind = id
	display_name = String(k["name"])
	skin = MonsterKinds.skin_for(id)
	max_hp *= float(k["hp"])
	speed *= float(k["speed"])
	touch_damage *= float(k["damage"])


func has_affix(id: String) -> bool:
	return affixes.has(id)


## Rift progress this kill is worth (elites and legendaries count for more).
func kill_weight() -> int:
	return int(MonsterAffix.TIERS[tier].weight) if tier != MonsterAffix.Tier.NORMAL else 1


func _resist(dtype: RuneDef.DamageType) -> float:
	match dtype:
		RuneDef.DamageType.PHYSICAL:
			return 0.6 if has_affix("armored") else 1.0
		RuneDef.DamageType.FIRE:
			return 0.3 if has_affix("fire_res") else 1.0
		RuneDef.DamageType.COLD:
			return 0.3 if has_affix("cold_res") else 1.0
		RuneDef.DamageType.LIGHTNING:
			return 0.3 if has_affix("lightning_res") else 1.0
		RuneDef.DamageType.CHAOS:
			return 0.3 if has_affix("poison_res") else 1.0
	return 1.0


func _heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
	queue_redraw()


## Ability countdown: true (and restarts at `every` seconds) when it fires.
func _ready_ability(id: String, every: float, delta: float) -> bool:
	_ab_t[id] = float(_ab_t.get(id, every * randf_range(0.4, 0.9))) - delta
	if _ab_t[id] <= 0.0:
		_ab_t[id] = every
		return true
	return false


func _tick_affixes(delta: float, dist: float) -> void:
	_shield_t = maxf(_shield_t - delta, 0.0)
	if has_affix("regenerating") and hp < max_hp:
		hp = minf(hp + max_hp * 0.02 * delta, max_hp)
	if has_affix("molten") and dist < MOLTEN_RADIUS:
		target.take_damage(touch_damage * 0.6 * delta)
	if has_affix("shielding") and _ready_ability("shielding", 9.0, delta):
		_shield_t = 2.5
	if has_affix("teleporter") and dist > 220.0 and _ready_ability("teleporter", 5.0, delta):
		var dest := target.global_position + Vector2.from_angle(randf() * TAU) * 110.0
		if maze != null:
			dest = maze.random_floor_near(target.global_position, 90.0, 160.0)
		_flash_ring(global_position, 50.0, Color(0.8, 0.5, 1.0))
		global_position = dest
		_flash_ring(global_position, 50.0, Color(0.8, 0.5, 1.0))
	if has_affix("frozen") and dist < 600.0 and _ready_ability("frozen", 6.0, delta):
		_frost_orb(target.global_position)
	if has_affix("summoner") and _ready_ability("summoner", 10.0, delta):
		_summon_minions()
	queue_redraw()


## Frozen: a frost orb lands under the player and bursts after a moment, hurting and slowing.
func _frost_orb(at: Vector2) -> void:
	var orb := Node2D.new()
	orb.z_index = -1
	get_parent().add_child(orb)
	orb.global_position = at
	var dmg := touch_damage * 1.5
	orb.draw.connect(func():
		orb.draw_circle(Vector2.ZERO, FROST_ORB_RADIUS, Color(0.5, 0.85, 1.0, 0.18))
		orb.draw_arc(Vector2.ZERO, FROST_ORB_RADIUS, 0.0, TAU, 40, Color(0.6, 0.9, 1.0, 0.9), 3.0))
	orb.queue_redraw()
	var t := orb.create_tween()
	t.tween_interval(1.2)
	t.tween_callback(func():
		if is_instance_valid(target) and not target.dead \
				and target.global_position.distance_to(orb.global_position) < FROST_ORB_RADIUS:
			target.take_damage(dmg)
			target.apply_slow(2.0)
		orb.queue_free())


## Molten: a delayed fiery blast where it died.
func _molten_explosion() -> void:
	var at := global_position
	var dmg := touch_damage * 2.0
	var host := get_parent()
	var warn := Node2D.new()
	warn.z_index = -1
	host.add_child(warn)
	warn.global_position = at
	warn.draw.connect(func():
		warn.draw_circle(Vector2.ZERO, 130.0, Color(1.0, 0.35, 0.05, 0.22))
		warn.draw_arc(Vector2.ZERO, 130.0, 0.0, TAU, 40, Color(1.0, 0.5, 0.1, 0.9), 3.0))
	warn.queue_redraw()
	var t := warn.create_tween()
	t.tween_interval(1.4)
	t.tween_callback(func():
		var p: Player = target
		if is_instance_valid(p) and not p.dead and p.global_position.distance_to(at) < 130.0:
			p.take_damage(dmg)
		warn.queue_free())


## Summoner: raise two zombies next to it (at most 6 of its minions alive).
func _summon_minions() -> void:
	_minions = _minions.filter(func(m): return is_instance_valid(m) and not m._dead)
	if _minions.size() >= 6:
		return
	var t: Dictionary = MonsterAffix.TIERS[tier]
	for i in 2:
		var m := Enemy.new()
		m.target = target
		m.maze = maze
		m.max_hp = max_hp / float(t.hp) * 0.6
		m.touch_damage = touch_damage / float(t.damage)
		m.speed = speed
		m.position = global_position + Vector2.from_angle(randf() * TAU) * 60.0
		m.kind = kind  # summoned minions are of its kind
		m.display_name = display_name.trim_prefix("Elite ")
		m.skin = MonsterKinds.skin_for(kind)
		minion_spawned.emit(m)  # the rift counts minions as normal kills
		get_parent().add_child(m)
		m.wake()
		_minions.append(m)
	_flash_ring(global_position, 80.0, Color(0.6, 0.85, 0.4))


func _flash_ring(at: Vector2, radius: float, col: Color) -> void:
	var ring := Node2D.new()
	get_parent().add_child(ring)
	ring.global_position = at
	ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, col, 5.0))
	ring.queue_redraw()
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)


func _spawn_text(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.z_index = 10
	get_parent().add_child(l)
	l.position = global_position + Vector2(-22, -118 * size_mult)
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - 30.0, 0.5)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)
