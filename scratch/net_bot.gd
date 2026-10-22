extends Node
## A pretend player for testing multiplayer (Net) without a second device. Run alongside a server:
##   godot --headless --path . res://scratch/net_bot.tscn -- --bot=walker --name=Brom [--addr=127.0.0.1] [--secs=20]
## walker:  joins, enters town and walks in a circle by the spawn, in some gear, then leaves.
## watcher: joins, enters town, and checks what it sees (prints "watcher: N checks, M failed").
## scan:    looks for servers on the Wi-Fi and prints them.

var mode := "walker"
var addr := "127.0.0.1"
var bot_name := "Bot"
var secs := 20.0
var _t := 0.0
var _checks := 0
var _failed := 0
var _seen := {}  # id -> {"info", "states"}
var _left := []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bot="): mode = a.get_slice("=", 1)
		elif a.begins_with("--addr="): addr = a.get_slice("=", 1)
		elif a.begins_with("--name="): bot_name = a.get_slice("=", 1)
		elif a.begins_with("--secs="): secs = float(a.get_slice("=", 1))
	GameState.char_name = bot_name
	GameState.level = 7
	GameState.appearance = Appearance.random_look()
	if mode == "scan":
		Net.servers_found.connect(func(list): print("scan: ", list))
		Net.scan()
		await get_tree().create_timer(2.0).timeout
		get_tree().quit()
		return
	Net.state_source = _state
	Net.status_changed.connect(func(): print("%s: %s" % [bot_name, Net.status]))
	Net.peer_joined.connect(func(id, info, state):
		print("%s: sees %s (Lv %d) at %s" % [bot_name, info.name, info.level, state.get("p")])
		_seen[id] = {"info": info, "states": 0})
	Net.peer_state.connect(func(id, _s):
		if _seen.has(id):
			_seen[id].states += 1)
	Net.peer_left.connect(func(id): _left.append(id))
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


## Walks in a circle by the town's spawn point.
func _state() -> Dictionary:
	var p := Vector2(0, 360) + Vector2(140, 0).rotated(_t * 0.8) + Vector2(-60, -40)
	return {"p": p, "f": -sin(_t * 0.8), "a": "Walking", "s": 1.0}


## Pretends to wear a sword, a helmet and armour (as Net.my_info would send them).
func _send_gear() -> void:
	var info := Net.my_info()
	info.gear = {"weapon": ["broad_sword", ""], "helmet": ["iron_helm", "crimson"], "chest": ["brigandine", ""]}
	Net._rpc_looks.rpc_id(1, info)


func _process(delta: float) -> void:
	_t += delta
	if _t < secs:
		return
	set_process(false)
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
