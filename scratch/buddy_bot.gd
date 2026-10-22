extends Node
## Plays with TestBot (scripts/bots/test_bot.gd) as a person would, to check it: on a local server
## started with --data and --bot-key, TestBot running with that key:
##   godot --headless --path . res://scratch/buddy_bot.tscn
## Whispers it help and invite, trades with it, opens a party rift and checks it comes in and fights,
## has it die and revives it. Prints "buddy: N checks, M failed". (A copy runs at the root.)

var runner := false
var _checks := 0
var _failed := 0
var _whispers: Array = []
var _invited := 0
var _trade := {}
var _got := []
var _got_orbs := {}
var _kills := 0


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	Net.test_key = "buddy-bot".rpad(40, "0")
	Net.status_changed.connect(func(): print("buddy: status: ", Net.status))
	Net.role_changed.connect(func(h): print("buddy: instance host ", h, " (me ", Net.my_id(), ") in ", Net.instance))
	Net.chat.connect(func(_f, n, ch, text):
		if ch == "whisper" and n == "TestBot":
			_whispers.append(text))
	Net.invited.connect(func(from, _n): _invited = from)
	Net.trade_asked.connect(func(from, _n): Net.answer_trade(from, true))
	Net.trade_changed.connect(func(s): _trade = s)
	Net.trade_finished.connect(func(items, orbs):
		_got = items
		_got_orbs = orbs)
	get_tree().node_added.connect(func(n):
		if n is Enemy and not n.remote:
			n.died.connect(func(_p): _kills += 1))
	Net.join("127.0.0.1")
	var t := 0.0
	while not GameState.online_saves and t < 10.0:
		await _wait(0.2)
		t += 0.2
	GameState.select_character(GameState.create_character("Buddy", "warrior"))
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.give_starter_skills()
	GameState.save()
	get_tree().change_scene_to_file("res://scenes/town.tscn")
	var bot := 0
	t = 0.0
	while bot == 0 and t < 30.0:
		await _wait(0.5)
		t += 0.5
		for id in Net.others:
			if String(Net.others[id].get("name", "")) == "TestBot":
				bot = int(id)
	_check(bot != 0, "TestBot is in town")
	Net.whisper(bot, "help")
	await _wait(1.5)
	_check(_whispers.any(func(w): return "test bot" in w), "it answers a whisper (%s)" % (_whispers[0] if not _whispers.is_empty() else "nothing"))
	Net.whisper(bot, "invite")
	await _wait(1.5)
	_check(_invited == bot, "whisper 'invite': it invites you")
	Net.answer_invite(_invited, true)
	await _wait(1.5)
	_check(Net.is_member(bot), "in a party with it")
	Net.whisper(bot, "trade")
	await _wait(2.0)
	_check(not _trade.is_empty() and not _trade.get("theirs", []).is_empty() and int(_trade.get("theirs_orbs", {}).get("transmute", 0)) == 5,
		"whisper 'trade': a trade with an item and orbs on offer")
	Net.trade_ready(true)
	await _wait(2.0)
	_check(_got.size() == 1 and int(_got_orbs.get("transmute", 0)) == 5, "ready: it's ready too, and the trade goes through")
	Net.open_party_rift(1)  # in we go; it follows
	t = 0.0
	var in_rift := false
	while t < 25.0 and not in_rift:
		await _wait(0.5)
		t += 0.5
		var scene := get_tree().current_scene
		in_rift = scene != null and scene.scene_file_path.ends_with("main.tscn") and \
			get_tree().get_nodes_in_group("remote_players").any(func(r): return r.peer_id == bot)
	var sc := get_tree().current_scene
	_check(in_rift, "it follows you into the party's rift (I'm in %s, instance %s, %d others)" % [
		sc.scene_file_path.get_file() if sc != null else "?", Net.instance, get_tree().get_nodes_in_group("remote_players").size()])
	var p: Player = GameState.player
	var k0 := _kills
	t = 0.0
	var pack_t := 0.0
	while t < 30.0 and _kills - k0 < 5:
		await _wait(0.5)
		t += 0.5
		pack_t -= 0.5
		if is_instance_valid(p):
			p.hp = p.stats.get_stat("max_life")
			if pack_t <= 0.0:  # you go towards the monsters (never hitting them): it comes along and fights
				pack_t = 4.0
				var foes := get_tree().get_nodes_in_group("enemies").filter(func(e): return not e._dead and not e.remote)
				foes.sort_custom(func(a, b): return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
				if not foes.is_empty():
					p.global_position = foes[0].global_position + Vector2(220, 0)
	_check(_kills - k0 >= 5, "it fights: monsters die without you lifting a finger (%d)" % (_kills - k0))
	Net.whisper(bot, "die")
	await _wait(1.5)
	var rp = get_tree().get_nodes_in_group("remote_players").filter(func(r): return r.peer_id == bot)
	_check(not rp.is_empty() and rp[0].dead, "whisper 'die': it falls")
	t = 0.0
	while t < 10.0 and not rp.is_empty() and rp[0].dead:
		await _wait(0.2)
		t += 0.2
		p.hp = p.stats.get_stat("max_life")
		p.global_position = rp[0]._target + Vector2(30, 0)  # stand by it
	_check(not rp.is_empty() and not rp[0].dead, "standing by it revives it (%.1f s)" % t)
	print("buddy: %d checks, %d failed" % [_checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
