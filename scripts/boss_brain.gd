class_name BossBrain
extends Node
## Runs a boss fight on a boss monster (Enemy) that has an entry in BossDB: the intro, its moves, its
## phases, its adds and its enrage. A child of the boss, made by attach(), only in the game that runs the
## monster (the host's, in a party). The Enemy asks control() each physics frame: while it answers true
## the brain is driving (a warning showing, a dash, a roar) and the monster does nothing else; between
## moves it answers false and the monster fights as it always did (an archer keeps its distance and shoots).
##
## Every attack is shown on the ground first (BossTelegraph), and hurts whoever is standing in that spot
## when the warning ends: the player, their hireling and the others in a party. Phases begin when its life
## falls to a phase's `at`: it roars, untouchable (the shield monsters already have), says its line and
## calls its adds; a phase can speed it up, make it hit harder and shorten its cooldowns. After the
## entry's `enrage` seconds it goes faster and harder for good.

signal phase_changed(index: int)
signal said(text: String)
signal enraged_now

enum S { SLEEP, INTRO, IDLE, WINDUP, DASH, RECOVER, ROAR }

const ROAR_TIME := 1.5
const ENRAGE_SPEED := 1.3
const ENRAGE_DMG := 1.4
const ENRAGE_CD := 0.6
const BODY := 14.0  ## a player's reach beyond a point, for the hit tests

var boss: Enemy
var def := {}
var state := S.SLEEP
var phase := 0
var enraged := false
var fight_t := 0.0
var moves_used := {}  ## move id -> how many times (tests, and a look at what it did)

var _t := 0.0
var _gap := 1.0
var _cd := {}
var _move := {}
var _move_id := ""
var _aim := Vector2.RIGHT
var _spots: Array[Vector2] = []
var _dash_left := 0.0
var _dash_hit := {}
var _adds: Array = []
var _base_speed := 0.0
var _base_touch := 0.0
var _phase_speed := 1.0
var _phase_dmg := 1.0
var _phase_cd := 1.0
var _resume := false
var _veil := {}  ## the phase's Veil Realm settings (VeilRealm), {} for none
var _veil_t := 0.0
var _realm: VeilRealm


## Puts a brain on `e` if the boss `id` has an entry (and `e` is the real monster, not a copy of the
## host's). `resume`: a fight already under way (a party's host left and this game took over): no intro.
static func attach(e: Enemy, id: String, resume := false) -> BossBrain:
	var d := BossDB.def(id)
	if d.is_empty() or e.remote:
		return null
	var b := BossBrain.new()
	b.name = "BossBrain"
	b.boss = e
	b.def = d
	b._resume = resume
	e.brain = b
	e.add_child(b)
	return b


func _ready() -> void:
	_base_speed = boss.speed
	_base_touch = boss.touch_damage
	boss.died.connect(_on_boss_died)
	if _resume:
		state = S.IDLE
		phase = BossDB.phase_at(def, boss.hp / maxf(boss.max_hp, 1.0))
		_load_phase(phase)


# ---------- each frame ----------

## True while the brain is driving the monster this frame.
func control(delta: float) -> bool:
	if not is_instance_valid(boss) or boss._dead:
		return false
	if state == S.SLEEP:
		if not boss._aggro:
			return false
		_start_intro()
	for k in _cd.keys():
		_cd[k] = maxf(float(_cd[k]) - delta, 0.0)
	if state != S.INTRO:
		fight_t += delta
		if not enraged and fight_t >= float(def.get("enrage", 1e9)):
			_enrage()
		_veil_step(delta)

	match state:
		S.INTRO, S.ROAR:
			_stand()
			_t -= delta
			if _t <= 0.0:
				state = S.IDLE
				_gap = 0.7
		S.WINDUP:
			_stand()
			_t -= delta
			if _t <= 0.0:
				_strike()
		S.DASH:
			_dash(delta)
		S.RECOVER:
			_stand()
			_t -= delta
			if _t <= 0.0:
				state = S.IDLE
		S.IDLE:
			_idle(delta)
	return state != S.IDLE


func _idle(delta: float) -> void:
	var want := BossDB.phase_at(def, boss.hp / maxf(boss.max_hp, 1.0))
	if want > phase:
		_enter_phase(want)
		return
	_gap -= delta
	if _gap > 0.0:
		return
	var foe := _foe()
	var id := _choose(foe)
	if id == "":
		_gap = 0.4
		return
	_begin(id, foe)


# ---------- intro, phases, enrage ----------

func _start_intro() -> void:
	state = S.INTRO
	_t = float(def.get("intro", 1.8))
	_load_phase(0)
	_make_untouchable(_t)
	boss.rig.pulse(0.3, 1.0)
	boss._flash_ring(boss.global_position, 170.0, Color(1.0, 0.45, 0.2))
	var line := String(def.get("lines", {}).get("intro", ""))
	if line != "":
		_say(line)


func _enter_phase(i: int) -> void:
	phase = i
	_load_phase(i)
	state = S.ROAR
	_t = ROAR_TIME
	_make_untouchable(_t)
	boss.rig.pulse(0.3, 0.9)
	boss._flash_ring(boss.global_position, 200.0, Color(1.0, 0.3, 0.15))
	var ph: Dictionary = def.phases[i]
	var line := String(ph.get("say", ""))
	if line != "":
		_say(line)
	_summon(ph.get("adds", []))
	phase_changed.emit(i)


func _load_phase(i: int) -> void:
	var phases: Array = def.get("phases", [])
	var ph: Dictionary = phases[i] if i < phases.size() else {}
	_phase_speed = float(ph.get("speed", 1.0))
	_phase_dmg = float(ph.get("dmg", 1.0))
	_phase_cd = float(ph.get("cd", 1.0))
	if ph.has("skin") and boss.rig != null:  # its look changes (Malaphax tears off his armour)
		boss.skin = String(ph.skin)
		boss.rig.set_part_overrides(RigSprite.skin_parts(boss.skin))
	var veil: Dictionary = ph.get("veil", {})
	if veil != _veil:
		_veil = veil
		_veil_t = 1.5
	_apply_stats()


func _apply_stats() -> void:
	boss.speed = _base_speed * _phase_speed * (ENRAGE_SPEED if enraged else 1.0)
	boss.touch_damage = _base_touch * _phase_dmg * (ENRAGE_DMG if enraged else 1.0)


## A phase with a "veil" drags the fight into the Veil Realm now and then (VeilRealm): `interval` seconds after one lifts, the next.
func _veil_step(delta: float) -> void:
	if _veil.is_empty() or is_instance_valid(_realm) or state == S.ROAR:
		return
	_veil_t -= delta
	if _veil_t <= 0.0:
		_realm = VeilRealm.begin(self, _veil)
		_realm.ended.connect(func(): _veil_t = float(_veil.get("interval", 26.0)))


func _cd_mult() -> float:
	return _phase_cd * (ENRAGE_CD if enraged else 1.0)


func _enrage() -> void:
	enraged = true
	_apply_stats()
	boss.rig.modulate = Color(1.0, 0.5, 0.42)
	boss.rig.pulse(0.25, 0.7)
	boss._flash_ring(boss.global_position, 220.0, Color(1.0, 0.15, 0.1))
	var line := String(def.get("lines", {}).get("enrage", ""))
	if line != "":
		_say(line)
	enraged_now.emit()


func _make_untouchable(seconds: float) -> void:
	boss._shield_t = maxf(boss._shield_t, seconds)
	boss._sfx_on("immunity", seconds, boss.size_mult, 36.0 * boss.size_mult)  # the party sees it too


# ---------- choosing and warning ----------

func _choose(foe: Node2D) -> String:
	if foe == null:
		return ""
	var dist := boss.global_position.distance_to(foe.global_position)
	var ids: Array = def.phases[phase].get("moves", []) if phase < def.get("phases", []).size() else def.moves.keys()
	var pool: Array = []
	var total := 0.0
	for id in ids:
		var m: Dictionary = def.moves[id]
		if float(_cd.get(id, 0.0)) > 0.0:
			continue
		var r: Array = m.get("range", [0.0, 99999.0])
		if dist < float(r[0]) or dist > float(r[1]):
			continue
		var w := float(m.get("weight", 1.0))
		pool.append([id, w])
		total += w
	if pool.is_empty():
		return ""
	var pick := randf() * total
	for entry in pool:
		pick -= float(entry[1])
		if pick <= 0.0:
			return String(entry[0])
	return String(pool[-1][0])


## Starts a move: its warning is shown now and the hit comes when `windup` is up.
func begin(id: String) -> void:
	_begin(id, _foe())


func _begin(id: String, foe: Node2D) -> void:
	_move_id = id
	_move = def.moves[id]
	moves_used[id] = int(moves_used.get(id, 0)) + 1
	_cd[id] = float(_move.get("cd", 4.0)) * _cd_mult()
	var to := (foe.global_position - boss.global_position) if foe != null else Vector2.RIGHT
	_aim = to.normalized() if to.length() > 1.0 else Vector2.RIGHT
	boss.rig.set_facing(_aim.x)
	state = S.WINDUP
	var w := float(_move.get("windup", 0.8))
	_t = w
	var o := boss.global_position
	match String(_move.kind):
		"slam":
			_tele({"s": "circle", "x": o.x, "y": o.y, "r": float(_move.r), "t": w})
		"sweep":
			_tele({"s": "cone", "x": o.x, "y": o.y, "a": _aim.angle(), "w": float(_move.arc), "r": float(_move.r), "t": w})
		"charge":
			_tele({"s": "line", "x": o.x, "y": o.y, "a": _aim.angle(), "r": float(_move.length), "w": float(_move.width), "t": w})
		"volley":
			_tele({"s": "cone", "x": o.x, "y": o.y, "a": _aim.angle(), "w": float(_move.spread), "r": float(_move.length), "t": w})
		"pin":
			_tele({"s": "line", "x": o.x, "y": o.y, "a": _aim.angle(), "r": float(_move.length), "w": float(_move.width), "t": w})
		"rain":
			_spots = _rain_spots(int(_move.count), float(_move.r), foe)
			for s in _spots:
				_tele({"s": "circle", "x": s.x, "y": s.y, "r": float(_move.r), "t": w})
		"backstep":
			_aim = -_aim  # away from its foe
		"summon":
			boss._flash_ring(o, 110.0, Color(1.0, 0.7, 0.3))
	if String(_move.kind) != "backstep":
		boss.rig.play_once("Slashing", 1.0)


func _tele(params: Dictionary) -> void:
	BossTelegraph.warn(boss, params)


## One circle on each player, and the rest about them.
func _rain_spots(count: int, r: float, foe: Node2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in Enemy.players_of(get_tree(), boss.target):
		if out.size() < count:
			out.append(p.global_position)
	var around: Vector2 = foe.global_position if foe != null else boss.global_position
	while out.size() < count:
		out.append(around + Vector2.from_angle(randf() * TAU) * randf_range(r * 1.2, r * 3.6))
	return out


# ---------- the hit ----------

func _strike() -> void:
	var m := _move
	var dmg := boss.touch_damage * float(m.get("dmg", 1.0))
	var o := boss.global_position
	match String(m.kind):
		"slam":
			_hurt_circle(o, float(m.r), dmg)
			boss._sfx("ground_hit", o, float(m.r) / 140.0)
		"sweep":
			_hurt_cone(o, _aim, float(m.arc), float(m.r), dmg)
			boss._sfx("ground_hit", o + _aim * float(m.r) * 0.5, float(m.r) / 280.0)
		"volley":
			_hurt_cone(o, _aim, float(m.spread), float(m.length), dmg)
			_shoot(int(m.arrows), float(m.spread))
		"pin":
			_hurt_line(o, _aim, float(m.length), float(m.width), dmg)
			_shoot(1, 0.0)
		"rain":
			for s in _spots:
				_hurt_circle(s, float(m.r), dmg)
				boss._sfx("ground_hit", s, float(m.r) / 140.0)
		"summon":
			_summon(m.get("adds", []))
		"charge", "backstep":
			state = S.DASH
			_dash_left = float(m.get("length", m.get("dist", 300.0)))
			_dash_hit.clear()
			boss.rig.play_loop("Walking")
			return
	_finish_move()


func _finish_move() -> void:
	state = S.RECOVER
	_t = float(_move.get("recover", 0.5))
	_gap = 1.2 * _cd_mult()
	if String(_move.get("kind", "")) == "charge":
		boss.rig.play_loop("Idle Blinking")  # winded: now is the time to hit it


func _dash(delta: float) -> void:
	var spd := float(_move.get("speed", 900.0))
	boss.velocity = _aim * spd
	boss.move_and_slide()
	_dash_left -= spd * delta
	if boss.get_slide_collision_count() > 0:
		_dash_left = 0.0
	if String(_move.kind) == "charge":
		var dmg := boss.touch_damage * float(_move.get("dmg", 1.0))
		for p in _victims():
			if not _dash_hit.has(p) and p.global_position.distance_to(boss.global_position) <= 70.0 + BODY:
				_dash_hit[p] = true
				p.take_damage(dmg, boss.element)
	if _dash_left <= 0.0:
		boss.velocity = Vector2.ZERO
		_finish_move()


## Everyone an attack can hurt: you, your hireling and the other players in a party.
func _victims() -> Array:
	var out := Enemy.players_of(get_tree(), boss.target)
	var h: Hireling = Hirelings.node
	if is_instance_valid(h) and h.is_inside_tree() and not h.dead:
		out.append(h)
	return out


func _hurt_circle(c: Vector2, r: float, dmg: float) -> void:
	for p in _victims():
		if p.global_position.distance_to(c) <= r + BODY:
			p.take_damage(dmg, boss.element)


func _hurt_cone(o: Vector2, dir: Vector2, arc: float, length: float, dmg: float) -> void:
	for p in _victims():
		var v: Vector2 = p.global_position - o
		var d := v.length()
		if d > length + BODY:
			continue
		if d < 1.0 or absf(angle_difference(dir.angle(), v.angle())) <= arc * 0.5 + atan2(BODY, maxf(d, 1.0)):
			p.take_damage(dmg, boss.element)


func _hurt_line(o: Vector2, dir: Vector2, length: float, width: float, dmg: float) -> void:
	for p in _victims():
		var v: Vector2 = p.global_position - o
		var along := v.dot(dir)
		var side := absf(v.dot(dir.orthogonal()))
		if along >= -BODY and along <= length + BODY and side <= width * 0.5 + BODY:
			p.take_damage(dmg, boss.element)


## Arrows flying down the cone's rays: only for show (the hit was resolved), here and in a party.
func _shoot(count: int, spread: float) -> void:
	var parts: Dictionary = RigSprite.skin_parts(boss.skin)
	for i in count:
		var dir := _aim
		if count > 1:
			dir = _aim.rotated(lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1)))
		var a := EnemyArrow.new()
		a.texture = parts.get("Arrow")
		a.global_position = boss.global_position + Vector2(0, -26.0 * boss.size_mult)
		a.dir = dir
		a.damage = 0.0
		a.maze = boss.maze
		boss.get_parent().add_child(a)
		Coop.host_fx("arrow", {"id": boss.net_id, "x": a.global_position.x, "y": a.global_position.y, "dx": dir.x, "dy": dir.y})


# ---------- adds and words ----------

func _summon(list: Array) -> void:
	_adds = _adds.filter(func(a): return is_instance_valid(a) and not a._dead)
	var cap := int(def.get("max_adds", 6))
	var parent := boss.get_parent()
	if parent == null:
		return
	for entry in list:
		for i in int(entry.get("n", 1)):
			if _adds.size() >= cap:
				return
			var at := boss.global_position + Vector2.from_angle(randf() * TAU) * randf_range(150.0, 240.0)
			if boss.maze != null and boss.maze.is_wall(boss.maze.world_to_cell(at)):
				at = boss.maze.random_floor_near(boss.global_position, 100.0, 240.0)
			var e: Enemy = parent.spawn_add(String(entry.kind), at) if parent.has_method("spawn_add") else _plain_add(String(entry.kind), at)
			if e != null:
				_adds.append(e)
	boss._flash_ring(boss.global_position, 100.0, Color(1.0, 0.7, 0.3))


## An add in a scene that has no spawn_add of its own.
func _plain_add(kind: String, at: Vector2) -> Enemy:
	var e := Enemy.new()
	e.target = boss.target
	e.maze = boss.maze
	e.max_hp = boss.max_hp / 12.0
	e.touch_damage = _base_touch * 0.5
	e.position = at
	e.set_kind(kind)
	boss.get_parent().add_child(e)
	e.wake()
	return e


func _say(text: String) -> void:
	said.emit(text)
	get_tree().call_group("boss_bar", "say", boss.display_name, text)
	Coop.host_fx("say", {"id": boss.net_id, "text": text})


func _on_boss_died(_at: Vector2) -> void:
	for a in _adds:
		if is_instance_valid(a) and not a._dead:
			a.hp = 0.0
			a._die()
	_adds.clear()


func _foe() -> Node2D:
	if boss._alive(boss._foe):
		return boss._foe
	return boss.target if boss._alive(boss.target) else null


func _stand() -> void:
	boss.velocity = Vector2.ZERO
	if not boss.rig.is_busy() and boss.rig.current_anim != "Idle Blinking":
		boss.rig.play_loop("Idle")
