extends Node
## TestBot: a player on the Tainted World for trying multiplayer on your own (on the main host it's
## the tainted-bot container). It comes in with the server's bot key (--bot-key: the server's
## TAINTED_BOT_KEY) instead of a sign-in, plays a warrior with a hireling, stands about Ashfall, and:
##   - accepts party invites, trades and friend requests;
##   - in a party stays with you: into party rifts and zones, fighting beside you with its skills,
##     standing by you when you fall (which revives you), getting up by itself if nobody revives it;
##   - in a trade offers an item and some orbs, and is ready once you are (restocked after);
##   - answers whispers: help, invite, trade, friend, follow, stay, rift, die, leave, say <text>.
##   godot --headless --path . res://scenes/test_bot.tscn -- --addr=ws://host:24601 --bot-key=... [--name=TestBot]
## If the server goes (a redeploy) it comes back by itself. (A copy runs at the root: scenes change.)

const HELP := "I'm a test bot. Whisper me: invite, trade, friend, follow, stay, rift (opens one for our party), " + \
	"die (in a rift or zone: then stand by me to revive me), leave (the party), say <text>."
const STOCK_ITEMS := 3  ## items it keeps in its bag to trade
const STOCK_ORBS := {"transmute": 20, "alteration": 10, "alchemy": 3}

var runner := false
var addr := "127.0.0.1"
var bot_name := "TestBot"
var _follow := 0  # town: the player it walks after (whisper follow); 0: about the spawn
var _home := Vector2.ZERO
var _think := 0.0
var _wander_t := 0.0
var _goto_t := 0.0
var _down_t := 0.0
var _alone_t := 0.0
var _offline_t := 0.0
var _starting := false
var _account_ok := false
var _offered := false
var _greet_t := {}  # player id -> msec it was last told to whisper help


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--addr="): addr = a.trim_prefix("--addr=")
		elif a.begins_with("--bot-key="): Net.bot_key = a.trim_prefix("--bot-key=")
		elif a.begins_with("--name="): bot_name = a.trim_prefix("--name=")
	GameState.char_name = bot_name
	Net.account_ready.connect(func(): _account_ok = true)
	Net.invited.connect(_on_invited)
	Net.party_portal.connect(_on_portal)
	Net.trade_asked.connect(func(from, _n): Net.answer_trade(from, true))
	Net.trade_changed.connect(_on_trade)
	Net.trade_finished.connect(func(_items, _orbs): _restock.call_deferred())
	Net.friend_asked.connect(func(from, _n): Net.answer_friend(from, true))
	Net.chat.connect(_on_chat)
	Net.status_changed.connect(func(): print("%s: %s" % [bot_name, Net.status]))
	_start()


## Joins, picks its character (makes it the first time), and goes to town.
func _start() -> void:
	if _starting:
		return
	_starting = true
	_account_ok = false
	Net.join(addr)
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	var t := 0.0
	while Net.online() and not _account_ok and t < 10.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	if not _account_ok:
		_starting = false  # tried again in a while (_process)
		return
	var id := ""
	for c in GameState.characters:
		if String(c.name) == bot_name:
			id = String(c.id)
	if id == "":
		id = GameState.create_character(bot_name, "warrior", Appearance.random_look())
	GameState.select_character(id)
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.give_starter_skills()
	if GameState.hireling.is_empty() or bool(GameState.hireling.get("dead", false)):
		var c := HirelingDB.roll_candidate("sellsword", maxi(GameState.level, 1))
		c["dead"] = false
		c["xp"] = 0.0
		c["attributes"] = {}
		GameState.hireling = c
		GameState.hireling_gear = {}
		GameState.hireling_flasks = [null, null]
	GameState.save()
	get_tree().change_scene_to_file("res://scenes/town.tscn")
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(GameState.player):
		_home = GameState.player.global_position
	_restock()
	_starting = false
	print("%s: in town" % bot_name)


## Keeps a few items in its bag and some orbs, for trading.
func _restock() -> void:
	var p = GameState.player
	if not is_instance_valid(p):
		return
	var n: int = p.inventory.filter(func(it): return it != null).size()
	for i in maxi(STOCK_ITEMS - n, 0):
		var rarity: int = [ItemInstance.Rarity.MAGIC, ItemInstance.Rarity.RARE].pick_random()
		p.bag.add(LootGenerator.roll_item(maxi(GameState.level, 1) + 3, rarity))
	for k in STOCK_ORBS:
		GameState.orbs[k] = maxi(GameState.orb_count(k), int(STOCK_ORBS[k]))
	GameState.save()


func _process(delta: float) -> void:
	if not runner:
		return
	if not Net.online() and Net.mode != Net.Mode.RECONNECTING and Net.mode != Net.Mode.CONNECTING and not _starting:
		_offline_t += delta
		if _offline_t > 10.0:  # the server went (a redeploy): back in once it's up
			_offline_t = 0.0
			_start()
		return
	_offline_t = 0.0
	_think -= delta
	if _think > 0.0 or _starting:
		return
	_think = 0.3
	var p = GameState.player
	var scene := get_tree().current_scene
	if not is_instance_valid(p) or scene == null:
		return
	var path := scene.scene_file_path
	if path.ends_with("town.tscn"):
		_town_step(p)
	elif path.ends_with("main.tscn") or path.ends_with("zone.tscn"):
		_fight_step(p, scene)


## The player it stays with: who it was told to follow, else a party member (its leader first).
func _buddy_id() -> int:
	if _follow != 0:
		return _follow
	if Net.in_party():
		var me := Net.my_id()
		if int(Net.party.leader) != me:
			return int(Net.party.leader)
		for m in Net.party.members:
			if int(m.id) != me:
				return int(m.id)
	return 0


func _buddy_node(id: int):
	for rp in get_tree().get_nodes_in_group("remote_players"):
		if rp.peer_id == id:
			return rp
	return null


func _town_step(p: Player) -> void:
	var id := _buddy_id()
	if id != 0 and Net.in_party() and Net.member_place(id) in ["rift", "zone"]:
		_goto_t -= 0.3
		if _goto_t <= 0.0:
			_goto_t = 8.0
			Net.go_to(id)  # they went into a rift or zone: after them
		return
	var b = _buddy_node(id) if id != 0 else null
	if b != null:
		if p.global_position.distance_to(b._target) > 130.0:
			p.walk_to(b._target + Vector2(70, 30), 60.0, _arrived)
		return
	_wander_t -= 0.3
	if _wander_t <= 0.0:
		_wander_t = randf_range(3.0, 7.0)
		p.walk_to(_home + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 200.0), 20.0, _arrived)


func _fight_step(p: Player, main: Node) -> void:
	if p.dead:
		_down_t += 0.3
		if _down_t > 30.0 and main.has_method("get_up"):  # nobody came: up again
			_down_t = 0.0
			main.get_up()
		return
	_down_t = 0.0
	var b = _buddy_node(_buddy_id())
	if b == null and get_tree().get_nodes_in_group("remote_players").size() > 0:
		b = get_tree().get_nodes_in_group("remote_players")[0]
	if b == null:
		_alone_t += 0.3
		if _alone_t > 6.0:  # everyone left: back to town
			_alone_t = 0.0
			if main.has_method("return_to_town"):
				main.return_to_town()
			else:
				ActDB.travel(get_tree(), ActDB.TOWN, "waypoint")
		return
	_alone_t = 0.0
	if b.dead:  # stand by them: that revives them (PartyDeath)
		p.walk_to(b._target + Vector2(25, 0), 20.0, _arrived)
		return
	var foe: Enemy = null
	var best := 420.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = e.global_position.distance_to(p.global_position)
		if not e._dead and d < best and e.global_position.distance_to(b._target) < 700.0:
			best = d
			foe = e
	if foe != null:
		if best > 90.0:
			p.walk_to(foe.global_position, 70.0, _arrived)
		else:
			p.facing = (foe.global_position - p.global_position).normalized()
			for i in p.skills.size():
				if p.skills[i] != null and (i == 0 or randf() < 0.3):
					p.use_skill(i)
		return
	var d: float = p.global_position.distance_to(b._target)
	if d > 900.0:
		p.global_position = b._target + Vector2(60, 0)  # far behind (they went through a portal): catch up
	elif d > 160.0:
		p.walk_to(b._target + Vector2(70, 30), 90.0, _arrived)


## (walk_to calls it on arriving: nothing to do)
func _arrived() -> void:
	pass


func _on_invited(from: int, _from_name: String) -> void:
	if Net.in_party():
		Net.whisper(from, "I'm in a party already. Whisper me 'leave' first.")
		return
	Net.answer_invite(from, true)
	await get_tree().create_timer(0.5).timeout
	Net.whisper(from, "Thanks for the invite! Whisper me 'help' to see what I can do.")


func _on_portal(portal: Dictionary) -> void:
	if int(portal.get("by", 0)) == Net.my_id() or not Net.in_party():
		return  # (its own: Net takes it in)
	await get_tree().create_timer(1.0).timeout
	print("%s: portal %s (in party %s, in %s)" % [bot_name, portal.get("inst", "?"), Net.in_party(), Net.instance])
	if Net.in_party() and Net.instance != String(portal.get("inst", "")):
		Net.join_portal(portal)


func _on_trade(state: Dictionary) -> void:
	if state.is_empty():
		_offered = false
		return
	var p = GameState.player
	if not _offered and is_instance_valid(p):
		_offered = true
		var items: Array = p.inventory.filter(func(it): return it != null)
		if not items.is_empty():
			Net.trade_offer([items.pick_random().to_dict().uid])
		Net.trade_orbs({"transmute": 5, "alteration": 2})
		return
	if bool(state.get("ready_them", false)) and not bool(state.get("ready_me", false)):
		Net.trade_ready(true)  # you're ready: so is it


func _on_chat(from: int, from_name: String, channel: String, text: String) -> void:
	if from == Net.my_id() or from == 0:
		return
	if channel == "whisper":
		_command(from, from_name, text)
	elif channel in ["local", "party"] and (bot_name.to_lower() in text.to_lower() or "bot" in text.to_lower()):
		if Time.get_ticks_msec() - int(_greet_t.get(from, -100000)) > 20000:
			_greet_t[from] = Time.get_ticks_msec()
			Net.say(channel, "Hi %s! Whisper me 'help' to see what I can do." % from_name)


func _command(from: int, from_name: String, text: String) -> void:
	var words := text.strip_edges().split(" ", false)
	var cmd := words[0].to_lower() if not words.is_empty() else "help"
	var p = GameState.player
	var scene := get_tree().current_scene
	var fighting: bool = scene != null and (scene.scene_file_path.ends_with("main.tscn") or scene.scene_file_path.ends_with("zone.tscn"))
	match cmd:
		"invite":
			if Net.is_member(from):
				Net.whisper(from, "We're in a party already.")
			elif Net.in_party() and not Net.is_leader():
				Net.whisper(from, "I'm in someone else's party. Whisper me 'leave' first.")
			else:
				Net.invite(from)
		"trade":
			Net.trade_with(from)
		"friend":
			Net.add_friend(from)
		"follow":
			_follow = from
			Net.whisper(from, "Following you, %s." % from_name)
		"stay":
			_follow = 0
			if is_instance_valid(p):
				_home = p.global_position
			Net.whisper(from, "Staying here.")
		"rift":
			if not Net.is_member(from):
				Net.whisper(from, "Invite me to your party first (or whisper me 'invite').")
			else:
				Net.whisper(from, "Opening a rift for our party: join it from the pop-up or the party list.")
				Net.open_party_rift(GameState.rift_unlocked)
		"die":
			if fighting and is_instance_valid(p) and not p.dead:
				Net.whisper(from, "Down I go! Stand by me for 3 seconds to revive me.")
				p.take_damage(1.0e7)
			else:
				Net.whisper(from, "Only in a rift or zone.")
		"leave":
			if Net.in_party():
				Net.leave_party()
				Net.whisper(from, "I've left the party.")
			else:
				Net.whisper(from, "I'm not in a party.")
		"say":
			var line := " ".join(words.slice(1))
			if line != "":
				Net.say("local", line)
		_:
			Net.whisper(from, HELP)
