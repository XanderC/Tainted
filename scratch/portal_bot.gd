extends Node
## Town portals in a party's rift, with two bot players and a server (see net_bot.gd):
##   godot --headless --path . res://scratch/portal_bot.tscn -- --role=leader --name=Lead
##   godot --headless --path . res://scratch/portal_bot.tscn -- --role=follower --name=Fol
## The leader opens a rift and reads a scroll; the follower sees the leader's portal, goes through it
## to town and finds the way back there. The leader reads another (it replaces the first, in town
## too), then goes through last: the rift waits. The follower goes back in through the leader's
## portal and carries the rift on (the same maze and monsters, hosting it now). The leader comes back
## through its own portal (it closes). The follower reads one; the leader sees it, and sees it close
## when the rift moves on to its next maze. Each prints "<role>: N checks, M failed".

var role := "leader"
var bot_name := "Bot"
var secs := 120.0
var runner := false
var _checks := 0
var _failed := 0
var _t := 0.0
var _done := false


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
	GameState.char_name = bot_name
	GameState.appearance = Appearance.random_look()
	GameState.give_starter_skills()
	GameState.tp_scrolls = 5
	Net.notice.connect(func(t): print("%s: notice: %s" % [bot_name, t]))
	Net.invited.connect(func(from_id, _n):
		if role == "follower":
			Net.answer_invite(from_id, true))
	Net.party_portal.connect(func(p):
		if role == "follower" and int(p.get("by", 0)) != Net.my_id():
			await _wait(2.0)  # the leader goes in first and hosts
			Net.join_portal(p))
	await _wait(0.5)
	Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/town.tscn")
	await _wait(1.0)
	if role == "leader":
		await _until(func(): return not Net.others.is_empty(), 20.0)
		Net.invite(int(Net.others.keys()[0]))
		await _until(func(): return Net.party.get("members", []).size() >= 2, 10.0)
		GameState.rift_level = 1
		Net.open_party_rift(1)
		await _leader()
	else:
		await _follower()
	_finish()


func _process(delta: float) -> void:
	if not runner:
		return
	_t += delta
	var p = GameState.player
	if is_instance_valid(p) and p.is_inside_tree() and not p.dead and p.stats != null:
		p.hp = p.stats.get_stat("max_life")  # bots standing about: kept alive
	if _t > secs and not _done:
		print("%s: out of time" % bot_name)
		_finish()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print("%s: %s %s" % [bot_name, "ok:  " if ok else "FAIL:", what])
	if not ok:
		_failed += 1


func _finish() -> void:
	if _done:
		return
	_done = true
	print("%s %s: %d checks, %d failed" % ["portal", role, _checks, _failed])
	Net.leave()
	get_tree().quit(0)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, timeout: float) -> bool:
	var end := _t + timeout
	while not cond.call():
		if _t > end:
			return false
		await get_tree().process_frame
	return true


## The rift scene once its maze is known, else null.
func _rift():
	var s := get_tree().current_scene
	return s if s != null and s.scene_file_path.ends_with("main.tscn") and s.maze != null and not s._travelling else null


func _in_town() -> bool:
	var s := get_tree().current_scene
	return s != null and s.scene_file_path.ends_with("town.tscn")


func _other() -> int:
	for m in Net.party.get("members", []):
		if int(m.id) != Net.my_id():
			return int(m.id)
	return 0


## The other member's open portal as the party has it ({} for none).
func _their_tp() -> Dictionary:
	var tp = Net.party.get("tps", {}).get(_other(), {})
	return tp if tp is Dictionary else {}


func _node_of(tp_id) -> TownPortal:
	for n in get_tree().get_nodes_in_group("town_portals"):
		if int(n.tp_id) == int(tp_id) and not n.is_queued_for_deletion():
			return n
	return null


func _go_through(n: TownPortal) -> void:
	GameState.player.global_position = n.global_position
	n._plate.pressed.emit()
	await _wait(0.5)


func _alive_monsters() -> int:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return not e._dead and not e.is_queued_for_deletion()).size()


func _leader() -> void:
	var fol := 0
	if not await _until(func(): return _rift() != null and not Net.others.is_empty(), 25.0):
		_check(false, "both in the party's rift")
		return
	fol = _other()
	var m = _rift()
	_check(Net.is_instance_host(), "the leader hosts the rift")
	m.player.global_position = m.maze.random_floor_near(m.maze.start_pos, 120.0, 200.0)
	_check(TownPortals.read_scroll(m), "the leader reads a scroll in the party's rift")
	await _until(func(): return String(Net.member_where.get(fol, "")).begins_with("rift:"), 10.0)  # (it said town a moment ago)
	await _until(func(): return String(Net.member_where.get(fol, "")).begins_with(Net.TOWN), 25.0)
	_check(true, "the follower went to town (through the leader's portal)")
	await _wait(1.0)
	m.player.global_position = m.maze.random_floor_near(m.player.global_position, 150.0, 250.0)
	var first := int(GameState.town_portal.get("id", 0))
	TownPortals.read_scroll(m)
	var mine: Dictionary = GameState.town_portal
	await get_tree().process_frame
	var ps := get_tree().get_nodes_in_group("town_portals").filter(func(x): return not x.is_queued_for_deletion())
	_check(int(mine.id) != first and ps.size() == 1 and int(ps[0].tp_id) == int(mine.id), "reading another replaces it")
	await _wait(3.0)  # the follower sees the new one in town
	await _go_through(_node_of(mine.id))
	await _until(_in_town, 10.0)
	await _wait(1.0)
	_check(_in_town() and _node_of(mine.id) != null and "Portal: Rift 1" in _node_of(mine.id)._plate.text,
		"through it last, to town: the way back stands there")
	_check(not Net.party.get("portal", {}).is_empty(), "the party's rift waits (nobody's in it; a portal leads in)")
	await _until(func(): return String(Net.member_where.get(fol, "")).begins_with("rift:"), 25.0)
	await _wait(4.0)  # the follower carries the rift on first
	var spot := Vector2(float(mine.x), float(mine.y))
	await _go_through(_node_of(mine.id))
	if not await _until(func(): return _rift() != null and not Net.others.is_empty(), 20.0):
		_check(false, "back through its own portal into the rift")
		return
	m = _rift()
	await _wait(1.0)
	_check(m.player.global_position.distance_to(spot) < 120.0, "back through its own portal: by where it stood (%.0f away)" % m.player.global_position.distance_to(spot))
	_check(GameState.town_portal.is_empty() and _node_of(mine.id) == null, "and it closed behind it")
	_check(not Net.is_instance_host(), "the follower hosts the rift now")
	if not await _until(func(): return not _their_tp().is_empty(), 20.0):
		_check(false, "the follower reads a scroll")
		return
	var theirs := _their_tp()
	await _until(func(): return _rift() != null and _node_of(theirs.id) != null, 5.0)
	var n := _node_of(theirs.id)
	_check(n != null and "Fol's Town Portal" in n._plate.text, "the leader sees the follower's portal (%s)" % (n._plate.text if n else "none"))
	var closed := await _until(func(): return _their_tp().is_empty() and _rift() != null and _rift().mazes_visited >= 2 and _node_of(theirs.id) == null, 20.0)
	_check(closed, "it closes when the rift moves on to its next maze")


func _follower() -> void:
	if not await _until(func(): return _rift() != null and not Net.others.is_empty(), 30.0):
		_check(false, "both in the party's rift")
		return
	var m = _rift()
	var map: String = m.maze.map_id
	await _wait(1.0)
	var monsters := _alive_monsters()
	if not await _until(func(): return not _their_tp().is_empty(), 15.0):
		_check(false, "the leader reads a scroll")
		return
	var theirs := _their_tp()
	await _until(func(): return _node_of(theirs.id) != null, 5.0)
	var n := _node_of(theirs.id)
	_check(n != null and "Lead's Town Portal" in n._plate.text, "the follower sees the leader's portal in the rift (%s)" % (n._plate.text if n else "none"))
	if n == null:
		return
	await _go_through(n)
	await _until(_in_town, 10.0)
	await _wait(0.5)
	n = _node_of(theirs.id)
	_check(n != null and "Lead's Portal: Rift 1" in n._plate.text, "through it to town: the leader's portal back stands there (%s)" % (n._plate.text if n else "none"))
	var replaced := await _until(func(): return int(_their_tp().get("id", 0)) not in [0, int(theirs.id)], 20.0)
	await _wait(0.5)
	var ps := get_tree().get_nodes_in_group("town_portals").filter(func(x): return not x.is_queued_for_deletion())
	_check(replaced and ps.size() == 1 and int(ps[0].tp_id) == int(_their_tp().get("id", -1)),
		"the leader read another: in town too the old one's gone, the new one stands (%s %d: %s, party has %s)" % [replaced, ps.size(), ps.map(func(x): return x.tp_id), _their_tp().get("id", 0)])
	theirs = _their_tp()
	var lead := _other()
	await _until(func(): return String(Net.member_where.get(lead, "")).begins_with(Net.TOWN), 25.0)
	await _wait(1.5)
	n = _node_of(theirs.id)
	_check(n != null, "with the leader in town too, its portal still leads back")
	if n == null:
		return
	await _go_through(n)
	if not await _until(func(): return _rift() != null, 20.0):
		_check(false, "back into the rift through the leader's portal")
		return
	m = _rift()
	await _wait(1.0)
	_check(Net.is_instance_host(), "nobody was in it: the follower hosts it now")
	_check(m.maze.map_id == map, "the rift carried on: the same maze (%s)" % m.maze.map_id)
	_check(absi(_alive_monsters() - monsters) <= 1 and monsters > 0, "and its monsters (%d, were %d)" % [_alive_monsters(), monsters])
	_check(m.player.global_position.distance_to(Vector2(float(theirs.x), float(theirs.y))) < 120.0, "standing by the leader's portal")
	_check(_node_of(theirs.id) != null, "which is still open (it's the leader's)")
	await _until(func(): return not Net.others.is_empty(), 20.0)
	await _until(func(): return _their_tp().is_empty(), 10.0)
	_check(_their_tp().is_empty() and _node_of(theirs.id) == null, "the leader came back through its portal: it closed")
	await _wait(1.0)
	_check(TownPortals.read_scroll(m), "the follower reads a scroll")
	await _wait(3.0)  # the leader sees it
	m._travel()
	await _wait(2.0)
	_check(GameState.town_portal.is_empty(), "moving on to the next maze closes it")
	await _wait(3.0)  # the leader sees that too
