class_name Player
extends CharacterBody2D

signal died
signal item_picked(item: ItemInstance)
signal item_dropped(item: ItemInstance)
signal inventory_changed

const SWING_TIME := 0.15
const BAG_SIZE := 24
const SLOTS := ["weapon", "helmet", "chest", "gloves", "boots", "ring", "amulet"]
## Slots that change how the character looks (see RigSprite.GEAR_LAYERS).
const VISIBLE_SLOTS := ["weapon", "helmet", "chest"]
const ATTACK_ANIMS := ["Slashing", "Run Slashing", "Slashing in The Air"]
const HIT_DELAY := 0.12  # seconds into the swing animation when the blow lands

var class_def: ClassDef
var stats := StatBlock.new()
var hp := 100.0
var dead := false
var inventory: Array[ItemInstance] = []
var equipment := {}  # slot -> ItemInstance
var joystick: VirtualJoystick
var rig: RigSprite
var can_fight := true  # false in town

var skills: Array[SkillDef] = []
var facing := Vector2.RIGHT

var _cooldowns: Array[float] = []
var _attack_cd := 0.0
var _windup_t := 0.0
var _windup_dir := Vector2.RIGHT
var _hurt_cd := 0.0
var _busy := false  # true while leaping
var _buff_active := false
var _buff_t := 0.0
var _swing_t := 0.0
var _swing_dir := Vector2.RIGHT
var _swing_arc := 120.0
var _swing_radius := 100.0
var _ring_t := 0.0
var _ring_radius := 100.0


func _ready() -> void:
	if class_def == null:
		class_def = ClassLibrary.warrior()
	add_to_group("player")
	for k in class_def.base_stats:
		stats.set_base(String(k), class_def.base_stats[k])
	for s in class_def.skills:
		skills.append(s)
		_cooldowns.append(0.0)
	hp = stats.get_stat("max_life")

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
	_sync_gear_visuals()
	GameState.attach_player(self)  # restore saved gear and bag


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard skills for desktop testing: 1, 2, 3
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: use_skill(1)
			KEY_2: use_skill(2)
			KEY_3: use_skill(3)


func _physics_process(delta: float) -> void:
	if dead:
		return

	hp = minf(hp + stats.get_stat("life_regen") * delta, stats.get_stat("max_life"))
	for i in _cooldowns.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
	_swing_t = maxf(_swing_t - delta, 0.0)
	_ring_t = maxf(_ring_t - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	if _buff_active:
		_buff_t -= delta
		if _buff_t <= 0.0:
			_buff_active = false
			stats.remove_source("battle_cry")
	if _windup_t > 0.0:
		_windup_t -= delta
		if _windup_t <= 0.0:
			_do_cleave()
	queue_redraw()

	if _busy:
		return

	var dir := Vector2.ZERO
	if joystick:
		dir = joystick.output
	if dir == Vector2.ZERO:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")  # keyboard for desktop testing
	velocity = dir * stats.get_stat("move_speed")
	move_and_slide()
	if dir.length() > 0.1:
		facing = dir.normalized()

	# Stand / walk / run animation follows how fast we are actually moving.
	var speed := velocity.length()
	if not rig.is_busy():
		rig.set_facing(facing.x)
	if speed < 25.0:
		rig.play_loop("Idle")
	elif speed < stats.get_stat("move_speed") * 0.6:
		rig.play_loop("Walking", clampf(speed / 110.0, 0.6, 1.3))
	else:
		rig.play_loop("Running", clampf(speed / 220.0, 0.8, 1.4))

	# Basic attack: swing at the nearest enemy in reach; the blow lands mid-animation.
	_attack_cd -= delta
	if _attack_cd <= 0.0 and can_fight:
		var basic := skills[0]
		var target = _nearest_enemy(basic.radius)
		if target != null:
			facing = (target.global_position - global_position).normalized()
			rig.set_facing(facing.x)
			var as_hz := stats.get_stat("attack_speed")
			var anim_speed := maxf(1.0, 0.42 * as_hz)  # keep the swing shorter than the attack interval
			rig.play_once("Run Slashing" if speed > 25.0 else "Slashing", anim_speed)
			_windup_dir = facing
			_windup_t = HIT_DELAY / anim_speed
			_attack_cd = 1.0 / maxf(as_hz, 0.1)


func _do_cleave() -> void:
	var basic := skills[0]
	_swing_dir = _windup_dir
	_swing_arc = basic.arc_degrees
	_swing_radius = basic.radius
	_swing_t = SWING_TIME
	_hit_area(global_position, _windup_dir, basic.radius, basic.arc_degrees, basic.damage_mult)


func _nearest_enemy(within: float):
	var best = null
	var best_d := within
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Damage every enemy inside a cone (or full circle if arc >= 360).
func _hit_area(origin: Vector2, dir: Vector2, radius: float, arc_deg: float, mult: float, stun := 0.0) -> void:
	var half := deg_to_rad(arc_deg) * 0.5
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector2 = e.global_position - origin
		if to.length() > radius + 14.0:
			continue
		if arc_deg < 359.0 and absf(dir.angle_to(to)) > half:
			continue
		var crit := randf() < stats.get_stat("crit_chance")
		var dmg := stats.get_stat("damage") * mult * (2.0 if crit else 1.0)
		e.take_damage(dmg, crit)
		if stun > 0.0:
			e.stun(stun)


# ---------- skills ----------

func use_skill(i: int) -> void:
	if dead or _busy or not can_fight or i < 1 or i >= skills.size():
		return
	if _cooldowns[i] > 0.0:
		return
	var s := skills[i]
	_cooldowns[i] = s.cooldown
	match s.kind:
		SkillDef.Kind.WHIRLWIND:
			_ring_t = SWING_TIME * 2.0
			_ring_radius = s.radius
			rig.play_once("Slashing in The Air", 1.2)
			_hit_area(global_position, facing, s.radius, 360.0, s.damage_mult)
		SkillDef.Kind.LEAP_SLAM:
			_leap(s)
		SkillDef.Kind.BATTLE_CRY:
			_battle_cry(s)


func cooldown_fraction(i: int) -> float:
	if i < 0 or i >= skills.size() or skills[i].cooldown <= 0.0:
		return 0.0
	return clampf(_cooldowns[i] / skills[i].cooldown, 0.0, 1.0)


func _leap(s: SkillDef) -> void:
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
		_ring_t = SWING_TIME * 2.0
		_ring_radius = s.radius
		rig.play_once("Slashing", 1.3)
		_hit_area(global_position, facing, s.radius, 360.0, s.damage_mult, s.stun)
	)


## Timed buff built on StatBlock: 25% MORE damage and +40 armor.
func _battle_cry(s: SkillDef) -> void:
	if _buff_active:
		stats.remove_source("battle_cry")
	stats.add_mod("damage", StatBlock.ModType.MORE, 0.25, "battle_cry")
	stats.add_mod("armor", StatBlock.ModType.FLAT, 40.0, "battle_cry")
	_buff_active = true
	_buff_t = s.duration
	rig.pulse()


# ---------- health / items ----------

func take_damage(amount: float) -> void:
	if dead:
		return
	var armor := stats.get_stat("armor")
	hp -= amount * 100.0 / (100.0 + armor)  # diminishing-returns armor
	if hp <= 0.0:
		hp = 0.0
		dead = true
		rig.play_once("Dying", 1.0, true)
		died.emit()
	elif _hurt_cd <= 0.0 and not _busy and not (rig.oneshot_name() in ATTACK_ANIMS):
		rig.play_once("Hurt", 1.4)
		_hurt_cd = 0.7


## `inventory` is the bag only; worn items live in `equipment`.
## Returns false (and takes nothing) if the bag is full.
func pick_up(item: ItemInstance) -> bool:
	if not equipment.has(item.base.slot):
		equip(item)  # empty slot: wear it straight away
	elif inventory.size() < BAG_SIZE:
		inventory.append(item)
	else:
		return false
	item_picked.emit(item)
	inventory_changed.emit()
	return true


func equip(item: ItemInstance) -> void:
	var old_max := stats.get_stat("max_life")
	var slot := item.base.slot
	if equipment.has(slot):
		equipment[slot].remove_from(stats)
	item.apply_to(stats)
	equipment[slot] = item
	var new_max := stats.get_stat("max_life")
	hp = clampf(hp + maxf(new_max - old_max, 0.0), 0.0, new_max)
	_sync_gear_visuals()


## Wear a bag item. Whatever was in that slot takes its place in the bag.
func equip_from_bag(item: ItemInstance) -> void:
	var idx := inventory.find(item)
	if idx == -1:
		return
	var old = equipment.get(item.base.slot)
	inventory.remove_at(idx)
	if old != null:
		inventory.insert(idx, old)
	equip(item)  # equip() strips the old item's modifiers
	inventory_changed.emit()


## Run `change` (a Callable that edits the item) with stat bookkeeping handled:
## worn items have their modifiers removed first and re-applied after.
func modify_item(item: ItemInstance, change: Callable) -> void:
	var worn: bool = equipment.get(item.base.slot) == item
	if worn:
		item.remove_from(stats)
	change.call()
	if worn:
		item.apply_to(stats)
		hp = minf(hp, stats.get_stat("max_life"))
	inventory_changed.emit()


## Move a worn item into the bag. Fails if the bag is full.
func unequip(slot: String) -> bool:
	if not equipment.has(slot) or inventory.size() >= BAG_SIZE:
		return false
	var item: ItemInstance = equipment[slot]
	item.remove_from(stats)
	equipment.erase(slot)
	inventory.append(item)
	hp = minf(hp, stats.get_stat("max_life"))
	_sync_gear_visuals()
	inventory_changed.emit()
	return true


## Remove a bag item; the game world spawns it on the ground.
func drop_item(item: ItemInstance) -> void:
	if inventory.has(item):
		inventory.erase(item)
		item_dropped.emit(item)
		inventory_changed.emit()


## What would my stats be if I wore this? Leaves the real stats untouched.
func preview_equip(item: ItemInstance) -> Dictionary:
	var keys := ["max_life", "damage", "attack_speed", "armor", "crit_chance", "move_speed"]
	var before := {}
	var after := {}
	for k in keys:
		before[k] = stats.get_stat(k)
	var old = equipment.get(item.base.slot)
	if old != null:
		old.remove_from(stats)
	item.apply_to(stats)
	for k in keys:
		after[k] = stats.get_stat(k)
	item.remove_from(stats)
	if old != null:
		old.apply_to(stats)
	return {"before": before, "after": after}


## Show what is worn: the character's weapon, helmet and chest layers follow equipment.
func _sync_gear_visuals() -> void:
	if rig == null:
		return
	for slot in VISIBLE_SLOTS:
		var it = equipment.get(slot)
		rig.set_gear(slot, it.base.id if it != null else "")


# ---------- drawing (ground effects; the character itself is the rig) ----------

func _draw() -> void:
	RigSprite.draw_shadow(self, 26.0)
	if _buff_active:
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, Color(1.0, 0.6, 0.2, 0.8), 4.0)
	if _swing_t > 0.0:
		var a := _swing_t / SWING_TIME
		var half := deg_to_rad(_swing_arc) * 0.5
		var start := _swing_dir.angle() - half
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 13:
			pts.append(Vector2.from_angle(start + half * 2.0 * float(i) / 12.0) * _swing_radius)
		draw_colored_polygon(pts, Color(1, 1, 1, 0.30 * a))
	if _ring_t > 0.0:
		var a2 := _ring_t / (SWING_TIME * 2.0)
		draw_arc(Vector2.ZERO, _ring_radius, 0.0, TAU, 48, Color(1.0, 0.8, 0.4, a2), 6.0)
