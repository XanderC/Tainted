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
## Archers keep between KEEP_AWAY and SHOOT_RANGE from the player and shoot when they have a clear line
var ranged := false
var _shot_cd := 1.0
const SHOOT_RANGE := 430.0
const KEEP_AWAY := 230.0
const SHOT_INTERVAL := 2.0
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

## Party play (Coop): every monster has an id the party's games share. In a follower's game it is
## `remote`: it doesn't think, it shows what the host's copy does (apply_snapshot), and hits on it go
## to the host (Coop.forward_*), which sends back its life and its death (remote_die).
var net_id := 0
var remote := false
var _net_pos := Vector2.ZERO
var _net_anim := ""
var _net_flags := 0

## Who it is going for: you, or your hireling when that is nearer (or taunted it). `target` stays
## you: it is who wakes it, gets the kill and is struck by its affixes.
var _foe: Node2D = null
var _foe_t := 0.0
var _taunter: Node2D = null
var _taunt_t := 0.0

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
	if has_affix("molten"):  # its burning ground, about it while it lives (each game draws its own)
		SpellFx.attach(self, "ground_fire", 1.0e9, MOLTEN_RADIUS * 2.0 / 180.0, 0.0, false, 0.85)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if remote:
		_remote_step(delta)
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

	if not _alive(target) and _players().is_empty():  # in a party it goes on after the others
		velocity = Vector2.ZERO
		rig.play_loop("Idle")
		return

	# Calculate current movement speed (slowed if chilled)
	var cur_speed := speed
	if _chill_t > 0.0:
		cur_speed *= 0.60

	_taunt_t = maxf(_taunt_t - delta, 0.0)
	_foe_t -= delta
	if _foe_t <= 0.0 or not _alive(_foe):
		_foe_t = 0.4
		_foe = _pick_foe()
	var to_player := _foe.global_position - global_position
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

	if ranged and _ranged_step(delta, to_player, cur_speed):
		return

	# In a maze, follow the grid path around walls; otherwise walk straight at its foe
	var goal := _foe.global_position
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
		_foe.take_damage(touch_damage)
		if has_affix("vampiric"):
			_heal(max_hp * 0.04)
		if _foe.thorns() > 0.0:
			take_damage(_foe.thorns())
		_touch_cd = 1.0
		rig.play_once("Slashing", 1.4)


## An archer in range with a clear line: hold or back off, and shoot. False when it should walk
## closer instead (too far, or a wall in the way).
func _ranged_step(delta: float, to_player: Vector2, cur_speed: float) -> bool:
	_shot_cd -= delta
	var d := to_player.length()
	var clear := maze == null or maze.line_clear(global_position + Vector2(0, -20), _foe.global_position + Vector2(0, -20))
	if d > SHOOT_RANGE or not clear:
		return false
	if d < KEEP_AWAY:
		velocity = -to_player.normalized() * cur_speed * 0.8  # back off
		move_and_slide()
		rig.play_loop("Walking")
	else:
		velocity = Vector2.ZERO
		rig.play_loop("Idle")
	if not rig.is_busy():
		rig.set_facing(to_player.x)
	if _shot_cd <= 0.0:
		_shot_cd = SHOT_INTERVAL * randf_range(0.85, 1.15)
		rig.play_once("Shooting", 1.3)
		get_tree().create_timer(0.35, false).timeout.connect(_loose_arrow)
	return true


func _loose_arrow() -> void:
	if _dead or not _alive(_foe) or get_parent() == null:
		return
	var a := EnemyArrow.new()
	a.texture = RigSprite.skin_parts(skin).get("Arrow")
	a.global_position = global_position + Vector2(0, -26 * size_mult)
	a.dir = (_foe.global_position + Vector2(0, -14) - a.global_position).normalized()
	a.damage = touch_damage
	a.target = _foe
	a.maze = maze
	get_parent().add_child(a)
	Coop.host_fx("arrow", {"id": net_id, "x": a.global_position.x, "y": a.global_position.y, "dx": a.dir.x, "dy": a.dir.y})


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
	if remote:
		Coop.forward_status(net_id, "stun", seconds)
		return
	_stun_t = maxf(_stun_t, seconds)


func apply_sunder(seconds: float) -> void:
	if remote:
		Coop.forward_status(net_id, "sunder", seconds)
		return
	_sunder_t = maxf(_sunder_t, seconds)


## Its foe: a hireling that taunted it, else whichever of you, your hireling and the other players in
## your party (RemotePlayer, in a party rift) is nearest (a hireling only when clearly nearer, so it
## doesn't flip between you).
func _pick_foe() -> Node2D:
	if _taunt_t > 0.0 and _alive(_taunter):
		return _taunter
	var best: Node2D = target if _alive(target) else null
	var best_d := best.global_position.distance_to(global_position) if best != null else INF
	for rp in get_tree().get_nodes_in_group("remote_players"):
		if _alive(rp):
			var d: float = rp.global_position.distance_to(global_position)
			if d < best_d:
				best = rp
				best_d = d
	var h: Hireling = Hirelings.node
	if _alive(h) and h.is_inside_tree() and h.global_position.distance_to(global_position) < best_d * 0.85:
		return h
	return best if best != null else target


## A foe that can still be fought (untyped: a player who left the party's rift is freed, and a typed
## argument would choke on it).
func _alive(n) -> bool:
	return is_instance_valid(n) and not n.dead


## A hireling's taunt: it comes for the hireling for a while, whoever is nearer.
func taunt(by: Node2D, seconds: float) -> void:
	if _dead:
		return
	if remote:
		Coop.forward_status(net_id, "taunt", seconds)  # the host has it go for your character
		return
	_taunter = by
	_taunt_t = maxf(_taunt_t, seconds)
	_foe = by
	wake()


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
	if remote:
		# The host's copy takes it; the number shows here straight away
		Coop.forward_hit(net_id, amount, crit, dtype, ailment)
		if _shield_t > 0.0:
			_spawn_text("Immune", Color(0.85, 0.85, 1.0))
		else:
			_spawn_number(amount * _resist(dtype), crit, dtype)
			_hit_spark(dtype)
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
	_hit_spark(dtype)

	# Ailment logic
	match ailment:
		"chill":
			_chill_t = 3.5
			SpellFx.attach(self, "flame_blue", 3.5, size_mult, 36.0 * size_mult, false, 0.85)
			if crit and not is_boss:
				_freeze_t = 1.2
		"burn":
			_burn_t = 3.0
			SpellFx.attach(self, "flame", 3.0, 0.55 * size_mult, -6.0, false, 0.85)
			_burn_dps = maxf(_burn_dps, final_dmg * 0.35)
		"shock":
			_shock_t = 4.0
			SpellFx.attach(self, "spark_loop", 4.0, size_mult, 30.0 * size_mult, false, 0.9)
		"poison":
			if _poison_t <= 0.0:
				SpellFx.spawn(get_parent(), "poison_burst", global_position + Vector2(0, -24), size_mult * 0.7)
			_poison_t = 3.0
			SpellFx.attach(self, "flame_green", 3.0, size_mult, -4.0, false, 0.85)
			_poison_dps = maxf(_poison_dps, final_dmg * 0.30)

	if dtype == RuneDef.DamageType.COLD and crit and not is_boss:
		_freeze_t = 1.2

	# Electrified: sparks jump to a player standing close (any player, in a party)
	if has_affix("electrified") and randf() < 0.3:
		var near := _players_near(global_position, 160.0)
		if not near.is_empty():
			var struck = near.pick_random()
			struck.take_damage(touch_damage * 0.5)
			_flash_ring(global_position, 160.0, Color(1.0, 0.95, 0.4))
			_sfx("lightning_strike", struck.global_position + Vector2(0, -40), 0.9)

	queue_redraw()
	if hp <= 0.0:
		_die()
	elif not is_boss and _stun_t <= 0.0 and _freeze_t <= 0.0 and not rig.is_busy():
		rig.play_once("Hurt", 1.6)


func _die() -> void:
	if not _dead and get_parent() != null:
		SpellFx.spawn(get_parent(), "blood_splat", global_position, size_mult)  # on the ground where it fell
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
	# The slam hits you, your hireling and the party alike
	for who in [target, Hirelings.node] + get_tree().get_nodes_in_group("remote_players"):
		if _alive(who) and who.global_position.distance_to(global_position) < SLAM_RADIUS:
			who.take_damage(touch_damage * 2.0)
	_sfx("ground_hit", global_position, SLAM_RADIUS / 140.0)
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


# ---------- party play: a follower's copy ----------

## What the host's copy is doing now, for the followers: [id, x, y, life, animation, facing, flags].
func snapshot() -> Array:
	var flags := 0
	for pair in [[_chill_t, 1], [_freeze_t, 2], [_burn_t, 4], [_shock_t, 8], [_poison_t, 16], [_stun_t, 32],
			[_slam_t, 64], [_shield_t, 128]]:
		if pair[0] > 0.0:
			flags |= int(pair[1])
	if _aggro:
		flags |= 256
	return [net_id, global_position.x, global_position.y, hp, rig.current_anim if rig != null else "",
		-1.0 if rig != null and rig._facing_left else 1.0, flags]


## The host's copy, as it is now (a follower's game).
func apply_snapshot(s: Array) -> void:
	_net_pos = Vector2(float(s[1]), float(s[2]))
	if absf(float(s[3]) - hp) > 0.01:
		hp = float(s[3])
		hp_changed.emit(hp, max_hp)
		queue_redraw()
	_net_anim = String(s[4])
	if rig != null:
		rig.set_facing(float(s[5]))
	_net_flags = int(s[6])
	_slam_t = SLAM_WINDUP * 0.5 if _net_flags & 64 else 0.0
	_shield_t = 1.0 if _net_flags & 128 else 0.0
	_aggro = (_net_flags & 256) != 0


## A follower's copy: glides to where the host's is, plays what it plays, tinted by its ailments.
func _remote_step(delta: float) -> void:
	if _net_pos == Vector2.ZERO:
		_net_pos = global_position
	if global_position.distance_to(_net_pos) > 300.0:
		global_position = _net_pos  # a teleport, or far behind
	else:
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-14.0 * delta))
	if _net_anim != "" and rig != null:
		if _net_anim in ["Walking", "Idle", "Idle Blinking", "Running"]:
			rig.play_loop(_net_anim)
		elif rig.current_anim != _net_anim and not rig.is_busy():
			rig.play_once(_net_anim, 1.3)
	var f := _net_flags
	rig.modulate = Color(0.4, 0.85, 1.0) if f & 2 else Color(0.65, 0.88, 1.0) if f & 1 else \
		Color(1.0, 0.5, 0.2) if f & 4 else Color(1.0, 0.95, 0.4) if f & 8 else Color(0.7, 0.3, 0.95) if f & 16 else \
		Color(1.0, 1.0, 0.5) if f & 32 else _tint
	if _slam_t > 0.0 or _shield_t > 0.0:
		queue_redraw()


## The host's copy died: so does this one (its XP and the kill count here, as for your own kills).
func remote_die() -> void:
	if not _dead:
		hp = 0.0
		_die()


## A follower's copy becomes the real one: its host left and this game hosts now (Coop).
func take_over(you: Player) -> void:
	remote = false
	target = you
	if _net_pos != Vector2.ZERO:
		global_position = _net_pos


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
	ranged = bool(k.get("ranged", false))
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


## Every player its effects can reach, still standing: you, and in a party rift or zone the others
## (RemotePlayer: their game takes what hits them). The host's game is the one that hurts them.
func _players() -> Array:
	return Enemy.players_of(get_tree(), target)


func _players_near(at: Vector2, radius: float) -> Array:
	return Enemy.players_near(get_tree(), target, at, radius)


## Static so a delayed blast can still find them after the monster that cast it is gone.
static func players_of(tree: SceneTree, you) -> Array:
	var out: Array = []
	if is_instance_valid(you) and not you.dead:
		out.append(you)
	for rp in tree.get_nodes_in_group("remote_players"):
		if is_instance_valid(rp) and not rp.dead:
			out.append(rp)
	return out


static func players_near(tree: SceneTree, you, at: Vector2, radius: float) -> Array:
	return players_of(tree, you).filter(func(p): return p.global_position.distance_to(at) < radius)


func _tick_affixes(delta: float, dist: float) -> void:
	_shield_t = maxf(_shield_t - delta, 0.0)
	if has_affix("regenerating") and hp < max_hp:
		hp = minf(hp + max_hp * 0.02 * delta, max_hp)
	if has_affix("molten"):
		for p in _players_near(global_position, MOLTEN_RADIUS):  # its burning ground, whoever stands in it
			p.take_damage(touch_damage * 0.6 * delta)
	if has_affix("shielding") and _ready_ability("shielding", 9.0, delta):
		_shield_t = 2.5
		_sfx_on("immunity", 2.5, size_mult, 36.0 * size_mult)  # it can't be hurt a while: the party sees it too
	var who: Node2D = _foe if _alive(_foe) else target  # who it's after: you, your hireling, another player
	if has_affix("teleporter") and dist > 220.0 and _alive(who) and _ready_ability("teleporter", 5.0, delta):
		var dest := who.global_position + Vector2.from_angle(randf() * TAU) * 110.0
		if maze != null:
			dest = maze.random_floor_near(who.global_position, 90.0, 160.0)
		_flash_ring(global_position, 50.0, Color(0.8, 0.5, 1.0))
		global_position = dest
		_flash_ring(global_position, 50.0, Color(0.8, 0.5, 1.0))
	if has_affix("frozen") and dist < 600.0 and _alive(who) and _ready_ability("frozen", 6.0, delta):
		_frost_orb(who.global_position)
		Coop.host_fx("frost_orb", {"id": net_id, "x": who.global_position.x, "y": who.global_position.y})
	if has_affix("summoner") and _ready_ability("summoner", 10.0, delta):
		_summon_minions()
	queue_redraw()


## Frozen: a frost orb lands under the player and bursts after a moment, hurting and slowing every
## player in it. `hurt` false: only its look (a party member's copy of the host's).
func _frost_orb(at: Vector2, hurt := true) -> void:
	var orb := Node2D.new()
	orb.z_index = -1
	get_parent().add_child(orb)
	orb.global_position = at
	var dmg := touch_damage * 1.5
	var tree := get_tree()
	var you = target
	orb.draw.connect(func():
		orb.draw_circle(Vector2.ZERO, FROST_ORB_RADIUS, Color(0.5, 0.85, 1.0, 0.18))
		orb.draw_arc(Vector2.ZERO, FROST_ORB_RADIUS, 0.0, TAU, 40, Color(0.6, 0.9, 1.0, 0.9), 3.0))
	orb.queue_redraw()
	var t := orb.create_tween()
	t.tween_interval(1.2)
	t.tween_callback(func():
		if hurt:
			for p in Enemy.players_near(tree, you, orb.global_position, FROST_ORB_RADIUS):
				p.take_damage(dmg)
				p.apply_slow(2.0)
		SpellFx.spawn(orb.get_parent(), "ice_burst", orb.global_position, FROST_ORB_RADIUS / 100.0)
		orb.queue_free())


## Molten: a delayed fiery blast where it died, hurting every player in it (the host's game does the
## hurting; a party member's copy only shows it).
func _molten_explosion() -> void:
	var at := global_position
	var dmg := touch_damage * 2.0
	var host := get_parent()
	var players: Array = [] if remote else _players()  # caught now: it's freed before the blast
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
		for p in players:
			if is_instance_valid(p) and not p.dead and p.global_position.distance_to(at) < 130.0:
				p.take_damage(dmg)
		SpellFx.spawn(host, "fire_explosion", at + Vector2(0, -40), 1.15)
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
		m.ranged = ranged
		minion_spawned.emit(m)  # the rift counts minions as normal kills
		get_parent().add_child(m)
		m.wake()
		_minions.append(m)
	_flash_ring(global_position, 80.0, Color(0.6, 0.85, 0.4))


## A hit's spark by its damage type (SpellFx.HITS), on it: not more often than every 90 ms.
func _hit_spark(dtype) -> void:
	var now := Time.get_ticks_msec()
	if now - _spark_at < 90 or get_parent() == null:
		return
	_spark_at = now
	SpellFx.spawn(get_parent(), SpellFx.HITS[clampi(int(dtype), 0, SpellFx.HITS.size() - 1)],
		global_position + Vector2(randf_range(-14.0, 14.0), -32.0 * size_mult + randf_range(-10.0, 10.0)), size_mult)


## One kept on it a while; the party sees it on their copy (Coop.host_fx "sfx_on").
func _sfx_on(id: String, secs: float, size := 1.0, lift := 0.0) -> void:
	SpellFx.attach(self, id, secs, size, lift)
	Coop.host_fx("sfx_on", {"id": net_id, "fx": id, "secs": secs, "s": size, "lift": lift})


## A spell effect here; the party sees it too (the host's monsters: Coop.host_fx).
func _sfx(id: String, at: Vector2, size := 1.0) -> void:
	SpellFx.spawn(get_parent(), id, at, size)
	Coop.host_fx("sfx", {"id": net_id, "fx": id, "x": at.x, "y": at.y, "s": size})


var _spark_at := 0


func _flash_ring(at: Vector2, radius: float, col: Color) -> void:
	Coop.host_fx("ring", {"id": net_id, "x": at.x, "y": at.y, "r": radius, "c": col.to_html()})  # the party sees it too
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
