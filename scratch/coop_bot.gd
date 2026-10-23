extends Node
## Plays a party rift with two bot players (run with a server, see net_bot.gd):
##   godot --headless --path . res://scratch/coop_bot.tscn -- --role=leader --name=Lead
##   godot --headless --path . res://scratch/coop_bot.tscn -- --role=follower --name=Fol
## The leader invites the follower and opens a rift; the follower joins. Whichever game got in first
## hosts it (runs the monsters) and never attacks; the other kills the host's monsters through its
## copies (their hits go to the host), asks the host through the portal when a maze is clear, and
## finishes the rift: its own loot from the boss. The guest uses its skills as it goes; the host
## checks it sees them on its copy of the guest. Each prints "<host|guest>: N checks, M failed".
## Survives the scene changes (a copy of it runs at the root).
## Zone: --zone takes both into the Dune Wastes instead (the leader first): the guest kills the host's
## monsters there and checks its copies die, give XP and drop its own loot.
## Reconnect: --drop-at=6 makes the guest lose its connection 6 s into the rift (it uses no skills then, or it would be over); it should come back
## into the rift, pick up the host's monsters again and still finish it.
## Handover: --leave-after=12 makes the host quit 12 s into the rift; the guest with --takeover then
## checks it took over (hosts, its copies are real monsters, the run runs there).
## Affixes: --affixes (both) has the host clear its monsters, step away and set a molten, frozen,
## electrified legendary on the guest; the guest pokes it, then kills it, and checks what reached it:
## frost orbs (seen and slowing it), sparks, burning ground and the death blast.
## Allies: --allies (both) gives each a hireling; the guest also calls the Ancients, and the host
## checks it sees the guest's hireling and Ancients beside it.
## Revive: --revive (both): the guest falls and stays down in the rift; the host stands by it and
## revives it (half life); the host falls and its monsters still go for the guest; the guest falls
## too and the rift fails for both.
## Levels: --levels: the leader has reached rift 3, the follower rift 1. The leader asks for a level 7
## party rift and gets 3 (no higher than it has reached); the Rift Gate lists both; a clear in time
## unlocks 4 for the leader and only 2 for the follower.
## Go to: --goto: in town the follower has an arrow to the leader; the leader goes into the Dune
## Wastes; the follower's "go to" takes it there, beside the leader.

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
var _affixes := false
var _elite: Enemy              # host: the legendary it set on the guest
var _elite_copy: Enemy         # guest: its copy of it
var _copy_at := -1.0
var _killed_at := -1.0
var _poke_t := 0.0
var _fx_seen := {}             # guest: "frost_orb", "spark" -> count
var _hurt_total := 0.0
var _hurt_after_death := 0.0
var _guest_seen := false
var _elite_set := false
var _skill_t := 0.0
var _fx_drawn := 0  # host: frames the guest's copy showed one of its skills
var _allies := false
var _called := false
var _ally_kinds := {}  # host: the guest's allies it saw ("h", "a0"...)
var _revive := false
var _phase := 0
var _phase_t := 0.0
var _hurt_while_host_down := 0
var _levels := false
var _goto := false
var _went := false
var _arrow_seen := false
var _guest_left := false
var _addr := "127.0.0.1"  ## --addr: the server (a load test runs many pairs against one)
var _partner := ""        ## --partner=Name: the leader invites only that player (else the first it sees)


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
		elif a == "--affixes": _affixes = true
		elif a == "--allies": _allies = true
		elif a == "--revive": _revive = true
		elif a == "--levels": _levels = true
		elif a == "--goto": _goto = true
		elif a.begins_with("--addr="): _addr = a.get_slice("=", 1)
		elif a.begins_with("--key="): Net.test_key = a.get_slice("=", 1).rpad(40, "0")
		elif a.begins_with("--partner="): _partner = a.get_slice("=", 1)
	GameState.char_name = bot_name
	GameState.appearance = Appearance.random_look()
	GameState.give_starter_skills()
	# The old Warrior skills (their swings, spins and rings are what the host looks for on its copy),
	# and the Strength they need
	for i in 4:
		GameState.skill_slots[i].skill = ["cleave", "whirlwind", "leap_slam", "battle_cry"][i]
	GameState.attributes = {"str": 45}
	if _levels:
		GameState.rift_unlocked = 3 if role == "leader" else 1
		GameState.rift_level = GameState.rift_unlocked
	if _allies:
		var c := HirelingDB.roll_candidate("sellsword", 5)
		c["dead"] = false
		c["xp"] = 0.0
		c["attributes"] = {}
		GameState.hireling = c
		GameState.hireling_gear = {}
		GameState.hireling_flasks = [null, null]
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
		if kind == "hurt":
			_hurt_total += float(data)
			if _revive and _phase == 3:
				_hurt_while_host_down += 1
			if _killed_at >= 0.0:
				_hurt_after_death += float(data)
		elif kind == "fx" and data is Array and data.size() == 2:
			var what := String(data[0])
			if what == "ring" and is_equal_approx(float(data[1].get("r", 0.0)), 160.0):
				what = "spark"
			_fx_seen[what] = int(_fx_seen.get(what, 0)) + 1
		if kind in ["spawn", "die"] and int(_events[kind]) <= 3:
			print("%s: event %s %s" % [bot_name, kind, str(data).left(160)]))
	await get_tree().create_timer(0.5).timeout
	Net.join(_addr)
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	Net.enter(Net.TOWN)
	if _goto and role == "follower":
		get_tree().change_scene_to_file("res://scenes/town.tscn")  # the real town: its arrows, its "go to"
	if role == "leader":
		var mate := func() -> int:
			for id in Net.others:
				if _partner == "" or String(Net.others[id].get("name", "")) == _partner:
					return int(id)
			return 0
		while mate.call() == 0:
			await get_tree().create_timer(0.5).timeout
		Net.invite(mate.call())
		while Net.party.get("members", []).size() < 2:
			await get_tree().create_timer(0.3).timeout
		if _zone:
			ActDB.travel(get_tree(), "dune_wastes", "start")
		elif _goto:
			await get_tree().create_timer(3.0).timeout  # the follower sees it in town first
			ActDB.travel(get_tree(), "dune_wastes", "start")
		elif _levels:
			await get_tree().create_timer(1.0).timeout  # the party list with both members' highest
			var text := RiftSelectUI._party_text()
			_check("Lead [b]3[/b]" in text and "Fol [b]1[/b]" in text, "the Rift Gate lists each member's highest (%s)" % text.get_slice("\n", 2))
			Net.open_party_rift(7)
		else:
			GameState.rift_level = 1
			Net.open_party_rift(1)


func _process(delta: float) -> void:
	if not runner:
		return
	_t += delta
	var scene := get_tree().current_scene
	if _goto and role == "follower" and scene != null and scene.scene_file_path.ends_with("town.tscn") and Net.in_party():
		var lead := int(Net.party.leader)
		for np in scene.find_children("*", "NetPresence", true, false):
			if np._arrows.has(lead):
				_arrow_seen = true
		if not _went and Net.member_place(lead) == "zone":
			_check(_arrow_seen, "an arrow pointed to the party member in town")
			_went = Net.go_to(lead)
			_check(_went, "Go to them: the member's zone")
	var main = scene if scene != null and (scene.scene_file_path.ends_with("main.tscn") or scene.scene_file_path.ends_with("zone.tscn")) else null
	if main != null and main.maze != null:
		if not _in_rift:
			_in_rift = true
			_xp0 = GameState.xp + GameState.level * 100000.0
			print("%s: in the rift, maze %s, hosting %s" % [bot_name, main.maze.map_id, Net.is_instance_host()])
		_mazes[main.maze.map_id] = true
		_most_players = maxi(_most_players, get_tree().get_nodes_in_group("remote_players").size())
		for rp in get_tree().get_nodes_in_group("remote_players"):
			if rp._swing_t > 0.0 or rp._ring_t > 0.0 or rp._spin_t > 0.0:
				_fx_drawn += 1
		for a in get_tree().get_nodes_in_group("remote_allies"):
			_ally_kinds[a.kind] = true
		_rift_t += delta
		if _leave_after > 0.0 and role == "leader" and _rift_t > _leave_after and Net.is_instance_host():
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
		if _affixes:
			_affix_step(main, delta)
			return
		if _revive:
			_revive_step(main, delta)
			return
		if _goto:
			_goto_step(main)
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
	if _allies and not _called and _rift_t > 3.0:
		_called = true
		main.player._do_call_ancients(SkillTree.get_skill("ancients"))
		print("%s: called the Ancients (hireling: %s)" % [bot_name, is_instance_valid(Hirelings.node)])
	_skill_t -= delta
	if _skill_t <= 0.0 and _drop_at <= 0.0 and not _takeover:  # skills clear a rift in seconds: too soon to drop
		_skill_t = 0.6
		main.player.resource = main.player.max_resource()
		for i in main.player.skills.size():
			main.player._cooldowns[i] = 0.0
			main.player.use_skill(i)  # its swings and rings: the host should see them
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
		if _drop_at <= 0.0:  # (a guest that will drop uses no skills)
			_check(int(_events.get("pfx", 0)) > 0 and _fx_drawn > 0, "it sees the guest's skills (%d sent, %d frames shown)" % [int(_events.get("pfx", 0)), _fx_drawn])
		if _allies:
			_check(_ally_kinds.has("h"), "it sees the guest's hireling (%s)" % [_ally_kinds.keys()])
			_check(_ally_kinds.has("a0") and _ally_kinds.has("a1") and _ally_kinds.has("a2"), "it sees the guest's Ancients")
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
	if _levels and main != null:
		_check(main.run.level == 3, "the party's rift is at the opener's highest, not above (%d)" % main.run.level)
		var want := 4 if role == "leader" else 2
		_check(GameState.rift_unlocked == want, "a clear in time unlocks the next level for it: %d (%d)" % [want, GameState.rift_unlocked])
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


## Go to: the leader waits in the zone; the follower, there by "go to", checks it stands beside it.
func _goto_step(main) -> void:
	main.player.hp = main.player.stats.get_stat("max_life")
	var others := get_tree().get_nodes_in_group("remote_players")
	if role == "leader":
		if not others.is_empty():
			_guest_seen = true
		elif _guest_seen:
			_guest_left = true
		if _guest_left or _t > secs:
			set_process(false)
			_check(_guest_seen, "the follower came to it")
			print("goto leader: %d checks, %d failed" % [_checks, _failed])
			Net.leave()
			get_tree().quit(1 if _failed > 0 else 0)
		return
	if others.is_empty() or _rift_t < 1.0:
		if _rift_t > 25.0:
			set_process(false)
			_check(false, "it arrives beside the leader (never saw it)")
			print("goto follower: %d checks, %d failed" % [_checks, _failed])
			get_tree().quit(1)
		return
	var d: float = main.player.global_position.distance_to(others[0]._target)
	set_process(false)
	_check(main.get("zone_id") == "dune_wastes", "it is in the leader's zone (%s)" % main.get("zone_id"))
	_check(d < 120.0, "it arrives beside the leader (%d away)" % int(d))
	print("goto follower: %d checks, %d failed" % [_checks, _failed])
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


## Revive: see the top. The guest leads the steps; the host answers what it sees of the guest.
func _revive_step(main, delta: float) -> void:
	_phase_t += delta
	var p: Player = main.player
	var others := get_tree().get_nodes_in_group("remote_players")
	var other = others[0] if not others.is_empty() else null
	var fall: Array = main.get_children().filter(func(n): return n is PartyDeath)
	if Net.is_instance_host():
		match _phase:
			0:  # wait for the guest to fall, then stand by it
				p.hp = p.stats.get_stat("max_life")
				if other != null and other.dead:
					_phase = 1
					print("%s: the guest is down, going to it" % bot_name)
			1:
				p.hp = p.stats.get_stat("max_life")
				if other != null:
					p.global_position = other.global_position + Vector2(30, 0)
					if not other.dead:
						_check(true, "it revived the guest by standing beside it")
						_phase = 2
						_phase_t = 0.0
				if _phase_t > 15.0:
					_check(false, "it revived the guest by standing beside it")
					_phase = 2
			2:  # a moment, then it falls itself
				p.hp = p.stats.get_stat("max_life")
				if _phase_t > 3.0:
					p.take_damage(1.0e7)
					print("%s: fell on purpose" % bot_name)
					_phase = 3
					_phase_t = 0.0
			3:  # the guest falls too: the rift fails
				if main.run.state == DungeonRun.State.FAILED:
					_check(p.dead and other != null and other.dead, "the rift fails once everyone is down")
					_phase = 4
					_phase_t = 0.0
				elif _phase_t > 25.0:
					_check(false, "the rift fails once everyone is down (%s)" % main.run.state)
					_phase = 4
			4:
				if _phase_t > 3.0:
					set_process(false)
					print("revive host: %d checks, %d failed" % [_checks, _failed])
					Net.leave()
					get_tree().quit(1 if _failed > 0 else 0)
		return
	match _phase:
		0:  # in the rift a while, then fall
			p.hp = p.stats.get_stat("max_life")
			if _rift_t > 6.0:
				p.take_damage(1.0e7)
				_phase = 1
				_phase_t = 0.0
		1:
			if _phase_t > 0.5:
				_check(p.dead and get_tree().current_scene == main, "falling in a party's rift keeps it in the rift")
				_check(not fall.is_empty() and fall[0]._layer.visible, "it waits to be revived")
				_check(main.run.state != DungeonRun.State.FAILED, "the rift goes on while the host stands")
				_phase = 2
				_phase_t = 0.0
		2:  # the host comes and revives it
			if not p.dead:
				var frac := p.hp / p.stats.get_stat("max_life")
				_check(frac > 0.4 and frac < 0.6, "revived at half life (%d%%)" % int(frac * 100.0))
				_check(not fall[0]._layer.visible, "the fallen screen goes")
				_phase = 3
				_phase_t = 0.0
				_hurt_while_host_down = 0
			elif _phase_t > 20.0:
				_check(false, "revived by the host")
				_phase = 4
		3:  # the host falls; its monsters still come for it
			p.hp = p.stats.get_stat("max_life")
			var foes := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.remote and not e._dead)
			if not foes.is_empty():
				p.global_position = foes[0].global_position + Vector2(40, 0)  # stands among them, never hitting
			if other != null and other.dead and _phase_t > 6.0:
				_check(_hurt_while_host_down > 0, "the host's monsters still fight it while the host is down (%d hits)" % _hurt_while_host_down)
				p.take_damage(1.0e7)
				_phase = 4
				_phase_t = 0.0
			elif _phase_t > 30.0:
				_check(false, "the host fell")
				_phase = 4
		4:
			if (main.run.state == DungeonRun.State.FAILED and _phase_t > 1.0) or _phase_t > 15.0:  # its screen a frame behind
				_check(main.run.state == DungeonRun.State.FAILED, "the rift fails for it too")
				_check(not fall.is_empty() and not fall[0]._get_up.visible, "no getting up in a failed rift")
				set_process(false)
				print("revive guest: %d checks, %d failed" % [_checks, _failed])
				await get_tree().create_timer(1.0).timeout
				Net.leave()
				get_tree().quit(1 if _failed > 0 else 0)


## Affixes: the host sets a legendary on the guest; the guest checks what of it reaches its game.
func _affix_step(main, delta: float) -> void:
	if is_instance_valid(main.player) and not main.player.dead:
		main.player.hp = main.player.stats.get_stat("max_life")
	var others := get_tree().get_nodes_in_group("remote_players")
	if Net.is_instance_host():
		if not _elite_set and others.size() == 1 and _rift_t > 4.0:
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()  # only the legendary: whatever else reaches the guest is its
			var guest: Node2D = others[0]
			main.player.global_position = main.maze.random_floor_near(guest.global_position, 700.0, 900.0)
			var e := Enemy.new()
			e.position = guest.global_position + Vector2(40, 0)
			e.target = main.player
			e.maze = main.maze
			e.max_hp = 5000.0
			e.touch_damage = 4.0
			e.set_kind("zombie")
			var aff: Array[String] = ["molten", "frozen", "electrified"]
			e.make_elite(MonsterAffix.Tier.LEGENDARY, aff)
			main.add_child(e)
			e.wake()
			_elite = e
			_elite_set = true
			print("%s: set a legendary (%s) on the guest" % [bot_name, ", ".join(aff)])
		if others.size() == 1:
			_guest_seen = true
		if (_guest_seen and others.is_empty()) or _t > secs:
			set_process(false)
			_check(_elite_set, "it set the legendary on the guest")
			print("affixes host: %d checks, %d failed" % [_checks, _failed])
			Net.leave()
			get_tree().quit(1 if _failed > 0 else 0)
		return
	if _copy_at < 0.0:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.remote and e.has_affix("frozen"):
				_elite_copy = e
				_copy_at = _rift_t
				_hurt_total = 0.0
				print("%s: the legendary's copy is here" % bot_name)
		return
	if _killed_at < 0.0:
		_poke_t -= delta
		if _poke_t <= 0.0 and is_instance_valid(_elite_copy):
			_poke_t = 0.3
			_elite_copy.take_damage(1.0)  # its sparks jump at whoever is near when it's hit
		if _rift_t - _copy_at > 16.0:
			_elite_copy.take_damage(1.0e6)
			_killed_at = _rift_t
			_hurt_after_death = 0.0
			print("%s: killed it" % bot_name)
		return
	if _rift_t - _killed_at < 3.5:
		return
	set_process(false)
	_check(int(_fx_seen.get("frost_orb", 0)) > 0, "it sees the legendary's frost orbs (%d)" % int(_fx_seen.get("frost_orb", 0)))
	_check(int(_events.get("slow", 0)) > 0, "frost orb bursts slow it (%d)" % int(_events.get("slow", 0)))
	_check(int(_fx_seen.get("spark", 0)) > 0, "its sparks jump to it when hit (%d)" % int(_fx_seen.get("spark", 0)))
	_check(_hurt_total > 0.0, "the legendary hurts it (%.0f)" % _hurt_total)
	_check(_hurt_after_death > 0.0, "the molten death blast hurts it (%.0f)" % _hurt_after_death)
	print("%s: events %s fx %s" % [bot_name, _events, _fx_seen])
	print("affixes guest: %d checks, %d failed" % [_checks, _failed])
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
