class_name Player
extends CharacterBody2D

signal died
signal item_picked(item: ItemInstance)
signal item_dropped(item: ItemInstance)
signal inventory_changed

const SWING_TIME := 0.15
## The bag is a grid: gear takes several cells (ItemBase.bag_size), so what fits depends on shape.
const BAG_COLS := 12  # like Path of Exile: 12 x 5
const BAG_ROWS := 5
const BAG_SIZE := BAG_COLS * BAG_ROWS  # cells
const SLOTS := ["weapon", "offhand", "helmet", "chest", "gloves", "boots", "ring", "ring2", "amulet", "belt"]  # two ring slots
## Flask slots, Path of Exile style: the belt opens some of them (ItemBase.flask_slots); without
## one there is NO_BELT_FLASKS. Flasks in slots beyond that stay put but can't be drunk.
const FLASK_SLOTS := 5
const NO_BELT_FLASKS := 1
const FLASK_KEYS := [KEY_Q, KEY_E, KEY_R, KEY_T, KEY_F]
## Slots that change how the character looks (see RigSprite.GEAR_LAYERS).
const VISIBLE_SLOTS := ["weapon", "helmet", "chest", "gloves", "boots"]
## Slots that belong to a weapon set. Only the active set is in `equipment` (and gives stats);
## the other set waits in `alt_set` until swap_weapon_set().
const SET_SLOTS := ["weapon", "offhand"]
const SWAP_COOLDOWN := 0.5
const ATTACK_ANIMS := ["Slashing", "Run Slashing", "Slashing in The Air"]
const HIT_DELAY := 0.12  # seconds into the swing animation when the blow lands

var class_def: ClassDef  # the Adventurer (ClassLibrary): starting stats and Adrenaline's rules
var stats := StatBlock.new()
var hp := 100.0
## Two pools: Adrenaline (`resource`, Strength skills: built by their basic attacks and by being hit,
## fading away; class_def.power_*) and Mana (Dexterity and Energy skills: regenerates; max_mana).
var resource := 0.0
var mana := 0.0
const MANA_BASE := 40.0
const MANA_REGEN := 0.03  ## of maximum Mana per second
const WARD_TAKEN := 0.6  ## Arcane Ward: what's left of a hit
var _ward_t := 0.0
var flasks: Array = [null, null, null, null, null]  # ItemInstance or null, FLASK_SLOTS long
var _flask_cd: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _flask_cd_max: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
## Flasks in effect: {source, t, life_rate, power_rate, warding}. Their buffs are StatBlock mods
## under `source`, removed when t runs out.
var _flask_effects: Array[Dictionary] = []
var active_set := 0  # 0 = Set 1, 1 = Set 2
var alt_set := {}    # inactive weapon set: slot -> ItemInstance
var _swap_cd := 0.0
var _hit_power_cd := 0.0  # flat resource-on-hit at most every 0.5s
var _slow_t := 0.0  # Frozen elites: move 40% slower while > 0
var dead := false
var bag := ItemGrid.new(BAG_COLS, BAG_ROWS)
## What is in the bag, in reading order. Read-only: change the bag through `bag` and the bag
## functions below, which emit inventory_changed.
var inventory: Array[ItemInstance]:
	get:
		return bag.items()
var equipment := {}  # slot -> ItemInstance
## Worn gear whose attribute requirements aren't met (Attributes): it stays on but gives nothing.
var _inactive := {}  # ItemInstance -> true
var item_powers := {}  # Legendary powers + set bonuses of the worn gear (UniqueItems.powers_of)
var joystick: VirtualJoystick
# walk_to(): walking on your own to a spot, e.g. an item whose label was tapped
var _walking := false
var _walk_target := Vector2.ZERO
var _walk_reach := 0.0
var _walk_time := 0.0
var _walk_arrive: Callable
var rig: RigSprite
var can_fight := true  # false in town

var skills: Array[SkillDef] = []
var facing := Vector2.RIGHT

var _cooldowns: Array[float] = []
var _mouse_attack_down := false
var _whirlwind_t := 0.0
var _hurt_cd := 0.0
var _busy := false  # true while leaping

# Buffs
var _buff_active := false
var _buff_t := 0.0
var _iron_skin_active := false
var _iron_skin_t := 0.0
var _frenzy_stacks := 0
var _frenzy_t := 0.0
var _shield_slam_buff_t := 0.0
var _shared_buffs := {}  # your hireling's war cries on you: buff id -> seconds left

# Drawing FX
var _swing_t := 0.0
var _swing_dir := Vector2.RIGHT
var _swing_arc := 120.0
var _swing_radius := 100.0
var _swing_color := Color.WHITE
var _ring_t := 0.0
var _ring_radius := 100.0
var _ring_color := Color.WHITE


func _ready() -> void:
	GameState.leveled_up.connect(_on_leveled_up)  # a burst of stars
	if class_def == null:
		class_def = ClassLibrary.adventurer()
	add_to_group("player")
	for k in class_def.base_stats:
		stats.set_base(String(k), class_def.base_stats[k])

	hp = stats.get_stat("max_life")
	resource = class_def.power_start
	mana = MANA_BASE

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	shape.position = Vector2(0, -6)
	add_child(shape)

	rig = RigSprite.new()
	rig.base_scale = 0.2
	rig.weapon_from_gear = true  # weapon appears when equipped, not only during slashes
	add_child(rig)
	Appearance.apply(rig, GameState.appearance)
	_sync_gear_visuals()
	GameState.attach_player(self)  # restore saved gear, bag and skills
	Hirelings.spawn(self)  # your hireling comes along, if you have one standing


func sync_skills_from_state() -> void:
	_apply_passives()
	skills.clear()
	_cooldowns.clear()
	var equipped: Array[SkillDef] = GameState.get_equipped_skills()
	for s in equipped:
		skills.append(s)
		_cooldowns.append(0.0)


func _unhandled_input(event: InputEvent) -> void:
	# Desktop key bindings: Space/J for Main Attack, 1-3 for Skills
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_J: use_skill(0)
			KEY_1: use_skill(1)
			KEY_2: use_skill(2)
			KEY_3: use_skill(3)
			KEY_4: use_skill(4)
			KEY_5: use_skill(5)
			KEY_X: swap_weapon_set()
			_:
				var fi := FLASK_KEYS.find(event.keycode)
				if fi != -1:
					use_flask(fi)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not OS.has_feature("mobile") and not DisplayServer.is_touchscreen_available():
			if event.pressed:
				_mouse_attack_down = true
				if can_fight and not dead and not _busy:
					var mpos := get_global_mouse_position()
					facing = (mpos - global_position).normalized()
					rig.set_facing(facing.x)
					use_skill(0)
			else:
				_mouse_attack_down = false


func _physics_process(delta: float) -> void:
	if dead:
		return

	hp = minf(hp + stats.get_stat("life_regen") * delta, stats.get_stat("max_life"))
	var decay := 0.0 if passive("no_decay") > 0.0 and class_def.power_decay > 0.0 else class_def.power_decay
	resource = clampf(resource - decay * delta, 0.0, max_resource())
	mana = clampf(mana + mana_regen() * delta, 0.0, max_mana())
	_ward_t = maxf(_ward_t - delta, 0.0)
	for i in _cooldowns.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
	_swing_t = maxf(_swing_t - delta, 0.0)
	_ring_t = maxf(_ring_t - delta, 0.0)
	_whirlwind_t = maxf(_whirlwind_t - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	_process_flasks(delta)
	_swap_cd = maxf(_swap_cd - delta, 0.0)
	_slow_t = maxf(_slow_t - delta, 0.0)
	_hit_power_cd = maxf(_hit_power_cd - delta, 0.0)

	_process_buffs(delta)
	queue_redraw()

	# Desktop continuous keys hold (Space/J for Main Attack, 1-3 for Skills / Channeling); not while
	# typing in the chat
	if can_fight and not dead and not _busy and not Net.chat_typing:
		if _mouse_attack_down and (not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or OS.has_feature("mobile")):
			_mouse_attack_down = false
		if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_J):
			use_skill(0)
		elif _mouse_attack_down:
			var mpos := get_global_mouse_position()
			facing = (mpos - global_position).normalized()
			rig.set_facing(facing.x)
			use_skill(0)

		if Input.is_key_pressed(KEY_1):
			use_skill(1)
		elif Input.is_key_pressed(KEY_2):
			use_skill(2)
		elif Input.is_key_pressed(KEY_3):
			use_skill(3)
		elif Input.is_key_pressed(KEY_4):
			use_skill(4)
		elif Input.is_key_pressed(KEY_5):
			use_skill(5)

	if _busy:
		return

	var dir := Vector2.ZERO
	if joystick:
		dir = joystick.output
	if dir == Vector2.ZERO and not Net.chat_typing:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")  # keyboard for desktop testing
	dir = _walk_step(dir, delta)
	velocity = dir * stats.get_stat("move_speed") * (0.6 if _slow_t > 0.0 else 1.0)
	move_and_slide()
	if dir.length() > 0.1:
		facing = dir.normalized()

	# Stand / walk / run / whirlwind animation
	var cur_speed := velocity.length()
	if not rig.is_busy():
		rig.set_facing(facing.x)
	if _whirlwind_t > 0.0:
		var as_hz := stats.get_stat("attack_speed")
		rig.play_loop("Slashing in The Air", maxf(1.4, 0.7 * as_hz))
	elif cur_speed < 25.0:
		rig.play_loop("Idle")
	elif cur_speed < stats.get_stat("move_speed") * 0.6:
		rig.play_loop("Walking", clampf(cur_speed / 110.0, 0.6, 1.3))
	else:
		rig.play_loop("Running", clampf(cur_speed / 220.0, 0.8, 1.4))


func _process_buffs(delta: float) -> void:
	if _buff_active:
		_buff_t -= delta
		if _buff_t <= 0.0:
			_buff_active = false
			stats.remove_source("battle_cry")

	if _iron_skin_active:
		_iron_skin_t -= delta
		if _iron_skin_t <= 0.0:
			_iron_skin_active = false
			stats.remove_source("iron_skin")

	if _shield_slam_buff_t > 0.0:
		_shield_slam_buff_t -= delta
		if _shield_slam_buff_t <= 0.0:
			stats.remove_source("shield_slam")

	if _frenzy_stacks > 0:
		_frenzy_t -= delta
		if _frenzy_t <= 0.0:
			_frenzy_stacks = 0
			stats.remove_source("frenzy")

	for id in _shared_buffs.keys():
		_shared_buffs[id] = float(_shared_buffs[id]) - delta
		if float(_shared_buffs[id]) <= 0.0:
			_shared_buffs.erase(id)
			stats.remove_source("hireling_" + String(id))


## Your hireling's war cry reaches you too (Diablo II's mercenary auras): Battle Cry's damage and
## critical chance, or War Cry's armour, for `seconds`.
func shout_buff(id: String, seconds: float) -> void:
	var src := "hireling_" + id
	stats.remove_source(src)
	match id:
		"battle_cry":
			stats.add_mod("damage", StatBlock.ModType.MORE, 0.15, src)
			stats.add_mod("crit_chance", StatBlock.ModType.FLAT, 0.05, src)
		"war_cry":
			stats.add_mod("armor", StatBlock.ModType.FLAT, 35.0, src)
		_:
			return
	_shared_buffs[id] = seconds



func _nearest_enemy(within: float):
	var best = null
	var best_d := within
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Damage every enemy inside a cone or full circle, handling element, runes, crits and leech.
func _hit_area(origin: Vector2, dir: Vector2, hit_radius: float, arc_deg: float,
		skill: SkillDef, stun_dur := 0.0, is_echo := false) -> void:
	var half := deg_to_rad(arc_deg) * 0.5
	var dtype := skill.get_effective_damage_type()
	var ailment := skill.get_effective_ailment()
	var leech := skill.get_effective_leech() + passive("leech")
	var exec_bonus := skill.get_execute_bonus()
	var rank := GameState.get_skill_rank(skill.id)
	var mult := skill.get_effective_damage_mult(rank) * (0.50 if is_echo else 1.0)

	var total_dealt := 0.0
	var hits := 0

	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.global_position - origin
		if to.length() > hit_radius + 14.0:
			continue
		if arc_deg < 359.0 and absf(dir.angle_to(to)) > half:
			continue

		var crit_chance := stats.get_stat("crit_chance") if passive("no_crit") <= 0.0 else 0.0
		if exec_bonus > 0.0 and e.hp / e.max_hp < 0.35:
			crit_chance += exec_bonus
		var crit := randf() < crit_chance

		var dmg := damage_for(skill) * mult * (2.0 if crit else 1.0)
		if e.hp / e.max_hp < 0.40:
			dmg *= 1.0 + passive("execute")
		e.take_damage(dmg, crit, dtype, ailment)
		total_dealt += dmg
		hits += 1

		if stun_dur > 0.0:
			e.stun(stun_dur)

		if skill.kind == SkillDef.Kind.SUNDERING_STRIKE:
			e.apply_sunder(5.0)

	# Generator skills build resource when they connect
	if not is_echo and skill.resource_gain > 0.0 and hits > 0:
		gain_resource(skill.get_effective_gain() + 2.0 * float(mini(hits, 5) - 1))

	# Life Leech Rune
	if leech > 0.0 and total_dealt > 0.0:
		var heal := total_dealt * leech
		hp = minf(hp + heal, stats.get_stat("max_life"))

	# Echo Rune aftershock
	if not is_echo and skill.has_echo():
		var t := create_tween()
		t.tween_interval(0.24)
		t.tween_callback(func():
			if is_instance_valid(self):
				_show_ring(hit_radius * 0.9, skill.get_effective_color(), SWING_TIME)
				_hit_area(origin, dir, hit_radius, arc_deg, skill, 0.0, true)
		)


# ---------- Skills Execution ----------

func use_skill(i: int) -> void:
	if dead or _busy or not can_fight or i < 0 or i >= skills.size():
		return
	if _cooldowns[i] > 0.0:
		return
	var s := skills[i]
	if s == null:  # empty action-bar slot
		return
	if skill_block_reason(s) != "":  # its weapon, or not enough of its attribute
		return
	var rank := GameState.get_skill_rank(s.id)
	var base_cd := s.get_effective_cooldown(rank)
	var cd := base_cd
	var cost := skill_cost(s)
	if base_cd <= 0.0 and s.kind == SkillDef.Kind.WHIRLWIND:
		# Rapid channeled hits (every ~0.20s scaled with attack speed); cost is per second
		cd = 0.20 / maxf(stats.get_stat("attack_speed"), 0.5)
		cost = skill_cost(s) * cd
	elif base_cd <= 0.0:
		cd = 1.0 / maxf(stats.get_stat("attack_speed"), 0.1)
	if cost > _pool(s):
		return
	_spend(s, cost)
	_cooldowns[i] = cd
	if s.get_on_use_gain() > 0.0:
		_gain_for(s, s.get_on_use_gain())
	if s.get_on_use_heal() > 0.0:
		hp = minf(hp + stats.get_stat("max_life") * s.get_on_use_heal(), stats.get_stat("max_life"))

	match s.kind:
		SkillDef.Kind.WHIRLWIND:
			_do_whirlwind(s)
		SkillDef.Kind.LEAP_SLAM:
			_do_leap_slam(s)
		SkillDef.Kind.BATTLE_CRY:
			_do_battle_cry(s)
		SkillDef.Kind.SHIELD_SLAM:
			_do_shield_slam(s)
		SkillDef.Kind.EARTHQUAKE:
			_do_earthquake(s)
		SkillDef.Kind.IRON_SKIN:
			_do_iron_skin(s)
		SkillDef.Kind.FRENZY:
			_do_frenzy(s)
		SkillDef.Kind.SUNDERING_STRIKE:
			_do_sundering_strike(s)
		SkillDef.Kind.BLADE_VORTEX:
			_do_blade_vortex(s)
		SkillDef.Kind.BATTLE_STANDARD:
			_do_battle_standard(s)
		SkillDef.Kind.CALL_ANCIENTS:
			_do_call_ancients(s)
		SkillDef.Kind.CLEAVE:
			_do_cleave_skill(s)
		SkillDef.Kind.SHOT:
			_play_shoot()
			_shoot(s, _aim(s.max_range), false, "arrow")
		SkillDef.Kind.POWER_SHOT:
			_play_shoot()
			_shoot(s, _aim(s.max_range), true, "arrow")
		SkillDef.Kind.MULTISHOT:
			_play_shoot()
			var base := _aim(s.max_range).angle()
			var spread := deg_to_rad(s.get_effective_arc() if s.get_effective_arc() < 359.0 else 40.0)
			for k in 5:
				_shoot(s, Vector2.from_angle(base - spread * 0.5 + spread * k / 4.0), false, "arrow")
		SkillDef.Kind.ARROW_RAIN:
			_play_shoot()
			_do_arrow_rain(s)
		SkillDef.Kind.DASH:
			_do_dash(s)
		SkillDef.Kind.KNIFE_FAN:
			_do_knife_fan(s)
		SkillDef.Kind.BOLT:
			_play_cast()
			_shoot(s, _aim(s.max_range), false, "orb")
		SkillDef.Kind.NOVA:
			_do_nova(s)
		SkillDef.Kind.ARC:
			_do_arc(s)
		SkillDef.Kind.METEOR:
			_do_meteor(s)
		SkillDef.Kind.WARD:
			_do_ward(s)
		SkillDef.Kind.HOLY_NOVA:
			_do_holy_nova(s)
		SkillDef.Kind.SMITE:
			_do_smite(s)


## "" if skill `s` can be used now as far as you go: what's in your hand (a bow, or a melee weapon)
## and whether you have enough of its attributes. Otherwise why not.
func skill_block_reason(s: SkillDef) -> String:
	if s == null:
		return "No skill"
	var wt := main_weapon_type()
	match s.weapon:
		"bow":
			if wt != "bow":
				return "Needs a bow"
		"melee":
			if wt == "bow":
				return "Needs a melee weapon"
	if s.hireling_only or s.for_hireling:
		return ""
	return GameState.gem_attr_block_reason(s.id)


## The kind of weapon in your main hand ("" for none, or one that doesn't meet its requirements).
func main_weapon_type() -> String:
	var w: ItemInstance = equipment.get("weapon")
	return w.base.weapon_type if w != null and gear_active(w) else ""


# ---------- damage: attacks by Strength, spells by Energy ----------

## What a hit of skill `s` starts from: your damage, scaled by Strength and attack damage for an
## attack (and bow damage for a bow's), or by Energy and spell damage for a spell.
func damage_for(s: SkillDef) -> float:
	return stats.get_stat("damage") * (spell_mult() if s != null and s.is_spell else attack_mult(s))


func attack_mult(s: SkillDef = null) -> float:
	var m := 1.0 + Attributes.ATTACK_PER_STR * GameState.attribute_bonus("str") + passive("attack_inc")
	if s != null and s.weapon == "bow":
		m += passive("bow_inc")
	return maxf(m, 0.1)


func spell_mult() -> float:
	return maxf(1.0 + Attributes.SPELL_PER_ENE * GameState.attribute_bonus("ene") + passive("spell_inc"), 0.1)


## One hit of skill `s` on enemy `e` (an arrow, a bolt, a strike of lightning), `scale` of the skill's
## damage: crits, execute, element and ailment (or `dtype` / `ailment` instead), leech. The damage dealt.
func _hit_one(e: Enemy, s: SkillDef, scale := 1.0, dtype := -1, ailment := "-") -> float:
	if not is_instance_valid(e) or e._dead:
		return 0.0
	var crit_chance := stats.get_stat("crit_chance") if passive("no_crit") <= 0.0 else 0.0
	if s.get_execute_bonus() > 0.0 and e.hp / e.max_hp < 0.35:
		crit_chance += s.get_execute_bonus()
	var crit := randf() < crit_chance
	var dmg := damage_for(s) * s.get_effective_damage_mult(GameState.get_skill_rank(s.id)) * scale * (2.0 if crit else 1.0)
	if e.hp / e.max_hp < 0.40:
		dmg *= 1.0 + passive("execute")
	e.take_damage(dmg, crit, s.get_effective_damage_type() if dtype < 0 else dtype,
		s.get_effective_ailment() if ailment == "-" else ailment)
	var leech := s.get_effective_leech() + passive("leech")
	if leech > 0.0:
		hp = minf(hp + dmg * leech, stats.get_stat("max_life"))
	return dmg


# ---------- Dexterity and Energy skills ----------

## Where to aim: the nearest enemy in `reach`, else the way you face.
func _aim(reach: float) -> Vector2:
	var target = _nearest_enemy(maxf(reach, 200.0))
	if target != null:
		facing = (target.global_position - global_position).normalized()
		rig.set_facing(facing.x)
	return facing


func _play_shoot() -> void:
	rig.play_once("Slashing" if rig.rig_dir == RigSprite.ARCHER_RIG else "Throwing", maxf(1.2, 0.5 * stats.get_stat("attack_speed")))


func _play_cast() -> void:
	rig.play_once("Throwing", maxf(1.2, 0.5 * stats.get_stat("attack_speed")))


## A projectile of skill `s` along `dir`: an arrow, a bolt of fire ("orb": it bursts where it hits)
## or a knife; the party sees it fly.
func _shoot(s: SkillDef, dir: Vector2, pierce: bool, style: String, reach := 0.0) -> void:
	if get_parent() == null:
		return
	var a := HirelingArrow.new()
	a.global_position = global_position + Vector2(0, -26)
	a.dir = dir
	a.pierce = pierce
	a.style = style
	a.maze = _maze()
	a.color = s.get_effective_color()
	if style == "orb":
		a.speed = 560.0
	a.life = clampf((reach if reach > 0.0 else maxf(s.max_range, 400.0)) / a.speed, 0.2, 1.5)
	a.on_hit = func(e: Enemy) -> void:
		if not is_instance_valid(self) or not is_instance_valid(e):
			return
		if s.kind == SkillDef.Kind.BOLT:  # bursts: everything near where it hit
			_sfx("fire_explosion" if s.get_effective_damage_type() == RuneDef.DamageType.FIRE else "hit_" + _element_name(s),
				e.global_position + Vector2(0, -16), s.get_effective_radius() / 90.0)
			_hit_area(e.global_position, Vector2.RIGHT, s.get_effective_radius(), 360.0, s)
		else:
			_hit_one(e, s)
	get_parent().add_child(a)
	Coop.player_fx(["proj", snappedf(a.global_position.x, 0.1), snappedf(a.global_position.y, 0.1), snappedf(dir.angle(), 0.001),
		a.color.to_html(false), pierce, style, snappedf(a.speed * a.life, 1.0)])


## "fire", "cold", "lightning" or "physical" for a skill's element (its SpellFx).
func _element_name(s: SkillDef) -> String:
	match s.get_effective_damage_type():
		RuneDef.DamageType.FIRE: return "fire"
		RuneDef.DamageType.COLD: return "cold"
		RuneDef.DamageType.LIGHTNING: return "lightning"
	return "physical"


func _maze() -> MazeMap:
	var scene := get_tree().current_scene if is_inside_tree() else null
	var m = scene.get("maze") if scene != null else null
	return m if m is MazeMap else null


## Arrow Rain: three volleys where the nearest enemy stands, each hitting everything in the circle.
func _do_arrow_rain(s: SkillDef) -> void:
	var target = _nearest_enemy(s.max_range)
	var at: Vector2 = target.global_position if target != null else global_position + facing * 220.0
	var rad := s.get_effective_radius()
	var col := s.get_effective_color()
	Coop.player_fx(["ground", at.x, at.y, rad, col.to_html(false), 1.2])
	for k in 3:
		get_tree().create_timer(0.3 * k + 0.25, false).timeout.connect(func():
			if not is_instance_valid(self) or dead or get_parent() == null:
				return
			var fx := Node2D.new()
			fx.global_position = at
			fx.z_index = 4
			get_parent().add_child(fx)
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


## Shadow Step: dash through the nearest enemy, cutting everything along the way.
func _do_dash(s: SkillDef) -> void:
	var dir := _aim(s.max_range + 80.0)
	var dist := s.max_range
	var target = _nearest_enemy(s.max_range + 80.0)
	if target != null:
		dist = minf(global_position.distance_to(target.global_position) + 70.0, s.max_range)
	var from := global_position
	var to := from + dir * dist
	var m := _maze()
	if m != null:  # stop short of a wall
		var step := 0.0
		while step < dist and not m.is_wall(m.world_to_cell(from + dir * (step + 20.0))):
			step += 20.0
		to = from + dir * step
	rig.play_once("Sliding", 1.6)
	_busy = true
	velocity = Vector2.ZERO
	_sfx("slash_lightning" if s.get_effective_damage_type() == RuneDef.DamageType.LIGHTNING else "slash_chaos", from.lerp(to, 0.5) + Vector2(0, -26),
		dist / 160.0, dir.x < 0.0)
	var t := create_tween()
	t.tween_property(self, "global_position", to, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		_busy = false
		var rad := s.get_effective_radius()
		for e in get_tree().get_nodes_in_group("enemies"):
			var p: Vector2 = e.global_position
			var along := clampf((p - from).dot(dir), 0.0, from.distance_to(to))
			if p.distance_to(from + dir * along) < rad + 14.0 * e.size_mult:
				_hit_one(e, s))


## Fan of Knives (Death Blossom: three waves): knives thrown out all round.
func _do_knife_fan(s: SkillDef) -> void:
	_play_cast()
	var waves := 3 if s.cluster == "ultimate" else 1
	for w in waves:
		get_tree().create_timer(0.22 * w + 0.01, false).timeout.connect(func():
			if not is_instance_valid(self) or dead:
				return
			for k in 10:
				_shoot(s, Vector2.from_angle(TAU * k / 10.0 + w * 0.3), false, "knife", s.max_range))


## Frost Nova: a burst all round you.
func _do_nova(s: SkillDef) -> void:
	_play_cast()
	var rad := s.get_effective_radius()
	_show_ring(rad, s.get_effective_color(), SWING_TIME * 2.0)
	var fx: String = {"cold": "ice_burst", "fire": "fire_explosion", "lightning": "lightning_strike"}.get(_element_name(s), "ground_hit")
	_sfx(fx, global_position, rad / 150.0)
	_hit_area(global_position, facing, rad, 360.0, s)


## Arc: lightning strikes the nearest enemies one after another (Thunderstorm: again and again).
func _do_arc(s: SkillDef) -> void:
	_play_cast()
	var storm := s.cluster == "ultimate"
	var strikes := 12 if storm else 3
	var gap := (s.duration / strikes) if storm else 0.07
	var picked := _nearest_enemies(s.max_range, strikes if not storm else 99)
	for k in strikes:
		get_tree().create_timer(gap * k + 0.01, false).timeout.connect(func():
			if not is_instance_valid(self) or dead:
				return
			var e = null
			if storm:
				var near := _nearest_enemies(s.max_range, 4)
				e = near.pick_random() if not near.is_empty() else null
			elif k < picked.size():
				e = picked[k]
			if is_instance_valid(e) and not e._dead:
				_sfx("lightning_strike", e.global_position + Vector2(0, -40), 0.9)
				_hit_one(e, s))


## The `n` nearest enemies within `reach`, nearest first.
func _nearest_enemies(reach: float, n: int) -> Array:
	var list := get_tree().get_nodes_in_group("enemies").filter(func(e):
		return not e._dead and global_position.distance_to(e.global_position) <= reach)
	list.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return list.slice(0, n)


## Meteor: a shadow grows where the enemies are, then the meteor crashes there.
func _do_meteor(s: SkillDef) -> void:
	_play_cast()
	var target = _nearest_enemy(s.max_range)
	var at: Vector2 = target.global_position if target != null else global_position + facing * 220.0
	var rad := s.get_effective_radius()
	var col := s.get_effective_color()
	Coop.player_fx(["ground", at.x, at.y, rad, col.to_html(false), 0.8])
	var mark := Node2D.new()
	mark.global_position = at
	mark.z_index = -1
	get_parent().add_child(mark)
	mark.draw.connect(func():
		mark.draw_circle(Vector2.ZERO, rad, Color(0, 0, 0, 0.25))
		mark.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 3.0))
	mark.scale = Vector2.ONE * 0.2
	var tw := mark.create_tween()
	tw.tween_property(mark, "scale", Vector2.ONE, 0.8)
	tw.tween_callback(func():
		mark.queue_free()
		if not is_instance_valid(self):
			return
		_sfx("fire_explosion", at, rad / 80.0)
		_hit_area(at, Vector2.RIGHT, rad, 360.0, s))


## Arcane Ward: for a while a part of each hit is taken by the ward (take_damage).
func _do_ward(s: SkillDef) -> void:
	_play_cast()
	_ward_t = s.duration
	_sfx_on("lightning_shield", s.duration, 1.0, 42.0, true, 0.55)


## Holy Nova: heals you and burns what's near.
func _do_holy_nova(s: SkillDef) -> void:
	_play_cast()
	hp = minf(hp + stats.get_stat("max_life") * 0.15, stats.get_stat("max_life"))
	var rad := s.get_effective_radius()
	_show_ring(rad, s.get_effective_color(), SWING_TIME * 2.5)
	_sfx_on("revival", 1.0, 1.2, 30.0)
	_hit_area(global_position, facing, rad, 360.0, s)


## Smite: a melee blow, and lightning strikes up to three of what it hit.
func _do_smite(s: SkillDef) -> void:
	var target = _nearest_enemy(s.get_effective_radius() + 30.0)
	if target != null:
		facing = (target.global_position - global_position).normalized()
		rig.set_facing(facing.x)
	rig.play_once("Slashing", maxf(1.0, 0.42 * stats.get_stat("attack_speed")))
	var rad := s.get_effective_radius()
	var arc := s.get_effective_arc()
	var struck := get_tree().get_nodes_in_group("enemies").filter(func(e):
		var to: Vector2 = e.global_position - global_position
		return not e._dead and to.length() <= rad + 14.0 and (arc >= 359.0 or absf(facing.angle_to(to)) <= deg_to_rad(arc) * 0.5))
	_show_swing(facing, arc, rad, s.get_effective_color(), SWING_TIME, s.get_effective_damage_type())
	_hit_area(global_position, facing, rad, arc, s)
	for e in struck.slice(0, 3):
		if is_instance_valid(e) and not e._dead:
			_sfx("lightning_strike", e.global_position + Vector2(0, -40), 0.8)
			_hit_one(e, s, 0.6, RuneDef.DamageType.LIGHTNING, "shock")


# ---------- flasks ----------

## How many flask slots can be drunk from: what the belt opens, or NO_BELT_FLASKS without one.
func flask_slot_count() -> int:
	var belt: ItemInstance = equipment.get("belt")
	var n := belt.base.flask_slots if belt != null and belt.base.flask_slots > 0 else NO_BELT_FLASKS
	return clampi(n, 1, FLASK_SLOTS)


## Drink the flask in slot i. False if the slot is empty, closed (belt) or on cooldown.
func use_flask(i: int) -> bool:
	if dead or i < 0 or i >= flask_slot_count():
		return false
	var it: ItemInstance = flasks[i]
	if it == null or _flask_cd[i] > 0.0:
		return false
	var e := it.flask_effect()
	_flask_cd[i] = float(e.cooldown)
	_flask_cd_max[i] = maxf(float(e.cooldown), 0.01)
	var source := RefCounted.new()
	var fx := {"source": source, "t": float(e.duration), "life_rate": 0.0, "power_rate": 0.0, "warding": bool(e.warding)}
	match String(e.kind):
		"life":
			var total: float = stats.get_stat("max_life") * float(e.amount)
			if e.instant:
				hp = minf(hp + total, stats.get_stat("max_life"))
			else:
				fx.life_rate = total / maxf(float(e.duration), 0.1)
		"power":  # Mana
			if e.instant:
				gain_mana(float(e.amount))
			else:
				fx.power_rate = float(e.amount) / maxf(float(e.duration), 0.1)
		"utility":
			var b: Dictionary = e.buff
			stats.add_mod(String(b.stat), int(b.mod), float(b.value), source)
	for d in e.during:
		stats.add_mod(String(d.stat), int(d.mod), float(d.value), source)
	if fx.warding:
		_slow_t = 0.0
	_flask_effects.append(fx)
	if rig != null:
		rig.pulse(0.10, 0.3)
	match String(e.kind):  # life rises green, power cyan
		"life": _sfx_on("life_recovery", 0.85, 1.0, 30.0)
		"power": _sfx_on("mana_recovery", 0.85, 1.0, 30.0)
	return true


## 1 just after drinking, down to 0 when slot i can be drunk again.
func flask_cooldown_fraction(i: int) -> float:
	return clampf(_flask_cd[i] / _flask_cd_max[i], 0.0, 1.0)


func _process_flasks(delta: float) -> void:
	for i in FLASK_SLOTS:
		_flask_cd[i] = maxf(_flask_cd[i] - delta, 0.0)
	var max_life := stats.get_stat("max_life")
	for fx in _flask_effects.duplicate():
		var step := minf(delta, float(fx.t))
		if float(fx.life_rate) > 0.0:
			hp = minf(hp + float(fx.life_rate) * step, max_life)
		if float(fx.power_rate) > 0.0:
			gain_mana(float(fx.power_rate) * step)
		fx.t = float(fx.t) - delta
		if float(fx.t) <= 0.0:
			stats.remove_source(fx.source)
			_flask_effects.erase(fx)


## A Warding flask in effect: slows don't take hold.
func slow_immune() -> bool:
	return _flask_effects.any(func(fx): return bool(fx.warding))


func is_worn(item: ItemInstance) -> bool:
	return item != null and (equipment.values().has(item) or flasks.has(item))


## Put a flask from the bag (or the ground) into flask slot i. What was there goes into the bag,
## where the new one was if it fits; a flask already in another slot swaps with it.
func equip_flask(item: ItemInstance, i: int) -> bool:
	if item == null or not item.is_flask() or i < 0 or i >= FLASK_SLOTS:
		return false
	var j := flasks.find(item)
	if j == i:
		return true
	if j != -1:
		flasks[j] = flasks[i]
		flasks[i] = item
		inventory_changed.emit()
		return true
	var old: ItemInstance = flasks[i]
	var at := bag.position_of(item)
	if old != null:
		var trial := bag.duplicate_grid()
		trial.remove(item)
		var spot := at if at != ItemGrid.NONE and trial.fits(old, at) else trial.find_free(old)
		if spot == ItemGrid.NONE:
			return false
		bag.remove(item)
		bag.place(old, spot)
	else:
		bag.remove(item)
	flasks[i] = item
	inventory_changed.emit()
	return true


## The first open, empty flask slot, or -1.
func free_flask_slot() -> int:
	for i in flask_slot_count():
		if flasks[i] == null:
			return i
	return -1


## Whether the flask in slot i could be dropped at `at` in the bag: into space, or swapping with a
## single flask there.
func can_unequip_flask_to(i: int, at: Vector2i) -> bool:
	var it: ItemInstance = flasks[i] if i >= 0 and i < FLASK_SLOTS else null
	if it == null:
		return false
	var plan := bag.plan_drop(it, at, null)
	if plan.is_empty():
		return false
	var b: ItemInstance = plan.get("swap")
	return b == null or b.is_flask()


func unequip_flask_to(i: int, at: Vector2i) -> bool:
	if not can_unequip_flask_to(i, at):
		return false
	var it: ItemInstance = flasks[i]
	var b: ItemInstance = bag.plan_drop(it, at, null).get("swap")
	if b != null:
		bag.remove(b)
	flasks[i] = b
	bag.place(it, at)
	inventory_changed.emit()
	return true


## Take the flask in slot i off into the first space in the bag it fits.
func unequip_flask(i: int) -> bool:
	var it: ItemInstance = flasks[i] if i >= 0 and i < FLASK_SLOTS else null
	if it == null:
		return false
	var at := bag.find_free(it)
	return at != ItemGrid.NONE and unequip_flask_to(i, at)


## Switch between weapon Set 1 and Set 2: the worn main / off hand go into the inactive set and
## the other set's weapons come out (only the active set counts for stats).
func swap_weapon_set() -> bool:
	if dead or (_swap_cd > 0.0 and not get_tree().paused):  # no cooldown while in the menu
		return false
	var old_max := stats.get_stat("max_life")
	var outgoing := {}
	for s in SET_SLOTS:
		if equipment.has(s):
			outgoing[s] = equipment[s]
			equipment[s].remove_from(stats)
			equipment.erase(s)
	for s in alt_set:
		equipment[s] = alt_set[s]
		alt_set[s].apply_to(stats)
	alt_set = outgoing
	active_set = 1 - active_set
	var new_max := stats.get_stat("max_life")
	hp = clampf(hp * new_max / maxf(old_max, 1.0), 1.0, new_max)
	_swap_cd = SWAP_COOLDOWN
	_sync_gear_visuals()
	inventory_changed.emit()
	return true


# ---------- passives (PassiveTree nodes, see GameState.passive_value) ----------

## Total of a passive stat key over the allocated passive tree nodes.
func passive(key: String) -> float:
	return GameState.passive_value(key)


func _apply_passives() -> void:
	var old_max := stats.get_stat("max_life")
	stats.remove_source("passives")
	var mods := [
		["armor", StatBlock.ModType.INCREASED, passive("armor_inc")],
		["max_life", StatBlock.ModType.FLAT, passive("life_flat")],
		["max_life", StatBlock.ModType.INCREASED, passive("life_inc")],
		["move_speed", StatBlock.ModType.INCREASED, passive("move_inc")],
		["crit_chance", StatBlock.ModType.FLAT, passive("crit")],
		["damage", StatBlock.ModType.INCREASED, passive("damage_inc")],
		["attack_speed", StatBlock.ModType.INCREASED, passive("attack_speed_inc")],
		["life_regen", StatBlock.ModType.FLAT, passive("regen")],
	]
	for m in mods:
		if m[2] != 0.0:
			stats.add_mod(m[0], m[1], m[2], "passives")
	Attributes.apply(stats, GameState.attribute_bonuses(), "attributes")
	var new_max := stats.get_stat("max_life")
	hp = clampf(hp + maxf(new_max - old_max, 0.0), 0.0, new_max)


## Retaliation: damage reflected to an enemy that hits you.
func thorns() -> float:
	return passive("thorns")


## Rampage: a slain enemy bursts, hurting others nearby.
func on_enemy_killed(pos: Vector2) -> void:
	var pct := passive("rampage")
	if pct <= 0.0:
		return
	var dmg := stats.get_stat("damage") * pct
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) < 110.0:
			e.call_deferred("take_damage", dmg)


func apply_slow(seconds: float) -> void:
	if slow_immune():
		return
	if _slow_t <= 0.0:
		_sfx_on("debuff", minf(seconds, 2.0), 1.0, 30.0, false, 0.8)  # cursed: slowed
	_slow_t = maxf(_slow_t, seconds)


## Maximum Adrenaline: the base plus passives.
func max_resource() -> float:
	return class_def.power_max + passive("power_max")


## Maximum Mana: a base, Energy and passives.
func max_mana() -> float:
	return maxf(MANA_BASE + Attributes.MANA_PER_ENE * GameState.attribute_bonus("ene") + passive("mana_max"), 0.0)


func mana_regen() -> float:
	return max_mana() * MANA_REGEN * maxf(1.0 + passive("mana_regen_inc"), 0.0)


## Attribute points were added or taken back: their bonuses, and which gear now meets its requirements.
func refresh_attributes() -> void:
	_sync_gear_visuals()
	resource = minf(resource, max_resource())
	mana = minf(mana, max_mana())


## What a skill costs to use: base cost x linked supports' multipliers, less passive reductions.
func skill_cost(s: SkillDef) -> float:
	return s.get_effective_cost() * maxf(1.0 - passive("cost_red"), 0.2)


func gain_resource(amount: float) -> void:
	resource = minf(resource + amount, max_resource())


func gain_mana(amount: float) -> void:
	mana = minf(mana + amount, max_mana())


## Blood Magic (a keystone): Mana skills cost life instead.
func blood_magic() -> bool:
	return passive("blood_magic") > 0.0


## What skill `s` can spend: Adrenaline for a Strength skill, Mana (or with Blood Magic life, keeping
## one) for the others.
func _pool(s: SkillDef) -> float:
	if not s.uses_mana():
		return resource
	return hp - 1.0 if blood_magic() else mana


func _spend(s: SkillDef, amount: float) -> void:
	if not s.uses_mana():
		resource -= amount
	elif blood_magic():
		hp -= amount
	else:
		mana -= amount


func _gain_for(s: SkillDef, amount: float) -> void:
	if s.uses_mana():
		gain_mana(amount)
	else:
		gain_resource(amount)


## True when skill i has enough resource to be used (ignores cooldown).
func can_afford(i: int) -> bool:
	if i < 0 or i >= skills.size():
		return false
	var s := skills[i]
	if s == null:
		return false
	if s.kind == SkillDef.Kind.WHIRLWIND and s.get_effective_cooldown(GameState.get_skill_rank(s.id)) <= 0.0:
		return _pool(s) >= skill_cost(s) * 0.2
	return _pool(s) >= skill_cost(s)


## True when skill i could be used if it weren't cooling down: its weapon, attributes and cost.
func can_use(i: int) -> bool:
	return i >= 0 and i < skills.size() and skills[i] != null and skill_block_reason(skills[i]) == "" and can_afford(i)


func cooldown_fraction(i: int) -> float:
	if i < 0 or i >= skills.size() or skills[i] == null:
		return 0.0
	var rank := GameState.get_skill_rank(skills[i].id)
	var max_cd := skills[i].get_effective_cooldown(rank)
	if max_cd <= 0.0:
		if skills[i].kind == SkillDef.Kind.WHIRLWIND:
			max_cd = 0.20 / maxf(stats.get_stat("attack_speed"), 0.5)
		else:
			max_cd = 1.0 / maxf(stats.get_stat("attack_speed"), 0.1)
	if max_cd <= 0.0:
		return 0.0
	return clampf(_cooldowns[i] / max_cd, 0.0, 1.0)


func _do_whirlwind(s: SkillDef) -> void:
	_show_spin(s.get_effective_radius(), s.get_effective_color())
	var as_hz := stats.get_stat("attack_speed")
	rig.play_loop("Slashing in The Air", maxf(1.4, 0.7 * as_hz))
	_hit_area(global_position, facing, s.get_effective_radius(), 360.0, s)


func _do_leap_slam(s: SkillDef) -> void:
	var dir := facing
	var dist := s.max_range
	var target = _nearest_enemy(s.max_range + 120.0)
	if target != null:
		var to: Vector2 = target.global_position - global_position
		dir = to.normalized()
		dist = minf(to.length(), s.max_range)
	facing = dir
	rig.set_facing(dir.x)
	rig.play_once("Jump Loop", 1.0)
	_busy = true
	velocity = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "global_position", global_position + dir * dist, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		_busy = false
		_show_ring(s.get_effective_radius(), s.get_effective_color(), SWING_TIME * 2.0)
		_sfx("ground_hit", global_position, s.get_effective_radius() / 140.0)
		rig.play_once("Slashing", 1.3)
		_hit_area(global_position, facing, s.get_effective_radius(), 360.0, s, s.stun)
	)


func _do_battle_cry(s: SkillDef) -> void:
	if _buff_active:
		stats.remove_source("battle_cry")
	stats.add_mod("damage", StatBlock.ModType.MORE, 0.30, "battle_cry")
	stats.add_mod("crit_chance", StatBlock.ModType.FLAT, 0.15, "battle_cry")
	stats.add_mod("armor", StatBlock.ModType.FLAT, 35.0, "battle_cry")
	_buff_active = true
	_buff_t = s.duration
	rig.pulse()
	_show_ring(180.0, s.get_effective_color(), 0.4)
	_sfx_on("strength_buff", 0.8, 1.0, 30.0, false, 0.95)


func _do_shield_slam(s: SkillDef) -> void:
	# Quick bash forward
	facing = facing.normalized()
	velocity = facing * 180.0
	rig.play_once("Slashing", 1.5)
	_show_swing(facing, s.get_effective_arc(), s.get_effective_radius(), s.get_effective_color(), SWING_TIME * 1.5, s.get_effective_damage_type())
	_hit_area(global_position, facing, s.get_effective_radius(), s.get_effective_arc(), s, s.stun)

	# Fortify buff
	if _shield_slam_buff_t > 0.0:
		stats.remove_source("shield_slam")
	stats.add_mod("armor", StatBlock.ModType.FLAT, 30.0, "shield_slam")
	_shield_slam_buff_t = s.duration


func _do_earthquake(s: SkillDef) -> void:
	rig.play_once("Slashing", 1.1)
	_show_ring(s.get_effective_radius(), s.get_effective_color(), SWING_TIME * 3.0)
	_hit_area(global_position, facing, s.get_effective_radius(), 360.0, s, 0.8)
	_sfx("ground_hit", global_position, s.get_effective_radius() / 140.0)
	_sfx("earth_fissure", global_position, s.get_effective_radius() / 160.0)

	# Lingering fractured ground zone
	var zone := Node2D.new()
	zone.global_position = global_position
	get_parent().add_child(zone)
	var z_col := s.get_effective_color()
	var z_rad := s.get_effective_radius()
	Coop.player_fx(["ground", zone.global_position.x, zone.global_position.y, z_rad, z_col.to_html(false), s.duration])
	zone.draw.connect(func():
		zone.draw_circle(Vector2.ZERO, z_rad, Color(z_col.r, z_col.g, z_col.b, 0.15))
		zone.draw_arc(Vector2.ZERO, z_rad, 0.0, TAU, 36, Color(z_col.r, z_col.g, z_col.b, 0.6), 3.0)
	)
	zone.queue_redraw()
	var t := zone.create_tween()
	t.tween_interval(s.duration)
	t.tween_property(zone, "modulate:a", 0.0, 0.4)
	t.tween_callback(zone.queue_free)


func _do_iron_skin(s: SkillDef) -> void:
	if _iron_skin_active:
		stats.remove_source("iron_skin")
	stats.add_mod("armor", StatBlock.ModType.FLAT, 90.0, "iron_skin")
	stats.add_mod("life_regen", StatBlock.ModType.FLAT, 10.0, "iron_skin")
	_iron_skin_active = true
	_iron_skin_t = s.duration
	rig.pulse()
	_show_ring(80.0, s.get_effective_color(), 0.3)
	_sfx_on("earth_shield", s.duration, 1.0, 42.0, true, 0.5)


func _do_frenzy(s: SkillDef) -> void:
	_frenzy_stacks = mini(_frenzy_stacks + 1, 5)
	_frenzy_t = 6.0
	stats.remove_source("frenzy")
	stats.add_mod("attack_speed", StatBlock.ModType.INCREASED, _frenzy_stacks * 0.10, "frenzy")
	stats.add_mod("move_speed", StatBlock.ModType.INCREASED, _frenzy_stacks * 0.05, "frenzy")

	rig.play_once("Slashing", 1.8)
	_show_swing(facing, s.get_effective_arc(), s.get_effective_radius(), s.get_effective_color(), SWING_TIME, s.get_effective_damage_type())
	_hit_area(global_position, facing, s.get_effective_radius(), s.get_effective_arc(), s)


func _do_sundering_strike(s: SkillDef) -> void:
	rig.play_once("Slashing", 1.3)
	_show_swing(facing, s.get_effective_arc(), s.get_effective_radius(), s.get_effective_color(), SWING_TIME * 1.5, s.get_effective_damage_type())
	_hit_area(global_position, facing, s.get_effective_radius(), s.get_effective_arc(), s, 0.5)
	_sfx("earth_spike", global_position + facing * s.get_effective_radius() * 0.8, s.get_effective_radius() / 85.0, facing.x < 0.0)


func _do_blade_vortex(s: SkillDef) -> void:
	rig.play_once("Slashing in The Air", 1.4)
	# Whirlwind axes outward
	_show_ring(s.get_effective_radius(), s.get_effective_color(), SWING_TIME * 2.0)
	_sfx("leaf_shield", global_position + Vector2(0, -30), s.get_effective_radius() / 115.0)
	_hit_area(global_position, facing, s.get_effective_radius(), 360.0, s)


func _do_battle_standard(s: SkillDef) -> void:
	rig.pulse()
	_show_ring(s.get_effective_radius(), s.get_effective_color(), 0.4)

	# Spawn Standard node on ground
	var banner := Node2D.new()
	banner.global_position = global_position
	get_parent().add_child(banner)
	var b_rad := s.get_effective_radius()
	var b_col := s.get_effective_color()
	_sfx("ground_hit", banner.global_position, b_rad / 180.0)
	Coop.player_fx(["banner", banner.global_position.x, banner.global_position.y, b_rad, b_col.to_html(false), s.duration])
	banner.draw.connect(func():
		banner.draw_circle(Vector2.ZERO, 16.0, b_col)
		banner.draw_arc(Vector2.ZERO, b_rad, 0.0, TAU, 40, Color(b_col.r, b_col.g, b_col.b, 0.4), 2.5)
	)
	banner.queue_redraw()
	var t := banner.create_tween()
	t.tween_interval(s.duration)
	t.tween_property(banner, "modulate:a", 0.0, 0.5)
	t.tween_callback(banner.queue_free)

	# Instant pulse damage
	_hit_area(global_position, facing, s.get_effective_radius(), 360.0, s)


## Call of the Ancients: Talic (Whirlwind), Korlic (Leap + Frenzy) and Madawc (Upheaval) fight for
## the skill's duration. Their base hit is a third of the skill's damage; each style scales it.
## [name, weapon, fighting style] - see AncientAlly
const ANCIENTS := [["Talic", "rusty_sword", "whirlwind"], ["Korlic", "battle_axe", "frenzy"], ["Madawc", "battle_axe", "upheaval"]]


func _do_call_ancients(s: SkillDef) -> void:
	rig.pulse()
	_show_ring(120.0, Color(0.6, 0.85, 1.0), 0.4)
	var rank := GameState.get_skill_rank(s.id)
	var per_hit := damage_for(s) * s.get_effective_damage_mult(rank) / 3.0
	for i in ANCIENTS.size():
		var a := AncientAlly.new()
		a.owner_player = self
		a.ancient_name = ANCIENTS[i][0]
		a.weapon_id = ANCIENTS[i][1]
		a.style = ANCIENTS[i][2]
		a.damage = per_hit
		a.lifetime = s.duration
		a.follow_offset = Vector2.from_angle(TAU * i / 3.0 + 0.5) * 80.0
		a.position = global_position + a.follow_offset
		get_parent().add_child(a)
		_sfx("lightning_strike", a.position + Vector2(0, -40))


func _do_cleave_skill(s: SkillDef) -> void:
	var target = _nearest_enemy(s.get_effective_radius() + 30.0)
	if target != null:
		facing = (target.global_position - global_position).normalized()
		rig.set_facing(facing.x)
	var as_hz := stats.get_stat("attack_speed")
	var anim_speed := maxf(1.0, 0.42 * as_hz)
	var cur_speed := velocity.length()
	rig.play_once("Run Slashing" if cur_speed > 25.0 else "Slashing", anim_speed)
	_show_swing(facing, s.get_effective_arc(), s.get_effective_radius(), s.get_effective_color(), SWING_TIME, s.get_effective_damage_type())
	_hit_area(global_position, facing, s.get_effective_radius(), s.get_effective_arc(), s)


# ---------- Health & Items ----------

func take_damage(amount: float) -> void:
	if dead:
		return
	var armor := stats.get_stat("armor")
	var taken := amount * 100.0 / (100.0 + armor)
	if _ward_t > 0.0:
		taken *= WARD_TAKEN  # Arcane Ward
	var shield := clampf(passive("mana_shield"), 0.0, 0.9)  # a keystone: part of each hit comes off Mana
	if shield > 0.0 and mana > 0.0:
		var off := minf(taken * shield, mana)
		mana -= off
		taken -= off
	hp -= taken
	# Getting hit builds Adrenaline
	var gain := class_def.power_per_life_lost * taken / maxf(stats.get_stat("max_life"), 1.0)
	if _hit_power_cd <= 0.0 and class_def.power_on_hit > 0.0:
		gain += class_def.power_on_hit
		_hit_power_cd = 0.5
	if gain > 0.0:
		gain_resource(gain)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		rig.play_once("Dying", 1.0, true)
		died.emit()
	elif _hurt_cd <= 0.0 and not _busy and not (rig.oneshot_name() in ATTACK_ANIMS):
		rig.play_once("Hurt", 1.4)
		_hurt_cd = 0.7


## Back on your feet with `frac` of your life (a party member revived you, or you got up: PartyDeath).
func revive(frac: float) -> void:
	if not dead:
		return
	dead = false
	hp = maxf(stats.get_stat("max_life") * frac, 1.0)
	rig.stop_once()
	rig.pulse()
	_sfx_on("revival", 1.0, 1.0, 30.0)


func bag_item_count() -> int:
	return bag.count()


## Cells the bag's items cover, of BAG_SIZE.
func bag_cells_used() -> int:
	return BAG_SIZE - bag.free_cells()


## Whether the bag has a free cell at all. To know if a particular item fits, use can_fit().
func has_empty_bag_slot() -> bool:
	return bag.free_cells() > 0


## Whether `item` has room in the bag (true if it's already in it).
func can_fit(item: ItemInstance) -> bool:
	return bag.can_fit(item)


func add_to_bag(item: ItemInstance) -> bool:
	if not bag.add(item):
		return false
	inventory_changed.emit()
	return true


func remove_from_bag(item: ItemInstance) -> bool:
	if bag.remove(item):
		inventory_changed.emit()
		return true
	return false


## Drag within the bag: `item` to top-left cell `at`. Landing on one item swaps it to where `item`
## was (or anywhere it fits); on two or more, or off the grid, nothing moves.
func move_in_bag(item: ItemInstance, at: Vector2i) -> bool:
	if not bag.has(item):
		return false
	var plan := bag.plan_drop(item, at, bag)
	if plan.is_empty():
		return false
	bag.apply_drop(item, at, bag, plan)
	inventory_changed.emit()
	return true


## Whether worn gear in `slot` could be dropped at `at` in the bag: into free space, or onto one
## bag item that can be worn in that slot (the two then trade places).
func can_unequip_to(slot: String, at: Vector2i) -> bool:
	var gear: ItemInstance = equipment.get(slot)
	if gear == null:
		return false
	var plan := bag.plan_drop(gear, at, null)
	if plan.is_empty():
		return false
	var b: ItemInstance = plan.get("swap")
	return b == null or (valid_slots(b).has(slot) and unique_conflict(b, slot) == null)


## Take worn gear off into the bag at `at`, or swap it with the bag item there (see can_unequip_to).
func unequip_to(slot: String, at: Vector2i) -> bool:
	if not can_unequip_to(slot, at):
		return false
	var gear: ItemInstance = equipment[slot]
	var plan := bag.plan_drop(gear, at, null)
	var b: ItemInstance = plan.get("swap")
	if b != null:
		return equip_to(b, slot, false, at)
	gear.remove_from(stats)
	equipment.erase(slot)
	bag.place(gear, at)
	hp = minf(hp, stats.get_stat("max_life"))
	_sync_gear_visuals()
	inventory_changed.emit()
	return true


func drop_from_bag(item: ItemInstance) -> void:
	if not bag.remove(item):
		return
	item_dropped.emit(item)
	inventory_changed.emit()


func drop_gear_slot(slot: String) -> void:
	if not equipment.has(slot):
		return
	var item: ItemInstance = equipment[slot]
	item.remove_from(stats)
	equipment.erase(slot)
	_sync_gear_visuals()
	item_dropped.emit(item)
	inventory_changed.emit()


## Walk to `pos` on your own (e.g. to an item whose label was tapped) and call `on_arrive` once
## within `reach`. Moving yourself cancels it, and so does getting stuck.
func walk_to(pos: Vector2, reach: float, on_arrive: Callable) -> void:
	_walk_target = pos
	_walk_reach = reach
	_walk_arrive = on_arrive
	_walk_time = 0.0
	_walking = true


func _walk_step(dir: Vector2, delta: float) -> Vector2:
	if not _walking:
		return dir
	if dir != Vector2.ZERO:
		_walking = false  # the player took over
		return dir
	var to := _walk_target - global_position
	_walk_time += delta
	if to.length() <= _walk_reach:
		_walking = false
		_walk_arrive.call()
		return Vector2.ZERO
	if _walk_time > 2.0 + to.length() / maxf(stats.get_stat("move_speed"), 1.0) * 2.0:
		_walking = false  # stuck on something
		return Vector2.ZERO
	return to.normalized()


## Picked-up loot, flasks included, always goes into the bag: equipping is only ever done by
## dragging an item onto its slot. False when it fits nowhere.
func pick_up(item: ItemInstance) -> bool:
	if not bag.can_fit(item):
		return false
	bag.add(item)
	item_picked.emit(item)
	inventory_changed.emit()
	return true


func equip(item: ItemInstance) -> void:
	equip_to(item, equip_slot_for(item), true)


# ---------- equipping rules: class weapon types, one/two-handed, dual wield ----------

## "" when you can use the item, otherwise the reason you can't (any weapon, if you meet its needs).
func equip_block_reason(item: ItemInstance) -> String:
	if item == null:
		return "Nothing to equip"
	if not item.identified:
		return "Identify it first"
	# A saved character's gear goes back on as it was; any that falls short just gives nothing
	if not GameState.is_restoring():
		return Attributes.block_reason(item.base, GameState.attribute_totals())
	return ""


func can_equip(item: ItemInstance) -> bool:
	return equip_block_reason(item) == ""


## Equipment slots `item` may go in (empty if the class can't use it).
func valid_slots(item: ItemInstance) -> Array[String]:
	var out: Array[String] = []
	if not can_equip(item) or item.is_flask():
		return out  # flasks go in flask slots (equip_flask)
	out.append(item.base.slot)
	if item.base.slot == "weapon" and not item.base.two_handed and class_def.dual_wield:
		out.append("offhand")
	if item.base.slot == "ring":
		out.append("ring2")  # a ring fits either ring slot
	return out


## Legendary and Set items are one of a kind on you: a second copy of one you are already wearing
## can't go in another slot (two of the same unique ring, or the same unique one-hander in both
## hands). Two different ones are fine. Returns the copy that is in the way, or null.
func unique_conflict(item: ItemInstance, slot: String) -> ItemInstance:
	if item == null or not item.is_unique():
		return null
	for s in equipment:
		var worn: ItemInstance = equipment[s]
		if worn != item and s != slot and worn.unique_id == item.unique_id:
			return worn
	return null


## "" if `item` may go in `slot` now, otherwise why not (class, requirements, or a unique you
## already wear).
func slot_block_reason(item: ItemInstance, slot: String) -> String:
	var why := equip_block_reason(item)
	if why != "":
		return why
	var dup := unique_conflict(item, slot)
	if dup != null:
		return "You are already wearing %s: each %s item can only be worn once" % [dup.display_name,
			"Set" if item.rarity == ItemInstance.Rarity.SET else "Legendary"]
	return ""


## Slot used when equipping without choosing one (Equip button, auto-equip on pickup):
## the first free valid slot, otherwise the main one. A unique you already wear replaces its copy.
func equip_slot_for(item: ItemInstance) -> String:
	var slots := valid_slots(item)
	if slots.is_empty():
		return item.base.slot
	for s in slots:
		var worn: ItemInstance = equipment.get(s)
		if worn != null and worn != item and item.is_unique() and worn.unique_id == item.unique_id:
			return s
	for s in slots:
		if not equipment.has(s) and not (s == "offhand" and _main_is_two_handed()):
			return s
	return slots[0]


func _main_is_two_handed() -> bool:
	var w: ItemInstance = equipment.get("weapon")
	return w != null and w.base.two_handed


## Gear that has to come off for `item` to go into `slot` (two-handers need both hands free).
func displaced_by(item: ItemInstance, slot: String) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var cur: ItemInstance = equipment.get(slot)
	if cur != null and cur != item:
		out.append(cur)
	if slot == "weapon" and item.base.two_handed and equipment.has("offhand"):
		out.append(equipment["offhand"])
	if slot == "offhand" and _main_is_two_handed() and equipment["weapon"] != item:
		out.append(equipment["weapon"])
	return out


## Equip `item` (from the bag or the ground) into `slot`. Whatever it replaces goes into the bag:
## at `prefer_at` if given and it fits, else where `item` was, else any space it fits. With
## allow_drop it is dropped on the ground if it fits nowhere; otherwise nothing changes.
## Also moves a worn one-hander between main and off hand. Returns false if not allowed.
func equip_to(item: ItemInstance, slot: String, allow_drop := false, prefer_at := ItemGrid.NONE) -> bool:
	if item == null or not valid_slots(item).has(slot):
		return false
	if unique_conflict(item, slot) != null and not GameState.is_restoring():
		return false
	if equipment.get(slot) == item:
		return true

	# Already worn in the other hand: swap hands (stats don't change)
	for s in equipment.keys():
		if equipment[s] == item:
			var other: ItemInstance = equipment.get(slot)
			if other != null and not valid_slots(other).has(s):
				return false
			equipment.erase(s)
			if other != null:
				equipment[s] = other
			equipment[slot] = item
			_sync_gear_visuals()
			inventory_changed.emit()
			return true

	var out := displaced_by(item, slot)
	# Where each piece coming off goes, worked out on a copy of the bag with `item` taken out
	var trial := bag.duplicate_grid()
	var old_at := bag.position_of(item)
	trial.remove(item)
	var spots := {}  # displaced item -> cell, or NONE to drop it on the ground
	for o in out:
		var spot := ItemGrid.NONE
		for c in [prefer_at, old_at]:
			if c != ItemGrid.NONE and trial.fits(o, c):
				spot = c
				break
		if spot == ItemGrid.NONE:
			spot = trial.find_free(o)
		if spot == ItemGrid.NONE and not allow_drop:
			return false
		if spot != ItemGrid.NONE:
			trial.place(o, spot)
		spots[o] = spot

	var old_max := stats.get_stat("max_life")
	for o in out:
		o.remove_from(stats)
		for s in equipment.keys():
			if equipment[s] == o:
				equipment.erase(s)
	bag.remove(item)
	item.apply_to(stats)
	equipment[slot] = item
	for o in out:
		if spots[o] != ItemGrid.NONE:
			bag.place(o, spots[o])
		else:
			item_dropped.emit(o)  # no room in the bag: drop it so nothing is lost
	var new_max := stats.get_stat("max_life")
	hp = clampf(hp + maxf(new_max - old_max, 0.0), 0.0, new_max)
	_sync_gear_visuals()
	inventory_changed.emit()
	return true


func equip_from_bag(item: ItemInstance) -> void:
	equip_to(item, equip_slot_for(item))


func modify_item(item: ItemInstance, change: Callable) -> void:
	var worn: bool = equipment.values().has(item)
	if worn:
		item.remove_from(stats)
	change.call()
	if worn:
		item.apply_to(stats)
		hp = minf(hp, stats.get_stat("max_life"))
		_sync_gear_visuals()  # an orb may have changed its Legendary power or base
	inventory_changed.emit()


## Take worn gear off into the first space in the bag it fits. False if it fits nowhere.
func unequip(slot: String) -> bool:
	var gear: ItemInstance = equipment.get(slot)
	if gear == null:
		return false
	var at := bag.find_free(gear)
	return at != ItemGrid.NONE and unequip_to(slot, at)


func drop_item(item: ItemInstance) -> void:
	if bag.has(item):
		drop_from_bag(item)
		return
	var fi := flasks.find(item)
	if fi != -1:
		flasks[fi] = null
		item_dropped.emit(item)
		inventory_changed.emit()
		return
	for s in equipment:
		if equipment[s] == item:
			drop_gear_slot(s)
			return


## Stats before / after equipping `item` (in `slot`, default: where Equip would put it).
func preview_equip(item: ItemInstance, slot := "") -> Dictionary:
	var keys := ["max_life", "damage", "attack_speed", "armor", "crit_chance", "move_speed"]
	if slot == "":
		slot = equip_slot_for(item)
	var before := {}
	var after := {}
	for k in keys:
		before[k] = stats.get_stat(k)
	var out: Array = displaced_by(item, slot) if can_equip(item) else []
	for o in out:
		o.remove_from(stats)
	item.apply_to(stats)
	for k in keys:
		after[k] = stats.get_stat(k)
	item.remove_from(stats)
	for o in out:
		o.apply_to(stats)
	return {"before": before, "after": after}


## Returns true if the item is better in slot than what is currently equipped.
func is_better_in_slot(item: ItemInstance) -> bool:
	if item == null:
		return false
	if not can_equip(item):
		return false
	var slot := equip_slot_for(item)
	if not equipment.has(slot) and displaced_by(item, slot).is_empty():
		return true  # Empty slot is always an upgrade!
	
	var old: ItemInstance = equipment.get(slot)
	if old == null:
		old = displaced_by(item, slot)[0]
	var cmp := preview_equip(item)
	var before: Dictionary = cmp["before"]
	var after: Dictionary = cmp["after"]

	var d_dmg: float = after["damage"] - before["damage"]
	var d_life: float = after["max_life"] - before["max_life"]
	var d_armor: float = after["armor"] - before["armor"]
	var d_crit: float = after["crit_chance"] - before["crit_chance"]
	var d_as: float = after["attack_speed"] - before["attack_speed"]
	var d_ms: float = after["move_speed"] - before["move_speed"]

	# General combat rating delta
	var score_delta := (d_dmg * 12.0) + (d_life * 3.0) + (d_armor * 4.0) + (d_crit * 400.0) + (d_as * 80.0) + (d_ms * 40.0)

	if score_delta > 0.5:
		return true

	# Slot-specific primary role checks
	match slot:
		"weapon", "offhand":
			if d_dmg > 0.0 or (d_dmg == 0.0 and d_as > 0.0):
				return true
		"chest", "helmet", "gloves", "boots":
			if (d_armor > 0.0 and d_life >= 0.0) or (d_life > 0.0 and d_armor >= 0.0):
				return true

	# If stats are tied, compare rarity and item level
	if absf(score_delta) <= 0.5:
		if item.rarity > old.rarity:
			return true
		if item.rarity == old.rarity and item.ilvl > old.ilvl:
			return true

	return false


## Generates a colored summary string explaining why this item is better in slot.
func get_upgrade_summary(item: ItemInstance) -> String:
	if item == null:
		return ""
	var slot := equip_slot_for(item)
	if not equipment.has(slot) or equipment[slot] == null:
		return "[color=#4ade80]Empty Slot! Immediate Upgrade[/color]"
	var cmp := preview_equip(item)
	var lines: Array[String] = []
	var before: Dictionary = cmp["before"]
	var after: Dictionary = cmp["after"]

	for k in ["damage", "max_life", "armor", "crit_chance", "attack_speed", "move_speed"]:
		var d: float = after[k] - before[k]
		if absf(d) < 0.001:
			continue
		var label: String = UIKit.STAT_LABELS.get(k, k.capitalize())
		var txt := ""
		match k:
			"crit_chance", "move_speed":
				txt = "%+d%%" % int(round(d * 100.0))
			"attack_speed":
				txt = "%+.2f /s" % d
			_:
				txt = "%+d" % int(round(d))
		var col := "4ade80" if d > 0.0 else "f87171"
		lines.append("[color=#%s]%s %s[/color]" % [col, txt, label])

	if lines.is_empty():
		var old: ItemInstance = equipment[slot]
		if item.rarity > old.rarity:
			return "[color=#ffd700]Higher Rarity Tier (%s vs %s)[/color]" % [
				ItemInstance.Rarity.keys()[item.rarity].capitalize(),
				ItemInstance.Rarity.keys()[old.rarity].capitalize()
			]
		if item.ilvl > old.ilvl:
			return "[color=#7ba6ff]Higher Item Level (iLvl %d vs %d)[/color]" % [item.ilvl, old.ilvl]
		return "[color=#4ade80]Superior magical affixes[/color]"

	return "\n".join(PackedStringArray(lines))


## Generates a compact inline summary of upgrade deltas for small HUD popups (e.g. "+15 Damage   +5% Crit").
func get_compact_upgrade_summary(item: ItemInstance) -> String:
	if item == null:
		return ""
	var slot := equip_slot_for(item)
	if not equipment.has(slot) or equipment[slot] == null:
		return "[color=#4ade80]Empty Slot! Immediate Upgrade[/color]"
	var cmp := preview_equip(item)
	var parts: Array[String] = []
	var before: Dictionary = cmp["before"]
	var after: Dictionary = cmp["after"]

	for k in ["damage", "max_life", "armor", "crit_chance", "attack_speed", "move_speed"]:
		var d: float = after[k] - before[k]
		if absf(d) < 0.001:
			continue
		var label: String = UIKit.STAT_LABELS.get(k, k.capitalize())
		var txt := ""
		match k:
			"crit_chance", "move_speed":
				txt = "%+d%%" % int(round(d * 100.0))
			"attack_speed":
				txt = "%+.2f/s" % d
			_:
				txt = "%+d" % int(round(d))
		var col := "4ade80" if d > 0.0 else "f87171"
		parts.append("[color=#%s]%s %s[/color]" % [col, txt, label])
		if parts.size() >= 2:
			break

	if parts.is_empty():
		return "[color=#4ade80]Superior Tier / Properties[/color]"
	return "   ".join(PackedStringArray(parts))


## Returns the display name of currently equipped gear in the item's slot.
func get_replaced_gear_name(item: ItemInstance) -> String:
	if item == null:
		return "None"
	var slot := equip_slot_for(item)
	if not equipment.has(slot) or equipment[slot] == null:
		return "Empty Slot"
	return equipment[slot].display_name


## Equips item directly. Places replaced gear into bag or drops onto world if bag is full.
func equip_with_overflow(item: ItemInstance) -> ItemInstance:
	var slot := equip_slot_for(item)
	var out := displaced_by(item, slot)
	if not equip_to(item, slot, true):
		return null
	return out[0] if not out.is_empty() else null


## Shows worn gear on a rig: main weapon, helmet, chest and the off-hand item.
static func dress_rig(r: RigSprite, gear: Dictionary) -> void:
	for slot in VISIBLE_SLOTS:
		var it = gear.get(slot)
		r.set_gear(slot, it.base.id if it != null else "", it.dye if it != null and slot in DyeDB.SLOTS else "")
	var off = gear.get("offhand")
	r.set_offhand(off.base.id if off != null else "", off != null and off.base.weapon_type == "shield")


## Called whenever the worn gear changes: redress the rig and recount Legendary powers and
## set bonuses (item_powers, read through GameState.passive_value like passive tree stats).
func _sync_gear_visuals() -> void:
	_refresh_gear_requirements()
	item_powers = UniqueItems.powers_of(equipment.values().filter(gear_active))
	if stats != null:
		_apply_passives()
	if rig == null:
		return
	_match_rig()
	dress_rig(rig, equipment)
	if GameState.player == self:
		Net.update_looks()  # others online see the new gear


## A bow in hand: drawn on the archer rig (drawing and loosing arrows); otherwise the sword rig. The
## rig is swapped for one of the right kind, wearing your looks.
func _match_rig() -> void:
	var w: ItemInstance = equipment.get("weapon")
	var want := RigSprite.rig_for_weapon(w.base.id if w != null else "")
	if rig.rig_dir == want:
		return
	var r := RigSprite.new()
	r.base_scale = rig.base_scale
	r.weapon_from_gear = true
	r.rig_dir = want
	var at := rig.get_index()
	remove_child(rig)
	rig.queue_free()
	add_child(r)
	move_child(r, at)
	Appearance.apply(r, GameState.appearance)
	rig = r


## Whether worn (or wearable) gear meets its attribute requirements, so its stats count.
func gear_active(item: ItemInstance) -> bool:
	return item != null and Attributes.meets(item.base, GameState.attribute_totals())


## Worn gear that falls short of its requirements gives nothing: its stats come off until it meets
## them, and go back on when it does. Safe to call any time; runs after every gear change.
func _refresh_gear_requirements() -> void:
	if stats == null:
		return
	var worn := equipment.values()
	for it in _inactive.keys():
		if not worn.has(it):
			_inactive.erase(it)
	for it in worn:
		if not gear_active(it):
			it.remove_from(stats)  # also undoes anything that re-applied it meanwhile
			_inactive[it] = true
		elif _inactive.has(it):
			it.apply_to(stats)
			_inactive.erase(it)


# ---------- Drawing (Ground effects; character itself is the rig) ----------

func _draw() -> void:
	RigSprite.draw_shadow(self, 26.0)
	if _buff_active:
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, Color(1.0, 0.6, 0.2, 0.8), 4.0)
	if _iron_skin_active:
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 32, Color(0.7, 0.85, 1.0, 0.9), 4.5)
	if _frenzy_stacks > 0:
		for s in _frenzy_stacks:
			var ang := (s / float(_frenzy_stacks)) * TAU
			draw_circle(Vector2.from_angle(ang) * 28.0, 3.5, Color(1.0, 0.8, 0.2, 0.9))

	if _swing_t > 0.0:
		Player.draw_swing(self, _swing_dir, _swing_arc, _swing_radius, _swing_color, _swing_t / SWING_TIME)
	if _ring_t > 0.0:
		Player.draw_ring(self, _ring_radius, _ring_color, _ring_t / (SWING_TIME * 2.5))
	if _whirlwind_t > 0.0:
		Player.draw_spin(self, _ring_color)


## A skill's swing on `ci`: a cone `arc` degrees wide towards `dir` (a circle at 360), fading with `a`.
## Also draws other players' swings (RemotePlayer).
static func draw_swing(ci: CanvasItem, dir: Vector2, arc: float, radius: float, col: Color, a: float) -> void:
	if arc >= 359.0:
		ci.draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, 0.30 * a))
		ci.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(col.r, col.g, col.b, 0.9 * a), 3.0)
		return
	var half := deg_to_rad(arc) * 0.5
	var start := dir.angle() - half
	var edge := PackedVector2Array()
	for i in 13:
		edge.append(Vector2.from_angle(start + half * 2.0 * float(i) / 12.0) * radius)
	ci.draw_colored_polygon(PackedVector2Array([Vector2.ZERO]) + edge, Color(col.r, col.g, col.b, 0.40 * a))
	ci.draw_polyline(edge, Color(col.r, col.g, col.b, 0.9 * a), 3.0)


static func draw_ring(ci: CanvasItem, radius: float, col: Color, a: float) -> void:
	ci.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)), 6.0)


## Whirlwind's cyclone: a ring and three blades going round.
static func draw_spin(ci: CanvasItem, col: Color) -> void:
	var spin_ang := float(Time.get_ticks_msec()) * 0.008
	ci.draw_arc(Vector2.ZERO, 145.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.5), 3.0)
	for b in 3:
		var b_ang := spin_ang + (b * TAU / 3.0)
		ci.draw_arc(Vector2.ZERO, 135.0, b_ang, b_ang + 1.1, 16, Color(1.0, 1.0, 1.0, 0.8), 3.0)


## What a skill looks like: drawn here, and in a party rift or zone sent to the others (Coop.player_fx)
## so their copy of you (RemotePlayer.show_fx) shows it too.
func _show_swing(dir: Vector2, arc: float, radius: float, col: Color, t: float, dtype := 0) -> void:
	_swing_dir = dir
	_swing_arc = arc
	_swing_radius = radius
	_swing_color = col
	if arc < 359.0 and SpellFx.SWINGS.has(dtype):  # an elemental swing: its own slash (the party sees it)
		_sfx(SpellFx.SWINGS[dtype], global_position + dir * radius * 0.5 + Vector2(0, -26), radius / 80.0, dir.x < 0.0)
		return
	if arc < 359.0:
		SpellFx.slash(self, dir, arc, radius, col, maxf(t * 1.6, 0.22))  # the art's slash, not a cone
	else:
		_swing_t = t
	Coop.player_fx(["swing", snappedf(dir.angle(), 0.01), arc, radius, col.to_html(false), t])


func _show_ring(radius: float, col: Color, t: float) -> void:
	_ring_t = t
	_ring_radius = radius
	_ring_color = col
	Coop.player_fx(["ring", radius, col.to_html(false), t])


func _on_leveled_up(_level: int) -> void:
	if is_inside_tree():
		_sfx("stars", global_position + Vector2(0, -60))


## A spell effect where it happens (SpellFx), seen by the party too (Coop.player_fx "sfx").
func _sfx(id: String, at: Vector2, size := 1.0, flip := false) -> void:
	SpellFx.spawn(get_parent(), id, at, size, flip)
	Coop.player_fx(["sfx", id, snappedf(at.x, 0.1), snappedf(at.y, 0.1), size, flip])


## One kept on you a while (a shield: SpellFx.attach), seen by the party too ("sfx_on").
func _sfx_on(id: String, secs: float, size := 1.0, lift := 0.0, hold := false, alpha := 1.0) -> void:
	SpellFx.attach(self, id, secs, size, lift, hold, alpha)
	Coop.player_fx(["sfx_on", id, secs, size, lift, hold, alpha])


var _spin_sent := 0  # msec: whirlwind hits many times a second; the others hear of it 4 times a second


func _show_spin(radius: float, col: Color) -> void:
	_whirlwind_t = 0.28  # keeps the spin loop animation and cyclone ring going across its hits
	_ring_t = 0.28
	_ring_radius = radius
	_ring_color = col
	SpellFx.attach(self, "typhoon", 0.35, radius / 125.0, 10.0, false, 0.55)  # (the party: "spin")
	if Time.get_ticks_msec() - _spin_sent > 250:
		_spin_sent = Time.get_ticks_msec()
		Coop.player_fx(["spin", radius, col.to_html(false), 0.4])
