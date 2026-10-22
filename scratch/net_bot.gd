extends Node
## A pretend player for testing multiplayer (Net) without a second device. Run alongside a server:
##   godot --headless --path . res://scratch/net_bot.tscn -- --bot=walker --name=Brom [--addr=127.0.0.1] [--secs=20]
## walker:  joins, enters town and walks in a circle by the spawn, in some gear, then leaves.
## watcher: joins, enters town, and checks what it sees (prints "watcher: N checks, M failed").
## partier: joins, invites everyone it sees, and checks the party forms, members' life arrives, a
##          member can be made leader, and leaving works (prints "partier: N checks, M failed").
## --accept: a walker or watcher that joins any party it is invited to.
## --invite: a walker that invites everyone it sees, two seconds in.
## --drop-at=8: loses its connection 8 s in (Net.simulate_drop) and checks it comes back: online, in
##   town, in its party ("dropper: N checks, M failed").
## keeper: a partier that keeps its party, and checks a member who drops is shown away and comes back.
## counter: in town for a while, prints how many others it sees (for the town copies test).
## --say=text: says it in town chat 3 s in (--party-say=text: in party chat).
## --expect-chat=a|b: checks lines containing each of those came (prints "chat: N checks, M failed");
## --no-chat=c: checks no line containing it came.
## --key=abc: its own account on a server that keeps characters (Net.test_key).
## --befriend: asks the first player it sees to be friends; --accept-friend accepts any friend request.
## --expect-friend=Name: checks Name is in its friends list (and, with --friend-online=yes/no, online or
##   not) at the end ("friends: N checks, M failed").
## inspector: inspects the first player it sees and checks their gear and stats came
##   ("inspector: N checks, M failed").

var mode := "walker"
var addr := "127.0.0.1"
var bot_name := "Bot"
var secs := 20.0
var _t := 0.0
var _checks := 0
var _failed := 0
var _seen := {}  # id -> {"info", "states"}
var _left := []
var accept := false
var invite_all := false
var drop_at := 0.0
var _dropped := false
var _away_seen := false
var _back_seen := false
var _say := ""
var _party_say := ""
var _expect: Array = []
var _no_chat := ""
var _befriend := false
var _accept_friend := false
var _expect_friend := ""
var _friend_online := ""
var _heard: Array = []
var _vitals := {}  # id -> last life seen
var _notices: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bot="): mode = a.get_slice("=", 1)
		elif a.begins_with("--addr="): addr = a.get_slice("=", 1)
		elif a.begins_with("--name="): bot_name = a.get_slice("=", 1)
		elif a.begins_with("--secs="): secs = float(a.get_slice("=", 1))
		elif a == "--accept": accept = true
		elif a == "--invite": invite_all = true
		elif a.begins_with("--drop-at="): drop_at = float(a.get_slice("=", 1))
		elif a.begins_with("--say="): _say = a.get_slice("=", 1)
		elif a.begins_with("--party-say="): _party_say = a.get_slice("=", 1)
		elif a.begins_with("--expect-chat="): _expect = Array(a.get_slice("=", 1).split("|"))
		elif a.begins_with("--no-chat="): _no_chat = a.get_slice("=", 1)
		elif a.begins_with("--key="): Net.test_key = a.get_slice("=", 1).rpad(40, "0")
		elif a == "--befriend": _befriend = true
		elif a == "--accept-friend": _accept_friend = true
		elif a.begins_with("--expect-friend="): _expect_friend = a.get_slice("=", 1)
		elif a.begins_with("--friend-online="): _friend_online = a.get_slice("=", 1)
	GameState.char_name = bot_name
	GameState.level = 7
	GameState.appearance = Appearance.random_look()
	Net.state_source = _state
	Net.status_changed.connect(func(): print("%s: %s" % [bot_name, Net.status]))
	Net.peer_joined.connect(func(id, info, state):
		print("%s: sees %s (Lv %d) at %s" % [bot_name, info.name, info.level, state.get("p")])
		_seen[id] = {"info": info, "states": 0})
	Net.peer_state.connect(func(id, _s):
		if _seen.has(id):
			_seen[id].states += 1)
	Net.peer_left.connect(func(id): _left.append(id))
	Net.notice.connect(func(t):
		_notices.append(t)
		print("%s: notice: %s" % [bot_name, t]))
	Net.invited.connect(func(from_id, from_name):
		print("%s: invited by %s" % [bot_name, from_name])
		if accept:
			Net.answer_invite(from_id, true))
	Net.party_changed.connect(func():
		print("%s: party now %s" % [bot_name, Net.party.get("members", []).map(func(m): return m.name)]))
	Net.friend_asked.connect(func(from_id, from_name):
		print("%s: %s wants to be friends" % [bot_name, from_name])
		if _accept_friend:
			Net.answer_friend(from_id, true))
	Net.friends_changed.connect(func():
		print("%s: friends %s" % [bot_name, Net.friends.map(func(f): return "%s(%s)" % [f.name, "on" if f.online else "off"])]))
	Net.chat.connect(func(_id, from_name, channel, text):
		_heard.append("%s/%s: %s" % [channel, from_name, text])
		print("%s: heard %s/%s: %s" % [bot_name, channel, from_name, text]))
	Net.party_vitals.connect(func(batch):
		for id in batch:
			_vitals[id] = batch[id].h)
	Net.join(addr)
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	if not Net.online():
		print("%s: FAIL could not connect" % bot_name)
		get_tree().quit(1)
		return
	Net.enter(Net.TOWN)
	if mode == "walker":
		_send_gear()
	if invite_all:
		await get_tree().create_timer(2.0).timeout
		for id in Net.others:
			Net.invite(id)
	if mode == "partier":
		_run_partier()
	if mode == "keeper":
		_run_keeper()
	if mode == "inspector":
		_run_inspector()
	if drop_at > 0.0:
		_run_dropper()
	if _befriend:
		await get_tree().create_timer(3.0).timeout
		if not Net.others.is_empty():
			Net.add_friend(Net.others.keys()[0])
	if _say != "" or _party_say != "":
		await get_tree().create_timer(3.0).timeout
		if _say != "":
			Net.say("local", _say)
		if _party_say != "":
			await get_tree().create_timer(1.0).timeout
			Net.say("party", _party_say)


## Drops its connection, then checks it got back where it was.
func _run_dropper() -> void:
	await get_tree().create_timer(drop_at).timeout
	var had_party := Net.in_party()
	print("%s: dropping (in a party: %s)" % [bot_name, had_party])
	Net.simulate_drop()
	_check(Net.mode == Net.Mode.RECONNECTING, "it starts reconnecting")
	var t := 0.0
	while not Net.online() and t < 20.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	await get_tree().create_timer(1.5).timeout
	_check(Net.online(), "it reconnects (%.1f s)" % t)
	_check(Net.instance == Net.TOWN, "it goes back into town")
	_check(Net.in_party() == had_party, "it is back in its party")
	print("dropper: %d checks, %d failed" % [_checks, _failed])


## Inspects whoever it sees first and checks what comes back.
func _run_inspector() -> void:
	var got := {}
	Net.inspected.connect(func(_id, data): got.merge(data))
	await get_tree().create_timer(5.0).timeout
	if not Net.others.is_empty():
		Net.inspect(Net.others.keys()[0])
	await get_tree().create_timer(2.0).timeout
	_check(not got.is_empty(), "the inspected player's data came")
	var eq = got.get("equipment", {})
	_check(eq is Dictionary and eq.size() >= 2, "with their worn gear (%d pieces)" % (eq.size() if eq is Dictionary else 0))
	_check(eq is Dictionary and eq.values().all(func(d): return ItemInstance.from_dict(d) != null), "which make real items here")
	_check(float(got.get("stats", {}).get("max_life", 0.0)) > 0.0, "and their stats")
	print("inspector: %d checks, %d failed" % [_checks, _failed])


## Keeps a party with whoever it invites; checks a member who drops is away, then back.
func _run_keeper() -> void:
	await get_tree().create_timer(2.0).timeout
	for id in Net.others:
		Net.invite(id)
	Net.party_changed.connect(func():
		if not Net.party.get("away", []).is_empty():
			_away_seen = true
		elif _away_seen and Net.party.get("members", []).size() >= 2:
			_back_seen = true)


## Invites everyone in town, then checks the party: forming, life, leadership, leaving.
func _run_partier() -> void:
	await get_tree().create_timer(2.0).timeout
	for id in Net.others:
		Net.invite(id)
	await get_tree().create_timer(3.0).timeout
	var n: int = Net.party.get("members", []).size()
	_check(n >= 2, "the party forms (%d members)" % n)
	_check(Net.is_leader(), "the inviter leads it")
	await get_tree().create_timer(2.0).timeout
	var others_life := _vitals.keys().filter(func(id): return id != Net.my_id())
	_check(not others_life.is_empty() and others_life.all(func(id): return absf(_vitals[id] - 0.75) < 0.01),
		"members' life arrives (%s)" % [_vitals])
	if n >= 2:
		var other := int(Net.party.members.filter(func(m): return int(m.id) != Net.my_id())[0].id)
		Net.promote(other)
		await get_tree().create_timer(1.5).timeout
		_check(int(Net.party.get("leader", 0)) == other and not Net.is_leader(), "the lead can be handed over")
		Net.invite(other)  # not the leader any more: refused
		await get_tree().create_timer(1.0).timeout
		_check(_notices.any(func(t): return "Only the party leader" in t), "a member can't invite")
	Net.leave_party()
	await get_tree().create_timer(1.5).timeout
	_check(not Net.in_party(), "leaving the party works")
	print("partier: %d checks, %d failed" % [_checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


## Walks in a circle by the town's spawn point.
func _state() -> Dictionary:
	var p := Vector2(0, 360) + Vector2(140, 0).rotated(_t * 0.8) + Vector2(-60, -40)
	return {"p": p, "f": -sin(_t * 0.8), "a": "Walking", "s": 1.0, "h": 0.75, "w": ActDB.TOWN_NAME}


## Pretends to wear a sword, a helmet and armour (as Net.my_info would send them).
func _send_gear() -> void:
	var info := Net.my_info()
	info.gear = {"weapon": ["broad_sword", ""], "helmet": ["iron_helm", "crimson"], "chest": ["brigandine", ""]}
	Net._rpc_looks.rpc_id(1, info)


func _process(delta: float) -> void:
	_t += delta
	if _t < secs or mode == "partier" or (drop_at > 0.0 and _t < drop_at + 25.0):
		return
	set_process(false)
	if _expect_friend != "":
		var f: Array = Net.friends.filter(func(x): return x.name == _expect_friend)
		_check(not f.is_empty(), "%s is a friend" % _expect_friend)
		if _friend_online != "" and not f.is_empty():
			_check(bool(f[0].online) == (_friend_online == "yes"), "%s shows %s" % [_expect_friend, "online" if _friend_online == "yes" else "offline"])
		print("friends: %d checks, %d failed" % [_checks, _failed])
	if not _expect.is_empty() or _no_chat != "":
		for e in _expect:
			_check(_heard.any(func(h): return e in h), "heard a line with \"%s\"" % e)
		if _no_chat != "":
			_check(not _heard.any(func(h): return _no_chat in h), "never heard \"%s\"" % _no_chat)
		print("chat: %d checks, %d failed" % [_checks, _failed])
	if mode == "counter":
		print("counter: sees %d others" % Net.others.size())
	if mode == "keeper":
		_check(_away_seen, "the member who dropped is shown away")
		_check(_back_seen, "and back in the party when they return")
		_check(Net.others.size() >= 1, "and back in town with it")
		print("keeper: %d checks, %d failed" % [_checks, _failed])
	if mode == "watcher":
		_check(_seen.size() >= 1, "sees at least one other player")
		for id in _seen:
			var s: Dictionary = _seen[id]
			_check(s.states > 10, "%s's movement arrives (%d updates)" % [s.info.name, s.states])
		# The walker bots wear a sword (players may wear nothing)
		_check(_seen.keys().any(func(id): return Net.others.get(id, {}).get("gear", {}).has("weapon")), "a walker's gear arrives")
		print("watcher: %d checks, %d failed" % [_checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
