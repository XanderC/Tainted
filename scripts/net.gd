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
## Party instances (stage 3): a member opens a rift (open_party_rift); the server makes an instance
## "rift:<party>:<n>" only that party may enter, and tells the members (party_portal; the party data
## carries it too, so latecomers can join from the party list). The first member in is the instance's
## host (role_changed): its game runs the monsters (Coop), the others' games follow it. Instance
## events (send_event / event) go between them through the server: to everyone else in the instance,
## to its host, or to one player. When the host leaves, the next member takes over.
##
## Staying connected (stage 4): a client that loses the server reconnects by itself (RECONNECTING, a
## try every RECONNECT_EVERY seconds for a while; at once when an Android app comes back to the front),
## then goes back into the instance it was in. Each game has a random session token, sent with its
## hello: a party member who drops is kept "away" in the party for AWAY_GRACE seconds, and coming back
## with the same token puts them back in it. A busy town is split into copies of TOWN_CAP players
## ("town", "town~2"...), party members kept together.
##
## Online characters (stage 5): a dedicated server started with --data=<dir> keeps its players'
## characters (AccountStore), and says so in its welcome (`accounts`). Its players' games then load
## their account from the server (GameState.use_online_files) and save to it (save_file), instead of
## the device; offline play and hosted games keep the device's characters. Who an account is comes
## with the hello: an Autharr sign-in (sign_in: email and password, Autharr's password grant for the
## tainted-game client; a refresh token kept encrypted on the device signs you in next time), or on a
## server that doesn't ask for one, a random key this device keeps (device_key). A server started with
## --auth=<Autharr URL> asks for it and checks each sign-in against Autharr's /connect/userinfo.
## One game per account: a second one replaces the first.
##
## Chat (say): "local" goes to everyone in your instance (your copy of the town, your rift or zone),
## "party" to your party. The server cleans each line (printable, at most CHAT_MAX characters, a word
## filter: _clean_chat) and allows one every CHAT_EVERY seconds.
## Friends (on a server that keeps characters): ask a player (add_friend), they accept, and each
## account keeps the other (AccountStore.social, which a game can't write). Every FRIENDS_EVERY
## seconds the server sends each player their friends: who is online, where, and their peer id (to
## invite them to a party from anywhere).
## Trading (on a server that keeps characters): ask a player (trade_with); once they accept, each
## offers items from their bag (trade_offer, by item id), checked against the bag the server has
## saved; both press Ready (any change resets it), and the server swaps them: it takes the items out of
## the givers' saved bags, puts them in the receivers' saved stash (overflow), tells both games
## (trade_done), and from then on strips the given items from the givers' saves (their "gone" ids), so
## a game can't keep what it traded.
## Inspecting (inspect): the server asks that player's game for its worn gear and stats
## (_inspect_data) and passes them on (inspected), if you can see them (same instance or party).
##
## The server's records live in _peers (id -> {"info", "instance", "state", "party", "token",
## "account"}), _parties and _instances; the host is peer 1.
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
signal party_portal(portal: Dictionary)  ## a member opened a party instance: {"inst", "kind", "level", "by", "by_name"}
signal role_changed(host_id: int)  ## who hosts your instance (runs its monsters) changed; you if == my_id()
signal event(from_id: int, kind: String, data: Variant)  ## an instance event (send_event)
signal account_ready  ## the server's characters for your account are loaded (GameState.use_online_files)
signal chat(from_id: int, from_name: String, channel: String, text: String)  ## a chat line (say)
signal inspected(id: int, data: Dictionary)  ## a player's worn gear and stats (inspect)
signal friends_changed  ## `friends` changed
signal friend_asked(from_id: int, from_name: String)  ## someone wants to be your friend (answer_friend)
signal trade_asked(from_id: int, from_name: String)  ## someone wants to trade (answer_trade)
signal trade_changed(state: Dictionary)  ## a trade opened or changed: {"with", "name", "mine", "theirs", "ready_me", "ready_them"}; {} closed
signal trade_finished(received: Array)  ## the trade went through: what you got (now in your stash)
signal signed_in_changed  ## signed in or out of Autharr (`signed_in_as`), or a sign-in failed (`sign_in_error`)

const PORT := 24601
const DISCOVERY_PORT := 24602
const PROTOCOL := 10  ## games with a different protocol can't play together
const MAX_ONLINE := 32
const PARTY_MAX := 4
const SEND_HZ := 15.0
const DISCOVER_MSG := "TAINTED_DISCOVER"
const TOWN := "town"
const MAX_EVENTS_PER_SEC := 240  ## instance events per client (monster updates, hits...)
const AWAY_GRACE := 60.0  ## seconds a dropped party member's place is kept
const RECONNECT_EVERY := 4.0
const RECONNECT_TRIES := 10
const TOWN_CAP := 20  ## players in one copy of the town
const TRADE_MAX_ITEMS := 10
const GONE_KEEP := 2000  ## traded-away item ids remembered per account
const FRIENDS_EVERY := 2.0
const MAX_FRIENDS := 100
const CHAT_MAX := 200
const CHAT_EVERY := 0.6  ## seconds between one player's chat lines
## Words the chat masks with stars (whole words, any case).
const CHAT_FILTER := ["fuck", "fucking", "fucker", "shit", "cunt", "bitch", "nigger", "nigga", "faggot", "fag",
	"retard", "whore", "slut", "dick", "pussy", "asshole", "bastard", "twat", "wanker", "spastic"]
const INVITE_TIMEOUT := 60.0  ## seconds an invite can be answered
const VITALS_HZ := 2.0  ## party members' life and whereabouts, this often
const HELLO_TIMEOUT := 10.0  ## seconds a new connection has to say hello before it is dropped
const KEEPALIVE := 20.0  ## a client says something at least this often (proxies drop idle WebSockets)
const MAX_MSGS_PER_SEC := 40  ## per client; more are dropped
## The Tainted World, unless project settings say otherwise.
const WORLD_NAME_DEFAULT := "Tainted World"
const WORLD_ADDRESSES_DEFAULT := ["ws://192.168.86.18:24601"]
const AUTH_URL_DEFAULT := "http://192.168.86.18:5180"  ## Autharr, for the sign-in (project setting tainted/net/auth_url)
const AUTH_CLIENT := "tainted-game"
const AUTH_FILE := "user://autharr.dat"

enum Mode { OFFLINE, CONNECTING, CLIENT, HOST, SERVER, RECONNECTING }

var mode := Mode.OFFLINE
var status := ""  ## a line for the player: "Connected to Home", "Connection failed"...
var server_name := ""
var instance := ""  ## the instance this game's player is in ("" while in none)
var others := {}  ## the other players in your instance: id -> info
## Your party: {"id", "leader", "members": [{"id", "name", "level", "class"}]}, or {} when on your own.
var party := {}
## The party instance this game is joining or in: {"inst", "kind", "level", "by", "by_name"}, else {}.
## Read by the scene it loads (a rift: Coop).
var coop := {}
## The server keeps your characters (its welcome said so): GameState saves to it (save_file).
var accounts := false
var auth_url := String(ProjectSettings.get_setting("tainted/net/auth_url", AUTH_URL_DEFAULT))
var signed_in_as := ""  ## the Autharr account's name ("" when not signed in)
var sign_in_error := ""
var _access_token := ""
var _http: HTTPRequest  # client: talking to Autharr
static var auth_file := AUTH_FILE  ## where the kept sign-in is (tests use their own)
## Your friends: [{"account", "name", "online", "id" (peer, if online), "where"}], online ones first.
var friends: Array = []
var instance_host := 0  ## who hosts your instance (role_changed)
var party_ui: PartyUI
var chat_ui: ChatUI  ## the chat on screen (not on a dedicated server)
var inspect_ui: InspectUI  ## another player's gear (inspect)
var trade_ui: TradeUI  ## an open trade
var chat_typing := false  ## the chat box has the keyboard: the game ignores its keys meanwhile  ## the party list, invites and player cards on screen (not on a dedicated server)
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
var town_cap := TOWN_CAP  ## players in one copy of the town (a dedicated server's --town-cap)
var _world_queue: Array = []  # Tainted World addresses still to try
var _keep_t := 0.0
var _pending := {}  # server only: id -> msec it connected, until it says hello
var _rate := {}  # server only: id -> [second, messages that second]
var _parties := {}  # server only: party id -> {"leader": id, "members": [ids]}
var _next_party := 1
var _invites := {}  # server only: invited id -> {inviter id: msec}
var _vitals_t := 0.0
var _instances := {}  # server only: party instance -> {"host": id}
var _next_inst := 1
var _event_rate := {}  # server only: id -> [second, events that second]
var _token := ""  # this game's session token (who you are across a reconnect)
var _url := ""  # the server being connected to
var _reconnect_url := ""  # the server to reconnect to ("" when you left on purpose)
var _reconnect_t := 0.0
var _reconnect_tries := 0
var _rejoin := ""  # the instance to go back into once reconnected
var _rejoin_coop := {}
var _store: AccountStore  # server only, with --data: the players' characters
var _auth_check := ""  # server only, with --auth: Autharr's URL, to check sign-ins
var _store_t := 0.0
var _pending_saves := {}  # files to send once reconnected: vpath -> data (null: delete)
var _chat_at := {}  # server only: id -> msec of its last chat line
var _online_accounts := {}  # server only: account -> peer id
var _friend_asks := {}  # server only: asked id -> {asking id: msec}
var _friends_sent := {}  # server only: id -> the friend list last sent (sent again only when it changes)
var _friends_t := 0.0
var _trade_asks := {}  # server only: asked id -> {asking id: msec}
var _trades := {}  # server only: trade id -> {"p": [a, b], "offer": {id: [item dicts]}, "ready": {id: bool}}
var _trade_of := {}  # server only: peer id -> trade id
var _next_trade := 1
var _filter: RegEx


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep talking while a menu pauses the game
	_token = Crypto.new().generate_random_bytes(12).hex_encode()
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
			elif a.begins_with("--town-cap="):
				town_cap = clampi(int(a.get_slice("=", 1)), 1, 1000)
			elif a.begins_with("--data="):
				_store = AccountStore.new(a.get_slice("=", 1))
			elif a.begins_with("--auth="):
				_auth_check = a.get_slice("=", 1).trim_suffix("/")
		start_server(name_arg, true)
		get_tree().change_scene_to_file.call_deferred("res://scenes/server.tscn")
	else:
		_http = HTTPRequest.new()
		_http.timeout = 15.0
		add_child(_http)
		party_ui = PartyUI.new()
		add_child(party_ui)
		chat_ui = ChatUI.new()
		add_child(chat_ui)
		inspect_ui = InspectUI.new()
		add_child(inspect_ui)
		trade_ui = TradeUI.new()
		add_child(trade_ui)


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


## Whether this game hosts its instance (runs the monsters for the party there).
func is_instance_host() -> bool:
	return online() and instance_host == my_id()


## A party instance's id ("rift:3:12" -> party 3), or 0 for a shared one like the town.
static func party_of_instance(inst: String) -> int:
	if inst.begins_with("rift:") or inst.begins_with("zone:"):
		return int(inst.get_slice(":", 1))
	return 0


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
		_set_status(Mode.SERVER, "Server \"%s\" running on port %d (up to %d players)%s%s" % [name, PORT, _max_online,
			", characters in %s" % _store.base_dir if _store != null else "",
			", sign-in checked with %s" % _auth_check if _auth_check != "" else ""])
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


## Join the Tainted World: its addresses in turn until one answers (signing in again first if a
## sign-in is kept).
func join_world() -> void:
	await resume_sign_in()
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
	server_name = address
	if _open_client(url_of(address)):
		_set_status(Mode.CONNECTING, "Connecting to %s..." % address)


## Starts connecting to `url` (false, and the failure handled, if it can't even start).
func _open_client(url: String) -> bool:
	_url = url
	var peer := _ws_peer()
	if peer.create_client(url) != OK:
		_on_connection_failed()
		return false
	multiplayer.multiplayer_peer = peer
	return true


## A WebSocket peer sized for the game's messages (a town's states fit easily; anything far bigger is refused).
func _ws_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 256 * 1024
	peer.outbound_buffer_size = 256 * 1024
	peer.max_queued_packets = 1024
	peer.handshake_timeout = 5.0
	return peer


## Go offline (stop hosting, or leave the server). No reconnecting after this; if the server kept
## your characters, the device's are back.
func leave() -> void:
	_reconnect_url = ""
	_rejoin = ""
	_rejoin_coop = {}
	_pending_saves.clear()
	_drop()
	if accounts:
		accounts = false
		GameState.use_local_files()


## Closes the connection and forgets the online world (leave() also stops any reconnecting).
func _drop() -> void:
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
	_instances.clear()
	_event_rate.clear()
	coop = {}
	instance_host = 0
	instance = ""
	if not party.is_empty():
		party = {}
		party_changed.emit()
	if not friends.is_empty():
		friends = []
		friends_changed.emit()
	_online_accounts.clear()
	_friend_asks.clear()
	_friends_sent.clear()
	_trade_asks.clear()
	_trades.clear()
	_trade_of.clear()
	if mode != Mode.OFFLINE:
		_set_status(Mode.OFFLINE, "Offline")


func _set_status(m: Mode, text: String) -> void:
	mode = m
	status = text
	status_changed.emit()


func _on_connected() -> void:
	_rpc_hello.rpc_id(1, PROTOCOL, my_info())


func _on_connection_failed() -> void:
	if _reconnect_url != "" and _reconnect_tries < RECONNECT_TRIES:
		_wait_to_reconnect()
		return
	if _reconnect_url != "":
		leave()
		_set_status(Mode.OFFLINE, "Couldn't reconnect to %s" % server_name)
		return
	if not _world_queue.is_empty():
		_try_next_world()  # the next of the Tainted World's addresses
		return
	var what := server_name
	leave()
	_set_status(Mode.OFFLINE, "Couldn't connect to %s" % what)


## The connection dropped (not by leaving): try to get back, into the same place.
func _on_server_lost() -> void:
	if mode != Mode.CLIENT or _reconnect_url == "":
		leave()
		_set_status(Mode.OFFLINE, "Lost the connection to the server")
		return
	_rejoin = instance
	_rejoin_coop = coop.duplicate()
	_reconnect_tries = 0
	_wait_to_reconnect()


func _wait_to_reconnect() -> void:
	var keep := [_reconnect_url, _rejoin, _rejoin_coop, _reconnect_tries, server_name]
	_drop()
	_reconnect_url = keep[0]
	_rejoin = keep[1]
	_rejoin_coop = keep[2]
	_reconnect_tries = keep[3]
	server_name = keep[4]
	coop = _rejoin_coop.duplicate()  # the scene you're in is still the party's
	_reconnect_t = 1.0 if _reconnect_tries == 0 else RECONNECT_EVERY
	_set_status(Mode.RECONNECTING, "Connection lost: reconnecting to %s..." % server_name)


func _try_reconnect() -> void:
	_reconnect_tries += 1
	_set_status(Mode.RECONNECTING, "Reconnecting to %s (try %d)..." % [server_name, _reconnect_tries])
	_open_client(_reconnect_url)


## Back in front (Android): reconnect now rather than at the next try.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and mode == Mode.RECONNECTING:
		_reconnect_t = 0.0


## For tests: lose the connection as a bad signal would.
func simulate_drop() -> void:
	if mode == Mode.CLIENT:
		multiplayer.multiplayer_peer.close()
		_on_server_lost()


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
	var account := {"kind": "autharr", "token": _access_token} if _access_token != "" else {"kind": "device", "key": device_key()}
	return {"name": GameState.char_name, "class": GameState.char_class, "level": GameState.level,
		"look": GameState.appearance, "gear": gear, "token": _token, "account": account}


# ---------- signing in (Autharr) ----------

## Signs in to Autharr with an email and password (signed_in_changed says how it went). The refresh
## token is kept, encrypted with this device's key, so the next start signs in by itself.
func sign_in(email: String, password: String) -> void:
	await _token_request({"grant_type": "password", "username": email.strip_edges(), "password": password,
		"scope": "openid profile email offline_access tainted"})


## Signs in again with the kept refresh token, if there is one (at start, and before joining).
func resume_sign_in() -> void:
	var refresh := _kept_refresh()
	if refresh != "" and _access_token == "":
		await _token_request({"grant_type": "refresh_token", "refresh_token": refresh})


func sign_out() -> void:
	_access_token = ""
	signed_in_as = ""
	if FileAccess.file_exists(auth_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(auth_file))
	signed_in_changed.emit()


func _token_request(form: Dictionary) -> void:
	if _http == null:
		return
	form["client_id"] = AUTH_CLIENT
	var body := "&".join(PackedStringArray(form.keys().map(func(k): return "%s=%s" % [k, String(form[k]).uri_encode()])))
	sign_in_error = ""
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var err := _http.request(auth_url + "/connect/token", ["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, body)
	if err != OK:
		sign_in_error = "Couldn't reach the sign-in server."
		signed_in_changed.emit()
		return
	var res: Array = await _http.request_completed
	var code: int = res[1]
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		sign_in_error = "Couldn't reach the sign-in server."
	elif code != 200 or not data is Dictionary or not data.has("access_token"):
		sign_in_error = String(data.get("error_description", "Sign-in failed.")) if data is Dictionary else "Sign-in failed."
		if form.grant_type == "refresh_token":
			sign_out()  # the kept sign-in no longer works: ask again
			return
	else:
		_access_token = String(data.access_token)
		if data.has("refresh_token"):
			_keep_refresh(String(data.refresh_token))
		signed_in_as = _name_in_token(_access_token)
	signed_in_changed.emit()


## The name (or email) in a JWT's claims, for showing who you are signed in as.
static func _name_in_token(jwt: String) -> String:
	var parts := jwt.split(".")
	if parts.size() < 2:
		return "?"
	var b64 := parts[1].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var claims = JSON.parse_string(Marshalls.base64_to_utf8(b64))
	return String(claims.get("name", claims.get("email", "?"))) if claims is Dictionary else "?"


func _keep_refresh(token: String) -> void:
	var f := FileAccess.open_encrypted_with_pass(auth_file, FileAccess.WRITE, device_key())
	if f != null:
		f.store_string(token)


func _kept_refresh() -> String:
	if not FileAccess.file_exists(auth_file):
		return ""
	var f := FileAccess.open_encrypted_with_pass(auth_file, FileAccess.READ, device_key())
	return f.get_as_text().strip_edges() if f != null else ""


## This device's account key (made once, kept in user://): who you are to a server that keeps
## characters, until signing in replaces it.
static var test_key := ""  ## tests' own account key, so they don't use (and fill) this device's account


static func device_key() -> String:
	if test_key != "":
		return test_key
	var path := "user://device_key.txt"
	if FileAccess.file_exists(path):
		var k := FileAccess.get_file_as_string(path).strip_edges()
		if k.length() >= 32:
			return k
	var key := Crypto.new().generate_random_bytes(24).hex_encode()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(key)
	return key


## Ask player `id` to be friends (they're asked: friend_asked).
func add_friend(id: int) -> void:
	_to_server("_on_friend_request", "_rpc_friend_request", [id])


func answer_friend(from_id: int, accept: bool) -> void:
	_to_server("_on_friend_answer", "_rpc_friend_answer", [from_id, accept])


## No longer friends with `account` (both sides).
func unfriend(account: String) -> void:
	_to_server("_on_unfriend", "_rpc_unfriend", [account])


## Whether player `id` (online now) is a friend.
func is_friend(id: int) -> bool:
	return friends.any(func(f): return int(f.get("id", 0)) == id)


## Ask player `id` to trade (they're asked: trade_asked).
func trade_with(id: int) -> void:
	GameState.save()  # the server checks offers against your saved bag
	_to_server("_on_trade_request", "_rpc_trade_request", [id])


func answer_trade(from_id: int, accept: bool) -> void:
	if accept:
		GameState.save()
	_to_server("_on_trade_answer", "_rpc_trade_answer", [from_id, accept])


## What you offer: the ids of items in your bag (at most TRADE_MAX_ITEMS).
func trade_offer(uids: Array) -> void:
	GameState.save()
	_to_server("_on_trade_offer", "_rpc_trade_offer", [uids.slice(0, TRADE_MAX_ITEMS)])


func trade_ready(on: bool) -> void:
	_to_server("_on_trade_ready", "_rpc_trade_ready", [on])


func trade_cancel() -> void:
	_to_server("_on_trade_cancel", "_rpc_trade_cancel", [])


## Ask to see player `id`'s gear and stats (inspected).
func inspect(id: int) -> void:
	_to_server("_on_inspect", "_rpc_inspect", [id])


## What others see when they inspect you: your worn gear (as saved) and a few stats.
func _inspect_data() -> Dictionary:
	var p = GameState.player
	var eq := {}
	var stats := {}
	if is_instance_valid(p):
		for slot in p.equipment:
			eq[slot] = p.equipment[slot].to_dict()
		for k in ["damage", "attack_speed", "crit_chance", "armor", "max_life", "move_speed"]:
			stats[k] = p.stats.get_stat(k)
	return {"name": GameState.char_name, "class": GameState.char_class, "level": GameState.level,
		"equipment": eq, "stats": stats}


## Says `text` on `channel` ("local" or "party").
func say(channel: String, text: String) -> void:
	text = text.strip_edges()
	if text != "" and online():
		_to_server("_on_chat", "_rpc_chat", [channel, text.left(CHAT_MAX)])


## Stores one of GameState's save files on the server (only while it keeps your characters; while
## reconnecting it waits and goes once back).
func save_file(vpath: String, data: Dictionary) -> void:
	if mode == Mode.CLIENT and accounts:
		_rpc_save_file.rpc_id(1, vpath, data)
	elif mode == Mode.RECONNECTING and accounts:
		_pending_saves[vpath] = data


func delete_file(vpath: String) -> void:
	if mode == Mode.CLIENT and accounts:
		_rpc_delete_file.rpc_id(1, vpath)
	elif mode == Mode.RECONNECTING and accounts:
		_pending_saves[vpath] = null


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
	instance_host = 0
	if coop.get("inst", "") != inst:
		coop = {}  # left the party instance
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
	if mode == Mode.RECONNECTING:
		_reconnect_t -= delta
		if _reconnect_t <= 0.0 and multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			_try_reconnect()
	if mode == Mode.CLIENT:
		_keep_t -= delta
		if _keep_t <= 0.0:
			_keep_t = KEEPALIVE
			_rpc_ping.rpc_id(1)  # so a proxy never sees the connection idle
	if is_server():
		_drop_silent()
		if _store != null:
			_store_t -= delta
			if _store_t <= 0.0:
				_store_t = 1.0
				_store.flush()
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
		_friends_t -= delta
		if _friends_t <= 0.0 and _store != null:
			_friends_t = FRIENDS_EVERY
			for id in _peers:
				_push_friends(id)


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
	if _store != null and String(_peers[id].get("account", "")) != "":
		_store.flush_account(String(_peers[id].account))
		if _online_accounts.get(_peers[id].account, 0) == id:
			_online_accounts.erase(_peers[id].account)
	_friend_asks.erase(id)
	_friends_sent.erase(id)
	_trade_asks.erase(id)
	_end_trade(id, "%s left." % _peers[id].info.name)
	var inst: String = _peers[id].instance
	_peers[id].instance = ""
	_instance_left(inst, id)
	_remove_from_party(id, "%s lost their connection." % _peers[id].info.name, true)
	_invites.erase(id)
	for t in _invites:
		_invites[t].erase(id)
	_peers.erase(id)
	_dirty.erase(id)
	_rate.erase(id)
	_event_rate.erase(id)
	_chat_at.erase(id)
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
	var token := String(info.get("token", "")).left(64) if info.get("token") is String else ""
	var account := ""
	if _store != null:
		var a = info.get("account", {})
		if _auth_check != "":
			# Signing in is required: Autharr says who the token belongs to
			if not a is Dictionary or String(a.get("kind", "")) != "autharr" or String(a.get("token", "")) == "":
				_send(id, "_rpc_refused", ["Sign in to play on this server."])
				return
			_pending[id] = Time.get_ticks_msec()  # a moment more while Autharr answers
			account = await _check_sign_in(String(a.token).left(8192))
			_pending.erase(id)
			if not multiplayer.get_peers().has(id) and id != 1:
				return  # gone while waiting
			if account == "":
				_send(id, "_rpc_refused", ["Your sign-in didn't work: sign in again."])
				return
		else:
			account = _account_of(a)
		if account == "":
			_send(id, "_rpc_refused", ["That server needs you to sign in."])
			return
		for other in _peers.keys():  # one game per account: the newer one replaces the older
			if _peers[other].get("account", "") == account:
				_send(other, "_rpc_refused", ["You started playing this account somewhere else."])
				_kick(other)
	_peers[id] = {"info": _clean_info(info), "instance": "", "state": {}, "party": 0, "token": token, "account": account}
	if account != "":
		_online_accounts[account] = id
	_send(id, "_rpc_welcome", [server_name, _peers.size(), _store != null])
	_restore_away(id, token)
	if mode == Mode.SERVER:
		print("Net: %s joined (%d online)" % [_peers[id].info.name, _peers.size()])


func _on_enter(id: int, inst: String, state: Dictionary) -> void:
	if not _peers.has(id):
		return
	state = _clean_state(state)
	var pid := party_of_instance(inst)
	if pid != 0 and _peers[id].party != pid:
		_send(id, "_rpc_notice", ["That belongs to another party."])
		return
	if inst == TOWN:
		inst = _town_copy(id)
	var rec: Dictionary = _peers[id]
	var old: String = rec.instance
	if old == inst:
		return
	if old != "":
		_tell_instance(old, id, "_rpc_gone", [id])
	rec.instance = inst
	rec.state = state
	if old != "":
		_instance_left(old, id)
	if inst == "":
		return
	if pid != 0:
		if not _instances.has(inst) or not _peers.has(int(_instances[inst].host)) \
				or _peers[int(_instances[inst].host)].instance != inst:
			_instances[inst] = {"host": id}
		_send(id, "_rpc_role", [int(_instances[inst].host)])
	for other in _peers:
		if other != id and _peers[other].instance == inst:
			_send(id, "_rpc_present", [other, _peers[other].info, _peers[other].state])
	_tell_instance(inst, id, "_rpc_present", [id, rec.info, state])


## Asks Autharr whose access token this is ("a" + its subject, or "" if it isn't a valid one).
func _check_sign_in(access_token: String) -> String:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var err := http.request(_auth_check + "/connect/userinfo", ["Authorization: Bearer " + access_token])
	if err != OK:
		http.queue_free()
		return ""
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return ""
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var sub := String(d.get("sub", "")) if d is Dictionary else ""
	return ("a" + sub.left(64)) if sub != "" else ""


## The account a hello's `account` field stands for ("" if none): a device key for now.
static func _account_of(a) -> String:
	if not a is Dictionary:
		return ""
	if String(a.get("kind", "")) == "device":
		var key := String(a.get("key", ""))
		if key.length() >= 32 and key.length() <= 128:
			return "d" + key.sha256_text().left(40)
	return ""


func _on_chat(id: int, channel: String, text: String) -> void:
	if not _peers.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_chat_at.get(id, -100000)) < CHAT_EVERY * 1000.0:
		_send(id, "_rpc_notice", ["Not so fast."])
		return
	_chat_at[id] = now
	text = _clean_chat(text)
	if text == "":
		return
	var who: Array = []
	if channel == "party":
		var pid: int = _peers[id].party
		if pid == 0 or not _parties.has(pid):
			_send(id, "_rpc_notice", ["You're not in a party."])
			return
		who = _parties[pid].members
	else:
		channel = "local"
		var inst: String = _peers[id].instance
		who = _peers.keys().filter(func(p): return p == id or (inst != "" and _peers[p].instance == inst))
	var name: String = _peers[id].info.name
	for p in who:
		_send(p, "_rpc_chat_of", [id, name, channel, text])


## A chat line as others see it: printable characters, at most CHAT_MAX, CHAT_FILTER words starred.
func _clean_chat(text: String) -> String:
	var out := ""
	for ch in text:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().left(CHAT_MAX)
	if _filter == null:
		_filter = RegEx.create_from_string("(?i)\\b(" + "|".join(PackedStringArray(CHAT_FILTER)) + ")\\b")
	for m in _filter.search_all(out):
		out = out.substr(0, m.get_start()) + "*".repeat(m.get_end() - m.get_start()) + out.substr(m.get_end())
	return out


func _on_friend_request(from: int, target: int) -> void:
	if _store == null or not _peers.has(from) or not _peers.has(target) or from == target:
		return
	var a := String(_peers[from].get("account", ""))
	var b := String(_peers[target].get("account", ""))
	if a == "" or b == "" or a == b:
		return
	if _store.social(a).get("friends", {}).has(b):
		_send(from, "_rpc_notice", ["You're friends already."])
		return
	if _store.social(a).get("friends", {}).size() >= MAX_FRIENDS:
		_send(from, "_rpc_notice", ["Your friends list is full."])
		return
	if not _friend_asks.has(target):
		_friend_asks[target] = {}
	_friend_asks[target][from] = Time.get_ticks_msec()
	_send(target, "_rpc_friend_ask", [from, String(_peers[from].info.name)])
	_send(from, "_rpc_notice", ["Asked %s to be friends." % _peers[target].info.name])


func _on_friend_answer(target: int, from: int, accept: bool) -> void:
	var asked: Dictionary = _friend_asks.get(target, {})
	if not asked.has(from) or not _peers.has(from) or not _peers.has(target):
		_send(target, "_rpc_notice", ["That request is no longer open."])
		return
	asked.erase(from)
	if not accept:
		_send(from, "_rpc_notice", ["%s said no." % _peers[target].info.name])
		return
	var a := String(_peers[from].account)
	var b := String(_peers[target].account)
	_befriend(a, b, String(_peers[target].info.name))
	_befriend(b, a, String(_peers[from].info.name))
	for p in [from, target]:
		_send(p, "_rpc_notice", ["%s and %s are friends now." % [_peers[from].info.name, _peers[target].info.name]])
		_push_friends(p)


func _befriend(account: String, friend: String, name: String) -> void:
	var soc := _store.social(account).duplicate(true)
	var fr: Dictionary = soc.get("friends", {})
	fr[friend] = {"name": name}
	soc["friends"] = fr
	_store.set_social(account, soc)


func _on_unfriend(id: int, other: String) -> void:
	if _store == null or not _peers.has(id) or String(_peers[id].get("account", "")) == "":
		return
	var me := String(_peers[id].account)
	for pair in [[me, other], [other, me]]:
		var soc := _store.social(pair[0]).duplicate(true)
		if soc.get("friends", {}).erase(pair[1]):
			_store.set_social(pair[0], soc)
	_push_friends(id)
	if _online_accounts.has(other):
		_push_friends(int(_online_accounts[other]))


## Sends `id` its friends (if the list changed since last time): who is online, where, their peer id.
func _push_friends(id: int) -> void:
	if _store == null or not _peers.has(id) or String(_peers[id].get("account", "")) == "":
		return
	var list: Array = []
	var fr: Dictionary = _store.social(String(_peers[id].account)).get("friends", {})
	for acc in fr:
		var pid: int = int(_online_accounts.get(acc, 0))
		var on := pid != 0 and _peers.has(pid)
		var name := String(_peers[pid].info.name) if on else String(fr[acc].get("name", "?"))
		if on and name != "?" and name != String(fr[acc].get("name", "")):
			_befriend(String(_peers[id].account), acc, name)  # they play another character now
		list.append({"account": acc, "name": name, "online": on, "id": pid if on else 0,
			"where": String(_peers[pid].state.get("w", "")) if on else ""})
	list.sort_custom(func(x, y): return x.online and not y.online or (x.online == y.online and String(x.name) < String(y.name)))
	var key := JSON.stringify(list)
	if _friends_sent.get(id, "") == key:
		return
	_friends_sent[id] = key
	_send(id, "_rpc_friends", [list])


# ---------- trading: the server ----------

## `data` (a save file) without the items this account traded away (its "gone" ids).
func _strip_gone(account: String, data: Dictionary) -> Dictionary:
	var gone: Dictionary = _store.social(account).get("gone", {})
	if gone.is_empty():
		return data
	var keep := func(d) -> bool: return not (d is Dictionary and gone.has(String(d.get("uid", ""))))
	for key in ["inventory", "stash"]:
		if data.get(key) is Array:
			data[key] = data[key].filter(func(e): return keep.call(e.get("item") if e is Dictionary and e.has("item") else e))
	if data.get("stash_overflow") is Array:
		data["stash_overflow"] = data.stash_overflow.filter(keep)
	if data.get("equipment") is Dictionary:
		for slot in data.equipment.keys():
			if not keep.call(data.equipment[slot]):
				data.equipment.erase(slot)
	return data


## The character `id` is playing, as the server has it saved ({} if none).
func _saved_character(id: int) -> Dictionary:
	var files := _store.files(String(_peers[id].account))
	var last := String(files.get("account", {}).get("last", ""))
	var c = files.get("characters/" + last, {})
	return c if c is Dictionary else {}


## The items with these ids in `id`'s saved bag (only those it really has), as saved.
func _bag_items(id: int, uids: Array) -> Array:
	var out: Array = []
	for e in _saved_character(id).get("inventory", []):
		var d = e.get("item") if e is Dictionary else null
		if d is Dictionary and String(d.get("uid", "")) in uids and out.size() < TRADE_MAX_ITEMS:
			out.append(d)
	return out


func _on_trade_request(from: int, target: int) -> void:
	if _store == null or not _can_see(from, target) or from == target:
		return
	if _trade_of.has(from) or _trade_of.has(target):
		_send(from, "_rpc_notice", ["One of you is trading already."])
		return
	if not _trade_asks.has(target):
		_trade_asks[target] = {}
	_trade_asks[target][from] = Time.get_ticks_msec()
	_send(target, "_rpc_trade_ask", [from, String(_peers[from].info.name)])
	_send(from, "_rpc_notice", ["Asked %s to trade." % _peers[target].info.name])


func _on_trade_answer(target: int, from: int, accept: bool) -> void:
	var asked: Dictionary = _trade_asks.get(target, {})
	if not asked.has(from) or not _peers.has(from) or not _peers.has(target):
		return
	asked.erase(from)
	if not accept:
		_send(from, "_rpc_notice", ["%s doesn't want to trade." % _peers[target].info.name])
		return
	if _trade_of.has(from) or _trade_of.has(target):
		return
	var tid := _next_trade
	_next_trade += 1
	_trades[tid] = {"p": [from, target], "offer": {from: [], target: []}, "ready": {from: false, target: false}}
	_trade_of[from] = tid
	_trade_of[target] = tid
	_tell_trade(tid)


func _on_trade_offer(id: int, uids: Array) -> void:
	if not _trade_of.has(id):
		return
	var t: Dictionary = _trades[_trade_of[id]]
	t.offer[id] = _bag_items(id, uids.map(func(u): return String(u)))
	for p in t.p:
		t.ready[p] = false  # anything changed: both look again
	_tell_trade(_trade_of[id])


func _on_trade_ready(id: int, on: bool) -> void:
	if not _trade_of.has(id):
		return
	var tid: int = _trade_of[id]
	var t: Dictionary = _trades[tid]
	t.ready[id] = on
	if t.ready.values().all(func(r): return r):
		_complete_trade(tid)
	else:
		_tell_trade(tid)


func _on_trade_cancel(id: int) -> void:
	if _peers.has(id):
		_end_trade(id, "%s cancelled the trade." % _peers[id].info.name)


## Closes `id`'s trade (if any), telling both why.
func _end_trade(id: int, why: String) -> void:
	if not _trade_of.has(id):
		return
	var tid: int = _trade_of[id]
	for p in _trades[tid].p:
		_trade_of.erase(p)
		_send(p, "_rpc_trade_state", [{}])
		_send(p, "_rpc_notice", [why])
	_trades.erase(tid)


func _tell_trade(tid: int) -> void:
	var t: Dictionary = _trades[tid]
	for p in t.p:
		var o: int = t.p[1] if p == t.p[0] else t.p[0]
		_send(p, "_rpc_trade_state", [{"with": o, "name": String(_peers[o].info.name), "mine": t.offer[p],
			"theirs": t.offer[o], "ready_me": t.ready[p], "ready_them": t.ready[o]}])


## Both are ready: check the offers against the saved bags once more, then swap them in the saves and
## tell both games.
func _complete_trade(tid: int) -> void:
	var t: Dictionary = _trades[tid]
	var a: int = t.p[0]
	var b: int = t.p[1]
	for p in t.p:
		var uids: Array = t.offer[p].map(func(d): return String(d.uid))
		if _bag_items(p, uids).size() != uids.size():
			_end_trade(p, "The trade was called off: an item is no longer in %s's bag." % _peers[p].info.name)
			return
	for pair in [[a, b], [b, a]]:
		var giver: int = pair[0]
		var taker: int = pair[1]
		var given: Array = t.offer[giver]
		var uids: Array = given.map(func(d): return String(d.uid))
		# Out of the giver's saved bag, and kept out of its saves from now on
		var gacc := String(_peers[giver].account)
		var files := _store.files(gacc)
		var last := String(files.get("account", {}).get("last", ""))
		var ch: Dictionary = files.get("characters/" + last, {}).duplicate(true)
		ch["inventory"] = ch.get("inventory", []).filter(func(e): return not (e is Dictionary and e.get("item") is Dictionary and String(e.item.get("uid", "")) in uids))
		_store.put(gacc, "characters/" + last, ch)
		var soc := _store.social(gacc).duplicate(true)
		var gone: Dictionary = soc.get("gone", {})
		for u in uids:
			gone[u] = true
		while gone.size() > GONE_KEEP:
			gone.erase(gone.keys()[0])
		soc["gone"] = gone
		_store.set_social(gacc, soc)
		# Into the taker's saved stash (where its game puts them too), and no longer "gone" for it
		var tacc := String(_peers[taker].account)
		var acc: Dictionary = _store.files(tacc).get("account", {}).duplicate(true)
		acc["stash_overflow"] = acc.get("stash_overflow", []) + given
		_store.put(tacc, "account", acc)
		var tsoc := _store.social(tacc).duplicate(true)
		for u in uids:
			tsoc.get("gone", {}).erase(u)
		_store.set_social(tacc, tsoc)
	for p in t.p:
		var o: int = b if p == a else a
		_trade_of.erase(p)
		_send(p, "_rpc_trade_done", [t.offer[p].map(func(d): return String(d.uid)), t.offer[o]])
		_send(p, "_rpc_trade_state", [{}])
	_trades.erase(tid)
	if mode == Mode.SERVER:
		print("Net: trade between %s and %s" % [_peers[a].info.name, _peers[b].info.name])


## Whether `who` may see `id` (to inspect them): in the same instance, or in the same party.
func _can_see(who: int, id: int) -> bool:
	if not _peers.has(who) or not _peers.has(id):
		return false
	var inst: String = _peers[who].instance
	var friend: bool = _store != null and String(_peers[who].get("account", "")) != "" and \
		_store.social(String(_peers[who].account)).get("friends", {}).has(String(_peers[id].get("account", "")))
	return (inst != "" and inst == _peers[id].instance) or friend or \
		(_peers[who].party != 0 and _peers[who].party == _peers[id].party)


func _on_inspect(who: int, id: int) -> void:
	if not _can_see(who, id):
		_send(who, "_rpc_notice", ["You can't see them from here."])
		return
	if id == 1 and mode == Mode.HOST:
		_send(who, "_rpc_inspect_of", [1, _inspect_data()])
	else:
		_send(id, "_rpc_inspect_ask", [who])


func _on_inspect_reply(id: int, who: int, data: Dictionary) -> void:
	if _can_see(who, id) and JSON.stringify(data).length() < 128 * 1024:
		_send(who, "_rpc_inspect_of", [id, data])


func _on_account_files(id: int) -> void:
	if _store != null and _peers.has(id) and String(_peers[id].get("account", "")) != "":
		_send(id, "_rpc_account", [_store.files(String(_peers[id].account))])


func _on_save_file(id: int, vpath: String, data: Variant) -> void:
	if _store == null or not _peers.has(id) or String(_peers[id].get("account", "")) == "":
		return
	if data is Dictionary:
		data = _strip_gone(String(_peers[id].account), data)
	var why := _store.put(String(_peers[id].account), vpath, data)
	if why != "":
		push_warning("Net: refused %s's %s: %s" % [_peers[id].info.name, vpath, why])


func _on_delete_file(id: int, vpath: String) -> void:
	if _store != null and _peers.has(id) and String(_peers[id].get("account", "")) != "":
		_store.remove(String(_peers[id].account), vpath)


## Which copy of the town `id` goes into: one a party member is in if it has room, else the first
## with room, else a new one.
func _town_copy(id: int) -> String:
	var counts := {}
	for p in _peers:
		var i: String = _peers[p].instance
		if p != id and (i == TOWN or i.begins_with(TOWN + "~")):
			counts[i] = int(counts.get(i, 0)) + 1
	var pid: int = _peers[id].party
	if pid != 0 and _parties.has(pid):
		for m in _parties[pid].members:
			var i: String = _peers[m].instance if _peers.has(m) else ""
			if m != id and counts.has(i) and int(counts[i]) < town_cap:
				return i
	var n := 1
	while true:
		var name := TOWN if n == 1 else "%s~%d" % [TOWN, n]
		if int(counts.get(name, 0)) < town_cap:
			return name
		n += 1
	return TOWN


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


## Open a rift of `level` for your party: everyone in it is asked to join (party_portal), you go in.
func open_party_rift(level: int) -> void:
	_to_server("_on_open_instance", "_rpc_open_instance", ["rift", level])


## Go into a party instance (a party_portal): loads its scene. From anywhere but the tutorial.
func join_portal(portal: Dictionary) -> void:
	if portal.is_empty() or not in_party():
		return
	coop = portal.duplicate()
	GameState.save()
	get_tree().paused = false
	match String(portal.kind):
		"rift":
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


## Sends an instance event: to 0 = everyone else in your instance, -1 = its host, or a player's id.
func send_event(to: int, kind: String, data: Variant) -> void:
	if not online() or instance == "":
		return
	_to_server("_on_event", "_rpc_event", [to, kind, data])


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


func _on_open_instance(id: int, kind: String, level: int) -> void:
	if not _peers.has(id) or _peers[id].party == 0 or kind != "rift":
		return
	var pid: int = _peers[id].party
	var portal := {"inst": "%s:%d:%d" % [kind, pid, _next_inst], "kind": kind, "level": clampi(level, 1, 999),
		"by": id, "by_name": String(_peers[id].info.name)}
	_next_inst += 1
	_parties[pid].portal = portal
	_tell_party(pid)
	for m in _parties[pid].members:
		_send(m, "_rpc_portal", [portal])


## Someone left instance `inst`: if they hosted it the next player there takes over; an empty party
## instance closes (its portal with it).
func _instance_left(inst: String, id: int) -> void:
	if not _instances.has(inst):
		return
	var left := _peers.keys().filter(func(p): return _peers[p].instance == inst)
	if left.is_empty():
		_instances.erase(inst)
		var pid := party_of_instance(inst)
		if _parties.has(pid) and _parties[pid].get("portal", {}).get("inst", "") == inst:
			_parties[pid].portal = {}
			_tell_party(pid)
		return
	if int(_instances[inst].host) == id:
		_instances[inst].host = left[0]
		for p in left:
			_send(p, "_rpc_role", [int(left[0])])


func _on_event(from: int, to: int, kind: String, data: Variant) -> void:
	if not _peers.has(from):
		return
	var inst: String = _peers[from].instance
	if inst == "":
		return
	if to == -1:
		to = int(_instances.get(inst, {}).get("host", 0))
	if to > 0:
		if _peers.has(to) and _peers[to].instance == inst and to != from:
			_send(to, "_rpc_event_of", [from, kind.left(24), data])
		return
	for p in _peers:
		if p != from and _peers[p].instance == inst:
			_send(p, "_rpc_event_of", [from, kind.left(24), data])


func _within_event_rate(id: int) -> bool:
	var sec := Time.get_ticks_msec() / 1000
	var r: Array = _event_rate.get(id, [sec, 0])
	if r[0] != sec:
		r = [sec, 0]
	r[1] += 1
	_event_rate[id] = r
	return r[1] <= MAX_EVENTS_PER_SEC


## Takes `id` out of its party: the lead passes on if it led, and a party of one disbands. `away`: it
## lost its connection, so its place is kept for AWAY_GRACE (coming back with its token restores it).
func _remove_from_party(id: int, why: String, away := false) -> void:
	var pid: int = _peers[id].party if _peers.has(id) else 0
	if pid == 0 or not _parties.has(pid):
		return
	var p: Dictionary = _parties[pid]
	p.members.erase(id)
	_peers[id].party = 0
	if not p.has("away"):
		p.away = {}
	if away and String(_peers[id].get("token", "")) != "":
		var info: Dictionary = _peers[id].info
		p.away[String(_peers[id].token)] = {"name": info.name, "level": info.level, "class": info["class"],
			"until": Time.get_ticks_msec() + int(AWAY_GRACE * 1000.0)}
	else:
		_send(id, "_rpc_party", [{}])
	_settle_party(pid, why)


## After someone left party `pid`: it disbands if one player is left with nobody away, it closes if
## nobody is left at all, else the lead passes to someone there and the members are told.
func _settle_party(pid: int, why: String) -> void:
	var p: Dictionary = _parties[pid]
	var away: Dictionary = p.get("away", {})
	if p.members.is_empty():
		if away.is_empty():
			_parties.erase(pid)
		return
	if p.members.size() == 1 and away.is_empty():
		var m: int = p.members[0]
		_peers[m].party = 0
		_send(m, "_rpc_party", [{}])
		_send(m, "_rpc_notice", [why + " The party disbanded."])
		_parties.erase(pid)
		return
	if not p.members.has(p.leader):
		p.leader = p.members[0]
	_tell_party(pid, why)


## `id` said hello with `token`: if a party kept its place while it was away, it's back in.
func _restore_away(id: int, token: String) -> void:
	if token == "":
		return
	for pid in _parties:
		var away: Dictionary = _parties[pid].get("away", {})
		if away.has(token):
			away.erase(token)
			_parties[pid].members.append(id)
			_peers[id].party = pid
			if not _parties[pid].members.has(_parties[pid].leader):
				_parties[pid].leader = id
			_tell_party(pid, "%s is back." % _peers[id].info.name)
			return


## Sends party `pid`'s members and leader to each member, with `why` as a notice.
func _tell_party(pid: int, why := "") -> void:
	if not _parties.has(pid):
		return
	var p: Dictionary = _parties[pid]
	var members: Array = []
	for m in p.members:
		var info: Dictionary = _peers[m].info
		members.append({"id": m, "name": info.name, "level": info.level, "class": info["class"]})
	var away: Array = []
	for t in p.get("away", {}):
		var a: Dictionary = p.away[t]
		away.append({"name": a.name, "level": a.level, "class": a["class"]})
	var data := {"id": pid, "leader": p.leader, "members": members, "away": away, "portal": p.get("portal", {})}
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
	for pid in _parties.keys():  # places kept for players who dropped run out
		var away: Dictionary = _parties[pid].get("away", {})
		for t in away.keys():
			if now > int(away[t].until):
				var who: String = away[t].name
				away.erase(t)
				_settle_party(pid, "%s didn't come back." % who)
				if not _parties.has(pid):
					break
	for pid in _parties:
		var batch := {}
		for m in _parties[pid].members:
			var s: Dictionary = _peers[m].state
			batch[m] = {"h": s.get("h", 1.0), "w": s.get("w", "")}
		for m in _parties[pid].members:
			_send(m, "_rpc_vitals", [batch])


# ---------- RPCs: client -> server ----------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_request(target: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_trade_request(id, target)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_answer(from: int, accept: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_trade_answer(id, from, accept)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_offer(uids: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_trade_offer(id, uids)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_ready(on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_trade_ready(id, on)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade_cancel() -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_trade_cancel(id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_friend_request(target: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_friend_request(id, target)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_friend_answer(from: int, accept: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_friend_answer(id, from, accept)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_unfriend(account: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_unfriend(id, account.left(64))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_inspect(id: int) -> void:
	var who := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(who):
		_on_inspect(who, id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_inspect_reply(who: int, data: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_inspect_reply(id, who, data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat(channel: String, text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_chat(id, channel.left(16), text.left(CHAT_MAX * 2))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_account_files() -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_account_files(id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_save_file(vpath: String, data: Variant) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_save_file(id, vpath.left(64), data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_delete_file(vpath: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_delete_file(id, vpath.left(64))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_open_instance(kind: String, level: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_rate(id):
		_on_open_instance(id, kind, level)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_event(to: int, kind: String, data: Variant) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_server() and _within_event_rate(id):
		_on_event(id, to, kind, data)


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
func _rpc_welcome(name: String, _count: int, keeps_characters: bool) -> void:
	var back := mode == Mode.RECONNECTING
	accounts = keeps_characters
	if accounts and not back:
		_rpc_account_files.rpc_id(1)  # your characters on this server (_rpc_account)
	if back:
		for vpath in _pending_saves:  # what was saved while the connection was down
			if _pending_saves[vpath] == null:
				_rpc_delete_file.rpc_id(1, vpath)
			else:
				_rpc_save_file.rpc_id(1, vpath, _pending_saves[vpath])
		_pending_saves.clear()
	server_name = name
	_reconnect_url = _url
	_reconnect_tries = 0
	_set_status(Mode.CLIENT, ("Reconnected to %s" if back else "Online: %s") % name)
	if back:
		coop = _rejoin_coop
		var i := _rejoin
		_rejoin = ""
		_rejoin_coop = {}
		if i != "":
			instance = ""
			enter(i)  # back where you were
		update_looks()


@rpc("authority", "call_remote", "reliable")
func _rpc_trade_ask(from: int, from_name: String) -> void:
	trade_asked.emit(from, from_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_trade_state(state: Dictionary) -> void:
	trade_changed.emit(state)


## The trade went through: what you gave leaves your bag, what you got goes to your stash.
@rpc("authority", "call_remote", "reliable")
func _rpc_trade_done(gave: Array, got: Array) -> void:
	var p = GameState.player
	if is_instance_valid(p):
		for it in p.inventory.duplicate():
			if it != null and it.uid in gave:
				p.bag.remove(it)
		p.inventory_changed.emit()
	var items: Array[ItemInstance] = []
	for d in got:
		var it := ItemInstance.from_dict(d) if d is Dictionary else null
		if it != null:
			items.append(it)
	GameState.store_items(items)
	GameState.save()
	trade_finished.emit(items)


@rpc("authority", "call_remote", "reliable")
func _rpc_friends(list: Array) -> void:
	friends = list
	friends_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_friend_ask(from: int, from_name: String) -> void:
	friend_asked.emit(from, from_name)


## Someone wants to see your gear: answer with it.
@rpc("authority", "call_remote", "reliable")
func _rpc_inspect_ask(who: int) -> void:
	_rpc_inspect_reply.rpc_id(1, who, _inspect_data())


@rpc("authority", "call_remote", "reliable")
func _rpc_inspect_of(id: int, data: Dictionary) -> void:
	inspected.emit(id, data)


@rpc("authority", "call_remote", "reliable")
func _rpc_chat_of(from: int, from_name: String, channel: String, text: String) -> void:
	chat.emit(from, from_name, channel, text)


## Your characters on this server: the game plays from them now.
@rpc("authority", "call_remote", "reliable")
func _rpc_account(files: Dictionary) -> void:
	GameState.use_online_files(files)
	account_ready.emit()


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
func _rpc_portal(portal: Dictionary) -> void:
	party_portal.emit(portal)
	if int(portal.get("by", 0)) == my_id():
		join_portal(portal)  # you opened it: in you go


@rpc("authority", "call_remote", "reliable")
func _rpc_role(host_id: int) -> void:
	instance_host = host_id
	role_changed.emit(host_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_event_of(from: int, kind: String, data: Variant) -> void:
	event.emit(from, kind, data)


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
