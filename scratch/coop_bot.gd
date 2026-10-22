extends Node
## Plays a party rift with two bot players (run with a server, see net_bot.gd):
##   godot --headless --path . res://scratch/coop_bot.tscn -- --role=leader --name=Lead
##   godot --headless --path . res://scratch/coop_bot.tscn -- --role=follower --name=Fol
## The leader invites the follower and opens a rift; the follower joins. Whichever game got in first
## hosts it (runs the monsters) and never attacks; the other kills the host's monsters through its
## copies (their hits go to the host), asks the host through the portal when a maze is clear, and
## finishes the rift: its own loot from the boss. Each prints "<host|guest>: N checks, M failed".
## Survives the scene changes (a copy of it runs at the root).
## Zone: --zone takes both into the Dune Wastes instead (the leader first): the guest kills the host's
## monsters there and checks its copies die, give XP and drop its own loot.
## Reconnect: --drop-at=15 makes the guest lose its connection 15 s into the rift; it should come back
## into the rift, pick up the host's monsters again and still finish it.
## Handover: --leave-after=12 makes the host quit 12 s into the rift; the guest with --takeover then
## checks it took over (hosts, its copies are real monsters, the run runs there).

var role := "leader"
var bot_name := "Bot"
var secs := 150.0
var _t := 0.0
var _checks := 0
var _failed := 0
var _in_rift := false
var _attack_t := 0.0
var _remote_deaths := 0  # leader: its monsters killed by the follower's hits
var _copies_seen := {}   # follower: monster ids it had copies of
var _copy_deaths := 0
var _xp0 := 0.0
var _mazes := {}
var _asked_travel := 0.0
var _events := {}
var _done_at := -1.0
var _most_players := 0
var _leave_after := 0.0
var _takeover := false
var _rift_t := 0.0
var _host_since := -1.0
var _was_guest := false
var _zone := false
var _drop_at := 0.0
var _drop_done := false
var _back_in := false
var _drops_seen := 0
var _shot_taken := false


var runner := false  # the copy that runs, at the root (the scene itself is replaced on travel)


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.get_slice("=", 1)
		elif a.begins_with("--name="): bot_name = a.get_slice("=", 1)
		elif a.begins_with("--secs="): secs = float(a.get_slice("=", 1))
		elif a.begins_with("--leave-after="): _leave_after = float(a.get_slice("=", 1))
		elif a == "--takeover": _takeover = true
		elif a == "--zone": _zone = true
		elif a.begins_with("--drop-at="): _drop_at = float(a.get_slice("=", 1))
	GameState.char_name = bot_name
	GameState.appearance = Appearance.random_look()
	GameState.give_starter_skills()
	Net.status_changed.connect(func(): print("%s: %s" % [bot_name, Net.status]))
	Net.notice.connect(func(t): print("%s: notice: %s" % [bot_name, t]))
	Net.party_portal.connect(func(p):
		print("%s: portal %s" % [bot_name, p])
		if role == "follower":
			if _takeover or _drop_at > 0.0:
				await get_tree().create_timer(3.0).timeout  # let the leader host
			Net.join_portal(p))
	Net.invited.connect(func(from_id, _n):
		if role == "follower":
			Net.answer_invite(from_id, true)
			if _zone:
				await get_tree().create_timer(4.0).timeout  # the leader goes first and hosts
				ActDB.travel(get_tree(), "dune_wastes", "start"))
	Net.role_changed.connect(func(h): print("%s: instance host %d (me %d)" % [bot_name, h, Net.my_id()]))
	get_tree().node_added.connect(_watch_leader_enemy)
	Net.event.connect(func(_from, kind, data):
		_events[kind] = int(_events.get(kind, 0)) + 1
		if kind in ["spawn", "die"] and int(_events[kind]) <= 3:
			print("%s: event %s %s" % [bot_name, kind, str(data).left(160)]))
	await get_tree().create_timer(0.5).timeout
	Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	Net.enter(Net.TOWN)
	if role == "leader":
		while Net.others.is_empty():
			await get_tree().create_timer(0.5).timeout
		Net.invite(Net.others.keys()[0])
		while Net.party.get("members", []).size() < 2:
			await get_tree().create_timer(0.3).timeout
		if _zone:
			ActDB.travel(get_tree(), "dune_wastes", "start")
		else:
			GameState.rift_level = 1
			Net.open_party_rift(1)


func _process(delta: float) -> void:
	if not runner:
		return
	_t += delta
	var scene := get_tree().current_scene
	var main = scene if scene != null and (scene.scene_file_path.ends_with("main.tscn") or scene.scene_file_path.ends_with("zone.tscn")) else null
	if main != null and main.maze != null:
		if not _in_rift:
			_in_rift = true
			_xp0 = GameState.xp + GameState.level * 100000.0
			print("%s: in the rift, maze %s, hosting %s" % [bot_name, main.maze.map_id, Net.is_instance_host()])
		_mazes[main.maze.map_id] = true
		_most_players = maxi(_most_players, get_tree().get_nodes_in_group("remote_players").size())
		_rift_t += delta
		if _leave_after > 0.0 and _rift_t > _leave_after and Net.is_instance_host():
			print("%s: leaving the rift mid-run" % bot_name)
			Net.leave()
			get_tree().quit(0)
			return
		if _drop_at > 0.0 and not _drop_done and _rift_t > _drop_at and not Net.is_instance_host():
			_drop_done = true
			print("%s: dropping the connection mid-rift" % bot_name)
			Net.simulate_drop()
		if _drop_done and not _back_in and Net.online() and Net.instance == String(Net.coop.get("inst", "?")):
			_back_in = true
			print("%s: back in the rift after reconnecting" % bot_name)
		if not Net.is_instance_host():
			_was_guest = true
		if _zone:
			_zone_step(main, delta)
			return
		if _takeover and _was_guest and Net.is_instance_host():
			if _host_since < 0.0:
				_host_since = _rift_t
			elif _rift_t - _host_since > 3.0:
				_finish_takeover(main)
				return
		if "--shot" in OS.get_cmdline_user_args() and not _shot_taken and _t > 14.0 and DisplayServer.get_name() != "headless":
			_shot_taken = true
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/coop_%s.png" % role))
			print("%s: saved coop_%s.png" % [bot_name, role])
		if is_instance_valid(main.player) and not main.player.dead:
			main.player.hp = main.player.stats.get_stat("max_life")  # a bot that stands in the crowd: kept alive
		if not Net.is_instance_host():
			_follow(main, delta)
		elif main.run.state == DungeonRun.State.COMPLETE:
			if _done_at < 0.0:
				_done_at = _t
			elif _t - _done_at > 8.0:  # the guest finishes too before the host goes
				_finish(main)
	if _t > secs:
		_finish(main)


## The leader: count its monsters dying while it never attacks (the follower's hits did it).
func _watch_leader_enemy(n: Node) -> void:
	if n is Enemy and not n.remote and Net.is_instance_host():
		n.died.connect(func(_p): _remote_deaths += 1)


## The follower: kill the host's monsters through their copies, ask for the portal when clear.
func _follow(main, delta: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.remote:
			if not _copies_seen.has(e.net_id):
				_copies_seen[e.net_id] = true
				e.died.connect(func(_p): _copy_deaths += 1)
	_attack_t -= delta
	if _attack_t > 0.0:
		return
	_attack_t = 0.25
	var alive := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.remote and not e._dead)
	if not alive.is_empty():
		var e: Enemy = alive[0]
		main.player.global_position = e.global_position + Vector2(60, 0)  # walk up to it (a bot may)
		e.take_damage(e.max_hp * 0.6, false)  # two hits each: goes to the host
	elif main.run.state == DungeonRun.State.FIGHTING and _t - _asked_travel > 3.0:
		_asked_travel = _t
		main.player.global_position = main.portal.global_position  # into the portal: the host takes us through
	if main.run.state == DungeonRun.State.COMPLETE:
		_finish(main)


func _finish(main) -> void:
	set_process(false)
	var hosting := Net.is_instance_host()
	if hosting:
		_check(_in_rift, "the host is in the rift")
		_check(_remote_deaths >= 10, "its monsters die from the follower's hits (%d)" % _remote_deaths)
		_check(_most_players == 1, "the other player is in the rift with it")
		_check(main != null and main.run.state == DungeonRun.State.COMPLETE, "the rift is completed (%s)" % [main.run.state if main else "?"])
	else:
		_check(_in_rift, "the guest is in the rift")
		_check(_copies_seen.size() >= 10, "it gets copies of the host's monsters (%d)" % _copies_seen.size())
		_check(_copy_deaths >= 10, "its copies die when the host's do (%d)" % _copy_deaths)
		_check(GameState.xp + GameState.level * 100000.0 > _xp0, "it gains XP from the kills")
		_check(_mazes.size() >= 1, "it loads the host's mazes (%d)" % _mazes.size())
		_check(main != null and main.run.state == DungeonRun.State.COMPLETE, "it finishes the rift (%s)" % [main.run.state if main else "?"])
		_check(main != null and main.run.rewards.size() >= 2, "the boss drops it its own loot (%d items)" % (main.run.rewards.size() if main else 0))
		if _drop_at > 0.0:
			_check(_drop_done and _back_in, "it dropped mid-rift and came back into it")
	print("%s: events %s" % [bot_name, _events])
	print("%s: %d checks, %d failed" % ["host" if hosting else "guest", _checks, _failed])
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


## A zone: the guest kills the host's monsters through its copies; both finish after enough deaths.
func _zone_step(main, delta: float) -> void:
	if Net.is_instance_host():
		if _remote_deaths >= 12 or _t > secs:
			_finish_zone(main, true)
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.remote and not _copies_seen.has(e.net_id):
			_copies_seen[e.net_id] = true
			e.died.connect(func(_p): _copy_deaths += 1)
	_drops_seen = get_tree().get_nodes_in_group("currency_pickups").size() + \
		main.get_children().filter(func(n): return n is LootPickup).size()
	_attack_t -= delta
	if _attack_t <= 0.0:
		_attack_t = 0.25
		var alive := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.remote and not e._dead)
		if not alive.is_empty():
			var e: Enemy = alive[0]
			main.player.global_position = e.global_position + Vector2(60, 0)
			e.take_damage(e.max_hp * 0.6, false)
	if _copy_deaths >= 15 or _t > secs:
		_finish_zone(main, false)


func _finish_zone(main, hosting: bool) -> void:
	set_process(false)
	_check(main != null and main.coop != null, "in the party's zone")
	if hosting:
		_check(_remote_deaths >= 12, "its monsters die from the guest's hits (%d)" % _remote_deaths)
		_check(_most_players == 1, "the guest is in the zone with it")
	else:
		_check(_copies_seen.size() >= 15, "it gets copies of the host's monsters (%d)" % _copies_seen.size())
		_check(_copy_deaths >= 15, "its copies die when the host's do (%d)" % _copy_deaths)
		_check(GameState.xp + GameState.level * 100000.0 > _xp0, "it gains XP from the kills")
		_check(_drops_seen > 0, "its own loot drops in its game (%d)" % _drops_seen)
	print("zone %s: %d checks, %d failed" % ["host" if hosting else "guest", _checks, _failed])
	await get_tree().create_timer(4.0 if hosting else 1.0).timeout
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _finish_takeover(main) -> void:
	set_process(false)
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check(_copies_seen.size() > 0, "it had copies of the host's monsters before (%d)" % _copies_seen.size())
	_check(Net.is_instance_host(), "it hosts the rift once the host has gone")
	_check(not enemies.is_empty() and enemies.all(func(e): return not e.remote), "the copies are real monsters now (%d)" % enemies.size())
	_check(not main.run.remote, "the run runs in its game now")
	print("takeover: %d checks, %d failed" % [_checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
