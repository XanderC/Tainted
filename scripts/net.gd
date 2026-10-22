extends Node
## Multiplayer (autoload "Net"). A server holds everyone who is online; each player is in one
## instance at a time ("town" is shared by everyone online), and sees the others in the same
## instance: who they are, how they look, where they stand and what they are doing.
##
## Three ways to run it:
##   dedicated server  godot --headless --path . -- --server [--name=Home] [--max=32]  (scenes/server.tscn;
##                     the Tainted World runs one in Docker, see server/)
##   host              "Host a game" on the online screen: this game is the server and plays too
##   client            "Play Online": join the Tainted World, a game found on your Wi-Fi, or an address
##
## It talks over WebSockets (ws:// on the LAN, wss:// through a TLS proxy such as Traefik behind a
## Cloudflare Tunnel), so a public server needs no forwarded port. The Tainted World's addresses are
## project settings (tainted/net/world_addresses), tried in order: the home network's first.
##
## Each game runs its own copy of the scene (town NPCs, vendors and your character are local); the
## server only passes on who is where. Characters stay in each player's own save. Games hosted on the
## Wi-Fi answer a broadcast on DISCOVERY_PORT, so the online screen lists them by themselves.
##
## The server takes nothing on trust: a client must say hello within HELLO_TIMEOUT, its states are
## rate-limited and cleaned (_clean_state), its looks cleaned (_clean_info), and only plain values
## cross the wire (object decoding stays off).
##
## Parties (up to PARTY_MAX): a player in a party, or on their own, invites another who is on their
## own; the inviter leads a new party. The leader can remove members or hand over the lead; anyone can
## leave. Members see each other's life and whereabouts wherever they are (party_vitals), and
## (stage 3) play zones and rifts together.
##
## The server's records live in _peers (id -> {"info", "instance", "state", "party"}) and _parties;
## the host is peer 1.
## RPC entry points (_rpc_*) take the sender from the MultiplayerAPI and call the _on_* handlers,
## which the host also calls directly for its own player.

signal status_changed  ## connected, disconnected, hosting... (read `mode` and `status`)
signal peer_joined(id: int, info: Dictionary, state: Dictionary)  ## someone is now in your instance
signal peer_left(id: int)  ## ...or isn't any more
signal peer_state(id: int, state: Dictionary)  ## where they are now (about SEND_HZ times a second)
signal peer_looks(id: int, info: Dictionary)  ## their gear, level or name changed
signal servers_found(list: Array)  ## servers answering on the Wi-Fi: [{"name", "address", "players", "max"}]
signal party_changed  ## you joined, left or were removed, or the party's members or leader changed (`party`)
signal invited(from_id: int, from_name: String)  ## someone invites you to their party (answer_invite)
signal party_vitals(batch: Dictionary)  ## members' life and whereabouts: id -> {"h": 0-1, "w": place}
signal notice(text: String)  ## a line for the player: "Brom joined the party", "Kael is already in a party"...

const PORT := 24601
const DISCOVERY_PORT := 24602
const PROTOCOL := 2  ## games with a different protocol can't play together
const MAX_ONLINE := 32
const PARTY_MAX := 4
const SEND_HZ := 15.0
const DISCOVER_MSG := "TAINTED_DISCOVER"
const TOWN := "town"
const INVITE_TIMEOUT := 60.0  ## seconds an invite can be answered
const VITALS_HZ := 2.0  ## party members' life and whereabouts, this often
const HELLO_TIMEOUT := 10.0  ## seconds a new connection has to say hello before it is dropped
const KEEPALIVE := 20.0  ## a client says something at least this often (proxies drop idle WebSockets)
const MAX_MSGS_PER_SEC := 40  ## per client; more are dropped
## The Tainted World, unless project settings say otherwise.
const WORLD_NAME_DEFAULT := "Tainted World"
const WORLD_ADDRESSES_DEFAULT := ["ws://192.168.86.18:24601"]

enum Mode { OFFLINE, CONNECTING, CLIENT, HOST, SERVER }

var mode := Mode.OFFLINE
var status := ""  ## a line for the player: "Connected to Home", "Connection failed"...
var server_name := ""
var instance := ""  ## the instance this game's player is in ("" while in none)
var others := {}  ## the other players in your instance: id -> info
## Your party: {"id", "leader", "members": [{"id", "name", "level", "class"}]}, or {} when on your own.
var party := {}
var party_ui: PartyUI  ## the party list, invites and player cards on screen (not on a dedicated server)
## What this game sends as its player's state; by default the local Player's (bots replace it).
var state_source: Callable = _player_state

var _peers := {}  # server only: id -> {"info": Dictionary, "instance": String, "state": Dictionary}
var _send_t := 0.0
var _relay_t := 0.0
var _dirty := {}  # server only: ids whose state changed since the last relay
var _looks_queued := false
var _disc_server: PacketPeerUDP  # server: answers discovery broadcasts
var _disc_client: PacketPeerUDP  # client: scanning for servers
var _found := {}  # address -> server info, while scanning
var _max_online := MAX_ONLINE
var _world_queue: Array = []  # Tainted World addresses still to try
var _keep_t := 0.0
var _pending := {}  # server only: id -> msec it connected, until it says hello
var _rate := {}  # server only: id -> [second, messages that second]
var _parties := {}  # server only: party id -> {"leader": id, "members": [ids]}
var _next_party := 1
var _invites := {}  # server only: invited id -> {inviter id: msec}
var _vitals_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep talking while a menu pauses the game
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)
	if dedicated_requested():
		var name_arg := "Tainted server"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--name="):
				name_arg = a.get_slice("=", 1)
			elif a.begins_with("--max="):
				_max_online = clampi(int(a.get_slice("=", 1)), 1, 1000)
		start_server(name_arg, true)
		get_tree().change_scene_to_file.call_deferred("res://scenes/server.tscn")
	else:
		party_ui = PartyUI.new()
		add_child(party_ui)


## Started as a dedicated server (`-- --server` on the command line).
static func dedicated_requested() -> bool:
	return "--server" in OS.get_cmdline_user_args()


## This game's peer id (1 when hosting), or 0 offline.
func my_id() -> int:
	return multiplayer.get_unique_id() if online() else 0


func in_party() -> bool:
	return not party.is_empty()


func is_leader() -> bool:
	return in_party() and int(party.leader) == my_id()


## Whether `id` is in your party.
func is_member(id: int) -> bool:
	return in_party() and party.members.any(func(m): return int(m.id) == id)


func online() -> bool:
	return mode in [Mode.CLIENT, Mode.HOST]


func is_server() -> bool:
	return mode in [Mode.HOST, Mode.SERVER]


## The Tainted World's name and addresses (project settings tainted/net/world_*), tried in order.
static func world_name() -> String:
	return String(ProjectSettings.get_setting("tainted/net/world_name", WORLD_NAME_DEFAULT))


static func world_addresses() -> Array:
	return Array(ProjectSettings.get_setting("tainted/net/world_addresses", WORLD_ADDRESSES_DEFAULT))


## A WebSocket URL for `address`: used as it is if it has a scheme, else ws://address:PORT.
static func url_of(address: String) -> String:
	address = address.strip_edges()
	return address if "://" in address else "ws://%s:%d" % [address, PORT]


## How many players are online (the server knows; a client knows only its instance).
func player_count() -> int:
	return _peers.size() if is_server() else others.size() + (1 if online() else 0)


# ---------- starting and stopping ----------

## Be the server. `dedicated`: nobody plays on this game (a headless server).
func start_server(name: String, dedicated := false) -> bool:
	leave()
	var peer := _ws_peer()
	var err := peer.create_server(PORT)
	if err != OK:
		_set_status(Mode.OFFLINE, "Couldn't start a server on port %d (is one already running?)" % PORT)
		return false
	multiplayer.multiplayer_peer = peer
	server_name = name
	_disc_server = PacketPeerUDP.new()
	if _disc_server.bind(DISCOVERY_PORT) != OK:
		push_warning("Net: discovery port %d is busy; the server won't show up in the list" % DISCOVERY_PORT)
		_disc_server = null
	if dedicated:
		_set_status(Mode.SERVER, "Server \"%s\" running on port %d (up to %d players)" % [name, PORT, _max_online])
		print(status)
	else:
		_peers[1] = {"info": my_info(), "instance": "", "state": {}, "party": 0}
		_set_status(Mode.HOST, "Hosting \"%s\"" % name)
	return true


## Host a game: this game is the server, and its player plays in it.
func host() -> bool:
	return start_server("%s's game" % (GameState.char_name if GameState.char_name != "" else "Someone"))


## Join the server at `address`: an IP on your Wi-Fi, or a ws:// / wss:// URL. status_changed tells
## how it went.
func join(address: String) -> void:
	_world_queue.clear()
	_connect(address)


## Join the Tainted World: its addresses in turn until one answers.
func join_world() -> void:
	_world_queue = world_addresses().duplicate()
	_try_next_world()


func _try_next_world() -> void:
	if _world_queue.is_empty():
		_set_status(Mode.OFFLINE, "Couldn't reach the %s. Is it running?" % world_name())
		return
	_connect(String(_world_queue.pop_front()))
	server_name = world_name()
	_set_status(Mode.CONNECTING, "Connecting to the %s..." % world_name())


func _connect(address: String) -> void:
	var keep_queue := _world_queue.duplicate()
	leave()
	_world_queue = keep_queue
	var peer := _ws_peer()
	if peer.create_client(url_of(address)) != OK:
		_on_connection_failed()
		return
	multiplayer.multiplayer_peer = peer
	server_name = address
	_set_status(Mode.CONNECTING, "Connecting to %s..." % address)


## A WebSocket peer sized for the game's messages (a town's states fit easily; anything far bigger is refused).
func _ws_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 256 * 1024
	peer.outbound_buffer_size = 256 * 1024
	peer.max_queued_packets = 1024
	peer.handshake_timeout = 5.0
	return peer


## Go offline (stop hosting, or leave the server).
func leave() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _disc_server != null:
		_disc_server.close()
		_disc_server = null
	for id in others.keys():
		peer_left.emit(id)
	others.clear()
	_peers.clear()
	_dirty.clear()
	_pending.clear()
	_rate.clear()
	_world_queue.clear()
	_parties.clear()
	_invites.clear()
	instance = ""
	if not party.is_empty():
		party = {}
		party_changed.emit()
	if mode != Mode.OFFLINE:
		_set_status(Mode.OFFLINE, "Offline")


func _set_status(m: Mode, text: String) -> void:
	mode = m
	status = text
	status_changed.emit()


func _on_connected() -> void:
	_rpc_hello.rpc_id(1, PROTOCOL, my_info())


func _on_connection_failed() -> void:
	if not _world_queue.is_empty():
		_try_next_world()  # the next of the Tainted World's addresses
		return
	var what := server_name
	leave()
	_set_status(Mode.OFFLINE, "Couldn't connect to %s" % what)


func _on_server_lost() -> void:
	leave()
	_set_status(Mode.OFFLINE, "Lost the connection to the server")


# ---------- who you are, and where you stand ----------

## What others see of this game's player: name, class, level, looks and visible gear.
func my_info() -> Dictionary:
	var gear := {}
	var p = GameState.player
	if is_instance_valid(p):
		for slot in Player.VISIBLE_SLOTS:
			var it: ItemInstance = p.equipment.get(slot)
			if it != null:
				gear[slot] = [it.base.id, it.dye if slot in DyeDB.SLOTS else ""]
		var off: ItemInstance = p.equipment.get("offhand")
		if off != null:
			gear["offhand"] = [off.base.id, off.base.weapon_type == "shield"]
	return {"name": GameState.char_name, "class": GameState.char_class, "level": GameState.level,
		"look": GameState.appearance, "gear": gear}


## The local player's state: position, facing, and the animation it is playing.
func _player_state() -> Dictionary:
	var p = GameState.player
	if not is_instance_valid(p) or p.rig == null:
		return {}
	var anim: String = p.rig.oneshot_name() if p.rig.is_busy() else p.rig._loop_anim
	return {"p": p.global_position, "f": p.facing.x, "a": anim, "s": p.rig._speed,
		"h": 0.0 if p.dead else p.hp / maxf(p.stats.get_stat("max_life"), 1.0), "w": where_label()}


## Where this game's player is, for the party list: the town, a zone or a rift.
func where_label() -> String:
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene != null else ""
	if path.ends_with("town.tscn"):
		return ActDB.TOWN_NAME
	if path.ends_with("zone.tscn"):
		return ActDB.zone_name(GameState.current_zone)
	if path.ends_with("main.tscn"):
		return "Rift %d" % GameState.rift_level
	if path.ends_with("tutorial.tscn"):
		return "The shipwreck"
	return ""


## Enter `inst` (TOWN, ...; "" to be in none). Others there see you, and you them (peer_joined).
func enter(inst: String) -> void:
	if not online() or inst == instance:
		return
	for id in others.keys():
		peer_left.emit(id)
	others.clear()
	instance = inst
	var s: Dictionary = state_source.call() if state_source.is_valid() else {}
	if mode == Mode.HOST:
		_on_enter(1, inst, s)
	else:
		_rpc_enter.rpc_id(1, inst, s)


## Your gear, level or name changed: others see it (sent once at the end of the frame).
func update_looks() -> void:
	if not online() or _looks_queued:
		return
	_looks_queued = true
	(func():
		_looks_queued = false
		if not online():
			return
		if mode == Mode.HOST:
			_on_looks(1, my_info())
		else:
			_rpc_looks.rpc_id(1, my_info())
	).call_deferred()


func _process(delta: float) -> void:
	_poll_discovery()
	if mode == Mode.CLIENT:
		_keep_t -= delta
		if _keep_t <= 0.0:
			_keep_t = KEEPALIVE
			_rpc_ping.rpc_id(1)  # so a proxy never sees the connection idle
	if is_server():
		_drop_silent()
	if online():  # outside an instance too: the party sees your life and whereabouts
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / SEND_HZ
			var s: Dictionary = state_source.call() if state_source.is_valid() else {}
			if not s.is_empty():
				if mode == Mode.HOST:
					_on_state(1, s)
				else:
					_rpc_state.rpc_id(1, s)
	if is_server():
		_relay_t -= delta
		if _relay_t <= 0.0:
			_relay_t = 1.0 / SEND_HZ
			_relay_states()
		_vitals_t -= delta
		if _vitals_t <= 0.0:
			_vitals_t = 1.0 / VITALS_HZ
			_relay_vitals()


# ---------- server: who is where ----------

func _on_peer_connected(id: int) -> void:
	if is_server():
		_pending[id] = Time.get_ticks_msec()  # recorded once it says hello


## Drops connections that never said hello.
func _drop_silent() -> void:
	var now := Time.get_ticks_msec()
	for id in _pending.keys():
		if now - int(_pending[id]) > HELLO_TIMEOUT * 1000.0:
			_pending.erase(id)
			_kick(id)


func _kick(id: int) -> void:
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and id != 1:
		multiplayer.multiplayer_peer.disconnect_peer(id)


## False once `id` has sent more than MAX_MSGS_PER_SEC this second (that message is ignored).
func _within_rate(id: int) -> bool:
	var sec := Time.get_ticks_msec() / 1000
	var r: Array = _rate.get(id, [sec, 0])
	if r[0] != sec:
		r = [sec, 0]
	r[1] += 1
	_rate[id] = r
	return r[1] <= MAX_MSGS_PER_SEC


func _on_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	if not is_server() or not _peers.has(id):
		return
	var inst: String = _peers[id].instance
	_remove_from_party(id, "%s left the game" % _peers[id].info.name)
	_invites.erase(id)
	for t in _invites:
		_invites[t].erase(id)
	_peers.erase(id)
	_dirty.erase(id)
	_rate.erase(id)
	_tell_instance(inst, id, "_rpc_gone", [id])
	if mode == Mode.SERVER:
		print("Net: %d left (%d online)" % [id, _peers.size()])


func _on_hello(id: int, protocol: int, info: Dictionary) -> void:
	_pending.erase(id)
	if _peers.has(id):
		return
	if protocol != PROTOCOL:
		_send(id, "_rpc_refused", ["That server runs a different version of Tainted: update the game."])
		return
	if _peers.size() >= _max_online:
		_send(id, "_rpc_refused", ["That server is full (%d players)." % _max_online])
		return
	_peers[id] = {"info": _clean_info(info), "instance": "", "state": {}, "party": 0}
	_send(id, "_rpc_welcome", [server_name, _peers.size()])
	if mode == Mode.SERVER:
		print("Net: %s joined (%d online)" % [_peers[id].info.name, _peers.size()])


func _on_enter(id: int, inst: String, state: Dictionary) -> void:
	if not _peers.has(id):
		return
	state = _clean_state(state)
	var rec: Dictionary = _peers[id]
	var old: String = rec.instance
	if old != "":
		_tell_instance(old, id, "_rpc_gone", [id])
	rec.instance = inst
	rec.state = state
	if inst == "":
		return
	for other in _peers:
		if other != id and _peers[other].instance == inst:
			_send(id, "_rpc_present", [other, _peers[other].info, _peers[other].state])
	_tell_instance(inst, id, "_rpc_present", [id, rec.info, state])


func _on_state(id: int, state: Dictionary) -> void:
	if _peers.has(id):
		var s := _clean_state(state)
		if not s.is_empty():
			_peers[id].state = s
			_dirty[id] = true


func _on_looks(id: int, info: Dictionary) -> void:
	if not _peers.has(id):
		return
	_peers[id].info = _clean_info(info)
	_tell_instance(_peers[id].instance, id, "_rpc_looks_of", [id, _peers[id].info])
	if _peers[id].party != 0:
		_tell_party(_peers[id].party)  # a new level shows in the party list


## Each instance's changed states, in one message to each of its players.
func _relay_states() -> void:
	if _dirty.is_empty():
		return
	var by_inst := {}
	for id in _dirty:
		if _peers.has(id) and _peers[id].instance != "":
			var inst: String = _peers[id].instance
			if not by_inst.has(inst):
				by_inst[inst] = {}
			by_inst[inst][id] = _peers[id].state
	_dirty.clear()
	for id in _peers:
		var batch: Dictionary = by_inst.get(_peers[id].instance, {})
		if batch.is_empty() or (batch.size() == 1 and batch.has(id)):
			continue
		var mine := batch.duplicate()
		mine.erase(id)
		if id == 1:
			_rpc_states(mine)
		else:
			_rpc_states.rpc_id(id, mine)


## Sends `method(args)` to every player in `inst` but `except`.
func _tell_instance(inst: String, except: int, method: String, args: Array) -> void:
	if inst == "":
		return
	for id in _peers:
		if id != except and _peers[id].instance == inst:
			_send(id, method, args)


## Calls `method` on peer `id`: by RPC, or straight away for the host's own player.
func _send(id: int, method: String, args: Array) -> void:
	if id == 1 and mode == Mode.HOST:
		callv(method, args)
	elif id != 1:
		callv("rpc_id", [id, method] + args)


## A state with only its expected fields, of the expected types and within sane ranges ({} if unusable).
static func _clean_state(s: Dictionary) -> Dictionary:
	var p = s.get("p")
	if not p is Vector2 or not p.is_finite():
		return {}
	var a = s.get("a", "Idle")
	return {"p": p.clamp(Vector2(-100000, -100000), Vector2(100000, 100000)),
		"f": clampf(float(s.get("f", 1.0)) if s.get("f") is float or s.get("f") is int else 1.0, -1.0, 1.0),
		"a": String(a).left(32) if a is String else "Idle",
		"s": clampf(float(s.get("s", 1.0)) if s.get("s") is float or s.get("s") is int else 1.0, 0.0, 4.0),
		"h": clampf(float(s.get("h", 1.0)) if s.get("h") is float or s.get("h") is int else 1.0, 0.0, 1.0),
		"w": String(s.get("w", "")).left(40) if s.get("w") is String else ""}


## A player's name as others see it: printable characters only, at most 24.
static func _clean_name(n) -> String:
	var out := ""
	for ch in String(n) if n is String else "?":
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().left(24)
	return out if out != "" else "?"


## Only the fields others need, of the expected types (a client's word isn't taken blindly).
static func _clean_info(info: Dictionary) -> Dictionary:
	var gear := {}
	var g = info.get("gear", {})
	if g is Dictionary:
		for slot in g:
			if g[slot] is Array and g[slot].size() == 2 and slot is String and slot in Player.VISIBLE_SLOTS + ["offhand"] \
					and g[slot][0] is String:
				var second = g[slot][1]
				gear[slot] = [String(g[slot][0]).left(48), bool(second) if slot == "offhand" else (String(second).left(24) if second is String else "")]
	var look = info.get("look", {})
	var cls = info.get("class", "warrior")
	var lvl = info.get("level", 1)
	return {"name": _clean_name(info.get("name", "?")), "class": String(cls).left(24) if cls is String else "warrior",
		"level": clampi(int(lvl), 1, 999) if lvl is int or lvl is float else 1,
		"look": Appearance.sanitize(look if look is Dictionary else {}), "gear": gear}


# ---------- parties: what a player does ----------

## Invite player `id` to your party (you lead it if you have none).
func invite(id: int) -> void:
	_to_server("_on_invite", "_rpc_invite", [id])


## Answer `from_id`'s invite.
func answer_invite(from_id: int, accept: bool) -> void:
	_to_server("_on_answer", "_rpc_answer", [from_id, accept])


func leave_party() -> void:
	_to_server("_on_leave_party", "_rpc_leave_party", [])


## Leader only: remove `id` from the party.
func kick(id: int) -> void:
	_to_server("_on_kick", "_rpc_kick", [id])


## Leader only: make `id` the leader.
func promote(id: int) -> void:
	_to_server("_on_promote", "_rpc_promote", [id])


## Runs `on_method(my id, args...)` on the server: here when hosting, else by RPC `rpc_method`.
func _to_server(on_method: String, rpc_method: String, args: Array) -> void:
	if mode == Mode.HOST:
		callv(on_method, [1] + args)
	elif mode == Mode.CLIENT:
		callv("rpc_id", [1, rpc_method] + args)


# ---------- parties: the server ----------

func _on_invite(from: int, target: int) -> void:
	if not _peers.has(from) or not _peers.has(target) or from == target:
		return
	var tname: String = _peers[target].info.name
	var pid: int = _peers[from].party
	if pid != 0 and _parties[pid].leader != from:
		_send(from, "_rpc_notice", ["Only the party leader can invite."])
		return
	if pid != 0 and _parties[pid].members.size() >= PARTY_MAX:
		_send(from, "_rpc_notice", ["Your party is full (%d players)." % PARTY_MAX])
		return
	if _peers[target].party != 0:
		_send(from, "_rpc_notice", ["%s is already in a party." % tname])
		return
	if not _invites.has(target):
		_invites[target] = {}
	_invites[target][from] = Time.get_ticks_msec()
	_send(target, "_rpc_invited", [from, String(_peers[from].info.name)])
	_send(from, "_rpc_notice", ["Invited %s to your party." % tname])


func _on_answer(target: int, from: int, accept: bool) -> void:
	var asked: Dictionary = _invites.get(target, {})
	if not asked.has(from) or not _peers.has(from) or not _peers.has(target):
		_send(target, "_rpc_notice", ["That invite is no longer open."])
		return
	var at: int = asked[from]
	asked.erase(from)
	var tname: String = _peers[target].info.name
	if Time.get_ticks_msec() - at > INVITE_TIMEOUT * 1000.0:
		_send(target, "_rpc_notice", ["That invite has run out."])
		return
	if not accept:
		_send(from, "_rpc_notice", ["%s declined your invite." % tname])
		return
	if _peers[target].party != 0:
		_send(target, "_rpc_notice", ["Leave your party first."])
		return
	var pid: int = _peers[from].party
	if pid == 0:
		pid = _next_party
		_next_party += 1
		_parties[pid] = {"leader": from, "members": [from]}
		_peers[from].party = pid
	if _parties[pid].members.size() >= PARTY_MAX:
		_send(target, "_rpc_notice", ["That party is full."])
		return
	_parties[pid].members.append(target)
	_peers[target].party = pid
	_invites.erase(target)  # in a party now: other invites lapse
	_tell_party(pid, "%s joined the party." % tname)


func _on_leave_party(id: int) -> void:
	if _peers.has(id) and _peers[id].party != 0:
		_remove_from_party(id, "%s left the party." % _peers[id].info.name)


func _on_kick(leader: int, target: int) -> void:
	if not _peers.has(leader) or not _peers.has(target) or leader == target:
		return
	var pid: int = _peers[leader].party
	if pid == 0 or _parties[pid].leader != leader or _peers[target].party != pid:
		return
	_send(target, "_rpc_notice", ["You were removed from the party."])
	_remove_from_party(target, "%s was removed from the party." % _peers[target].info.name)


func _on_promote(leader: int, target: int) -> void:
	if not _peers.has(leader) or not _peers.has(target):
		return
	var pid: int = _peers[leader].party
	if pid == 0 or _parties[pid].leader != leader or _peers[target].party != pid:
		return
	_parties[pid].leader = target
	_tell_party(pid, "%s now leads the party." % _peers[target].info.name)


## Takes `id` out of its party: the lead passes on if it led, and a party of one disbands.
func _remove_from_party(id: int, why: String) -> void:
	var pid: int = _peers[id].party if _peers.has(id) else 0
	if pid == 0 or not _parties.has(pid):
		return
	var p: Dictionary = _parties[pid]
	p.members.erase(id)
	_peers[id].party = 0
	_send(id, "_rpc_party", [{}])
	if p.members.size() <= 1:
		for m in p.members:
			_peers[m].party = 0
			_send(m, "_rpc_party", [{}])
			_send(m, "_rpc_notice", [why + " The party disbanded."])
		_parties.erase(pid)
		return
	if p.leader == id:
		p.leader = p.members[0]
	_tell_party(pid, why)


## Sends party `pid`'s members and leader to each member, with `why` as a notice.
func _tell_party(pid: int, why := "") -> void:
	if not _parties.has(pid):
		return
	var p: Dictionary = _parties[pid]
	var members: Array = []
	for m in p.members:
		var info: Dictionary = _peers[m].info
		members.append({"id": m, "name": info.name, "level": info.level, "class": info["class"]})
	var data := {"id": pid, "leader": p.leader, "members": members}
	for m in p.members:
		_send(m, "_rpc_party", [data])
		if why != "":
			_send(m, "_rpc_notice", [why])


## Each party's life and whereabouts, to its members.
func _relay_vitals() -> void:
	var now := Time.get_ticks_msec()
	for t in _invites.keys():  # forget invites nobody answered
		for f in _invites[t].keys():
			if now - int(_invites[t][f]) > INVITE_TIMEOUT * 1000.0:
				_invites[t].erase(f)
		if _invites[t].is_empty():
			_invites.erase(t)
	for pid in _parties:
		var batch := {}
		for m in _parties[pid].members:
			var s: Dictionary = _peers[m].state
			batch[m] = {"h": s.get("h", 1.0), "w": s.get("w", "")}
		for m in _parties[pid].members:
			_send(m, "_rpc_vitals", [batch])


# ---------- RPCs: client -> server ----------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_invite(target: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_invite(id, target)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_answer(from: int, accept: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_answer(id, from, accept)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_leave_party() -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_leave_party(id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_kick(target: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_kick(id, target)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_promote(target: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_promote(id, target)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(protocol: int, info: Dictionary) -> void:
	if is_server():
		_on_hello(multiplayer.get_remote_sender_id(), protocol, info)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_enter(inst: String, state: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_enter(id, inst.left(64), state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_state(state: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_state(id, state)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ping() -> void:
	pass  # only to keep the connection busy


@rpc("any_peer", "call_remote", "reliable")
func _rpc_looks(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_looks(id, info)


# ---------- RPCs: server -> client ----------

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(name: String, _count: int) -> void:
	server_name = name
	_set_status(Mode.CLIENT, "Online: %s" % name)


@rpc("authority", "call_remote", "reliable")
func _rpc_refused(reason: String) -> void:
	leave()
	_set_status(Mode.OFFLINE, reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_present(id: int, info: Dictionary, state: Dictionary) -> void:
	others[id] = info
	peer_joined.emit(id, info, state)


@rpc("authority", "call_remote", "reliable")
func _rpc_gone(id: int) -> void:
	if others.erase(id):
		peer_left.emit(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_states(batch: Dictionary) -> void:
	for id in batch:
		if others.has(id):
			peer_state.emit(id, batch[id])


@rpc("authority", "call_remote", "reliable")
func _rpc_looks_of(id: int, info: Dictionary) -> void:
	if others.has(id):
		others[id] = info
		peer_looks.emit(id, info)


@rpc("authority", "call_remote", "reliable")
func _rpc_party(data: Dictionary) -> void:
	party = data
	party_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_invited(from: int, from_name: String) -> void:
	invited.emit(from, from_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(text: String) -> void:
	notice.emit(text)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_vitals(batch: Dictionary) -> void:
	party_vitals.emit(batch)


# ---------- finding servers on the Wi-Fi ----------

## Ask the Wi-Fi which servers are there; servers_found lists them as they answer (call again to refresh).
func scan() -> void:
	if _disc_client == null:
		_disc_client = PacketPeerUDP.new()
		_disc_client.set_broadcast_enabled(true)
		_disc_client.bind(0)
	_found.clear()
	var msg := DISCOVER_MSG.to_utf8_buffer()
	for addr in ["255.255.255.255", "127.0.0.1"]:  # the second finds a server on this same device
		_disc_client.set_dest_address(addr, DISCOVERY_PORT)
		_disc_client.put_packet(msg)
	servers_found.emit([])


func stop_scan() -> void:
	if _disc_client != null:
		_disc_client.close()
		_disc_client = null


func _poll_discovery() -> void:
	if _disc_server != null:
		while _disc_server.get_available_packet_count() > 0:
			var pkt := _disc_server.get_packet().get_string_from_utf8()
			if pkt == DISCOVER_MSG:
				_disc_server.set_dest_address(_disc_server.get_packet_ip(), _disc_server.get_packet_port())
				_disc_server.put_packet(JSON.stringify({"name": server_name, "players": _peers.size(),
					"max": MAX_ONLINE, "protocol": PROTOCOL}).to_utf8_buffer())
	if _disc_client != null:
		var changed := false
		while _disc_client.get_available_packet_count() > 0:
			var raw := _disc_client.get_packet().get_string_from_utf8()
			var ip := _disc_client.get_packet_ip()
			var d = JSON.parse_string(raw)
			if d is Dictionary and int(d.get("protocol", 0)) == PROTOCOL:
				# The same server answers on loopback and the Wi-Fi: keep one, by name
				var key := String(d.get("name", ip))
				if not _found.has(key) or ip != "127.0.0.1":
					_found[key] = {"name": key, "address": ip, "players": int(d.get("players", 0)), "max": int(d.get("max", 0))}
					changed = true
		if changed:
			servers_found.emit(_found.values())
