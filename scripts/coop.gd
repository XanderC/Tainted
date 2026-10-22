class_name Coop
extends Node
## A rift or a story zone played by a party (Net.coop: kind "rift", or "zone"). Added by that scene
## (main.gd, zone.gd), which provides start_host() (start as a solo visit would: the first maze, the
## zone's packs) and coop_copy(e, d) (hook up a copy of the host's monster: what its death means
## here); a rift also remote_maze(d, instant) and party_travel(), and has `run`.
## One game hosts the instance (Net.role_changed: the first member in, or whoever is left when it
## goes): it runs the monsters (and a rift's mazes and run) as for a solo visit, and tells the others:
##   "maze"  which maze is loaded            "spawn" monsters as they appear (describe)
##   "snap"  where each is, its life...       "die"   which died ("gone": removed without dying)
##   "run"   the run's kills, time and stage  "fx"    an archer's arrow, to draw
##   "sync"  all of it at once, for a player just arrived ("hello")
## The other games (followers) show those monsters as copies (Enemy.remote) and send what their
## player and hireling do to them ("hits", "status") and when they step into a rift's portal
## ("travel"). A copy's death does here what a monster's death does (the scene's coop_copy): XP,
## quest credit, and loot rolled in this game, so each player's loot is their own.
## The host's monsters go for every player (RemotePlayer stands in for the others, and passes on
## what hits them: "hurt", "slow"). If the host leaves, the next player's copies become the real
## monsters (_take_over). A player who lost the connection and comes back (Net reconnects) starts
## again from what the host has now ("hello" -> "sync"), or hosts if nobody else is there.

const SNAP_HZ := 12.0
const RUN_HZ := 2.0
const HURT_EVERY := 0.1  ## damage to other players goes this often (burning ground hurts every frame)
const HP_PER_PLAYER := 0.6  ## monsters' life x (1 + this per extra player in the rift)

static var current: Coop = null

var main: Node2D  ## the rift scene (main.gd)
var is_host := false
var started := false
var _enemies := {}  # net id -> Enemy (the real ones on the host, copies elsewhere)
var _next_id := 1
var _spawns: Array = []
var _deaths: Array = []
var _gone: Array = []
var _hits: Array = []
var _hurt := {}  # host: damage to other players, gathered and sent every HURT_EVERY (peer -> amount)
var _hurt_t := 0.0
var _snap_t := 0.0
var _run_t := 0.0
var _resync := false  # the connection dropped: start again from the host's when back
var travel_asked := false  ## a follower asked the host to go through the portal (reset each maze)


func _ready() -> void:
	current = self
	Net.role_changed.connect(_on_role)
	Net.status_changed.connect(func():
		if Net.mode == Net.Mode.RECONNECTING:
			_resync = true)
	Net.event.connect(_on_event)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if current == self:
		current = null


static func active() -> bool:
	return current != null and is_instance_valid(current)


## Monsters' life multiplier for the players in the rift (the host scales what it spawns).
static func hp_scale() -> float:
	if not active():
		return 1.0
	return 1.0 + HP_PER_PLAYER * current.get_tree().get_nodes_in_group("remote_players").size()


# ---------- what a follower's monsters pass on ----------

static func forward_hit(id: int, amount: float, crit: bool, dtype: int, ailment: String) -> void:
	if active() and id != 0:
		current._hits.append([id, amount, crit, dtype, ailment])


static func forward_status(id: int, what: String, seconds: float) -> void:
	if active() and id != 0:
		Net.send_event(-1, "status", [id, what, seconds])


## The host's monster hit another player: their game takes it (gathered, sent every HURT_EVERY).
static func hurt_player(peer: int, amount: float) -> void:
	if active():
		current._hurt[peer] = float(current._hurt.get(peer, 0.0)) + amount


static func slow_player(peer: int, seconds: float) -> void:
	if active():
		Net.send_event(peer, "slow", seconds)


## Something the followers should see happen (the host's games only).
static func host_fx(kind: String, data: Dictionary) -> void:
	if active() and current.is_host and int(data.get("id", 0)) != 0:
		Net.send_event(0, "fx", [kind, data])


# ---------- roles ----------

func _on_role(host_id: int) -> void:
	var was := is_host
	is_host = host_id == Net.my_id()
	if not started:
		started = true
		if is_host:
			main.start_host()
		else:
			if _run() != null:
				_run().remote = true
			Net.send_event(-1, "hello", {})
	elif _resync:
		_resync = false
		_hits.clear()
		if is_host:
			if not was:
				_take_over()  # nobody else is here: what you see becomes the real thing
		else:
			# Someone else ran it meanwhile: drop what you have, take theirs
			for id in _enemies.keys():
				var e: Enemy = _enemies[id]
				if is_instance_valid(e):
					e.queue_free()
			_enemies.clear()
			_spawns.clear()
			_deaths.clear()
			_gone.clear()
			if _run() != null:
				_run().remote = true
			Net.send_event(-1, "hello", {})
	elif is_host and not was:
		_take_over()


## The scene's rift run, or null in a zone.
func _run() -> DungeonRun:
	var r = main.get("run")
	return r if r is DungeonRun else null


## The host left and this game hosts now: the copies become the real monsters, the run runs here.
func _take_over() -> void:
	for id in _enemies:
		var e: Enemy = _enemies[id]
		if is_instance_valid(e) and not e._dead:
			e.take_over(main.player)
		_next_id = maxi(_next_id, int(id) + 1)
	if _run() != null:
		_run().remote = false
		_run().announce("You lead the rift now", Color(0.6, 0.9, 1.0))


# ---------- the host: telling the others ----------

func _on_node_added(n: Node) -> void:
	if is_host and n is Enemy and not n.remote and n.net_id == 0:
		_track(n)


func _track(e: Enemy) -> void:
	e.net_id = _next_id
	_next_id += 1
	var id := e.net_id
	_enemies[id] = e
	_spawns.append(e)
	e.died.connect(func(_pos):
		if is_host:
			_deaths.append(id))
	e.tree_exiting.connect(func():
		_enemies.erase(id)
		if is_host and not e._dead:
			_gone.append(id))


## What a follower needs to make a copy of `e`.
static func describe(e: Enemy) -> Dictionary:
	return {"id": e.net_id, "kind": e.kind, "skin": e.skin, "name": e.display_name, "tier": e.tier,
		"affixes": Array(e.affixes), "max_hp": e.max_hp, "hp": e.hp, "speed": e.speed, "touch": e.touch_damage,
		"size": e.size_mult, "ranged": e.ranged, "boss": e.is_boss, "pack": e.pack, "aggro": e.aggro_range,
		"x": e.global_position.x, "y": e.global_position.y, "boss_id": String(e.get_meta("boss_id", ""))}


func _physics_process(delta: float) -> void:
	if is_host:
		_hurt_t -= delta
		if _hurt_t <= 0.0 and not _hurt.is_empty():
			_hurt_t = HURT_EVERY
			for peer in _hurt:
				Net.send_event(int(peer), "hurt", _hurt[peer])
			_hurt.clear()
		if not _spawns.is_empty():
			var list: Array = _spawns.filter(func(e): return is_instance_valid(e)).map(describe)
			_spawns.clear()
			Net.send_event(0, "spawn", list)
		if not _deaths.is_empty():
			Net.send_event(0, "die", _deaths.duplicate())
			_deaths.clear()
		if not _gone.is_empty():
			Net.send_event(0, "gone", _gone.duplicate())
			_gone.clear()
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = 1.0 / SNAP_HZ
			var snaps: Array = []
			for id in _enemies:
				var e: Enemy = _enemies[id]
				if is_instance_valid(e) and not e._dead:
					snaps.append(e.snapshot())
			if not snaps.is_empty():
				Net.send_event(0, "snap", snaps)
		_run_t -= delta
		if _run_t <= 0.0 and _run() != null:
			_run_t = 1.0 / RUN_HZ
			Net.send_event(0, "run", _run().net_state())
	elif not _hits.is_empty():
		Net.send_event(-1, "hits", _hits.duplicate())
		_hits.clear()


## Everything at once, for a player who just arrived.
func _sync_data() -> Dictionary:
	var list: Array = []
	for id in _enemies:
		var e: Enemy = _enemies[id]
		if is_instance_valid(e) and not e._dead:
			list.append(describe(e))
	return {"map": main.maze.map_id if main.maze != null else "", "n": main.get("mazes_visited"),
		"run": _run().net_state() if _run() != null else {}, "enemies": list}


## A new maze is loaded (the host): the others load it too.
func maze_loaded() -> void:
	if is_host:
		Net.send_event(0, "maze", {"map": main.maze.map_id, "n": main.mazes_visited})


# ---------- events ----------

func _on_event(from: int, kind: String, data: Variant) -> void:
	if is_host:
		match kind:
			"hello":
				Net.send_event(from, "sync", _sync_data())
			"hits":
				if data is Array:
					for h in data:
						var e: Enemy = _enemies.get(int(h[0])) if h is Array and h.size() == 5 else null
						if is_instance_valid(e) and not e._dead:
							e.take_damage(clampf(float(h[1]), 0.0, 1e7), bool(h[2]), int(h[3]), String(h[4]))
			"status":
				if data is Array and data.size() == 3:
					var e: Enemy = _enemies.get(int(data[0]))
					if is_instance_valid(e) and not e._dead:
						var secs := clampf(float(data[2]), 0.0, 10.0)
						match String(data[1]):
							"stun": e.stun(secs)
							"sunder": e.apply_sunder(secs)
							"taunt":
								for rp in get_tree().get_nodes_in_group("remote_players"):
									if rp.peer_id == from:
										e.taunt(rp, secs)
			"travel":
				if main.has_method("party_travel"):
					main.party_travel()
	else:
		match kind:
			"sync":
				if data is Dictionary:
					if main.has_method("remote_maze"):
						main.remote_maze(data, true)
					for d in data.get("enemies", []):
						_spawn_copy(d)
					if _run() != null:
						_run().apply_net_state(data.get("run", {}))
			"maze":
				if data is Dictionary and main.has_method("remote_maze"):
					main.remote_maze(data, false)
			"spawn":
				if data is Array:
					for d in data:
						_spawn_copy(d)
			"snap":
				if data is Array:
					for s in data:
						var e: Enemy = _enemies.get(int(s[0])) if s is Array and s.size() == 7 else null
						if is_instance_valid(e):
							e.apply_snapshot(s)
			"die":
				if data is Array:
					for id in data:
						var e: Enemy = _enemies.get(int(id))
						if is_instance_valid(e):
							e.remote_die()
			"gone":
				if data is Array:
					for id in data:
						var e: Enemy = _enemies.get(int(id))
						if is_instance_valid(e):
							e.queue_free()
			"run":
				if data is Dictionary and _run() != null:
					_run().apply_net_state(data)
			"fx":
				if data is Array and data.size() == 2:
					_fx(String(data[0]), data[1])
	match kind:  # either way: what the host's monsters did to you
		"hurt":
			if is_instance_valid(main.player) and not main.player.dead:
				main.player.take_damage(clampf(float(data), 0.0, 1e7))
		"slow":
			if is_instance_valid(main.player):
				main.player.apply_slow(clampf(float(data), 0.0, 10.0))


## A copy of the host's monster `d` (describe).
func _spawn_copy(d) -> void:
	if not d is Dictionary or (_enemies.has(int(d.get("id", 0))) and is_instance_valid(_enemies[int(d.id)]) \
			and not _enemies[int(d.id)].is_queued_for_deletion()):
		return
	var e := Enemy.new()
	e.remote = true
	e.net_id = int(d.id)
	e.kind = String(d.kind)
	e.skin = String(d.skin)
	e.display_name = String(d.name)
	e.tier = int(d.tier)
	e.affixes.assign(Array(d.affixes).map(func(a): return String(a)))
	e.max_hp = float(d.max_hp)
	e.speed = float(d.speed)
	e.touch_damage = float(d.touch)
	e.size_mult = float(d.size)
	e.ranged = bool(d.ranged)
	e.is_boss = bool(d.boss)
	e.pack = String(d.pack)
	e.aggro_range = float(d.aggro)
	e.position = Vector2(float(d.x), float(d.y))
	e.target = main.player
	e.maze = main.maze  # null until the first maze is known: a copy doesn't path-find anyway
	var id := e.net_id
	if String(d.get("boss_id", "")) != "":
		e.set_meta("boss_id", String(d.boss_id))
	e.tree_exiting.connect(func(): _enemies.erase(id))
	main.coop_copy(e, d)  # what its death means in this scene (connected before it can die)
	main.add_child(e)
	if e.pack != "":
		e.add_to_group(e.pack)
	e.hp = float(d.hp)
	_enemies[id] = e
	if e.is_boss and _run() != null:
		_run().boss_arrived(e)


## Draws what the host's monsters did that isn't a monster: an archer's arrow, a frost orb, a flash
## (harmless here: the host's game does the hurting).
func _fx(kind: String, d) -> void:
	if not d is Dictionary:
		return
	var who: Enemy = _enemies.get(int(d.get("id", 0)))
	if kind == "frost_orb" and is_instance_valid(who):
		who._frost_orb(Vector2(float(d.x), float(d.y)), false)
		return
	if kind == "ring":
		var ring := Node2D.new()
		main.add_child(ring)
		ring.global_position = Vector2(float(d.x), float(d.y))
		var r := clampf(float(d.get("r", 50.0)), 1.0, 600.0)
		var col := Color.from_string(String(d.get("c", "ffffff")), Color.WHITE)
		ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 5.0))
		ring.queue_redraw()
		var tw := ring.create_tween()
		tw.tween_property(ring, "modulate:a", 0.0, 0.35)
		tw.tween_callback(ring.queue_free)
		return
	if kind == "arrow" and d is Dictionary:
		var shooter: Enemy = _enemies.get(int(d.get("id", 0)))
		var a := EnemyArrow.new()
		a.texture = RigSprite.skin_parts(shooter.skin).get("Arrow") if is_instance_valid(shooter) else null
		a.position = Vector2(float(d.x), float(d.y))
		a.dir = Vector2(float(d.dx), float(d.dy)).normalized()
		a.damage = 0.0
		a.maze = main.maze
		main.add_child(a)
