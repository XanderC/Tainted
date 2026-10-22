extends Node2D
## Two bots trade on a server that keeps characters (--data):
##   godot --headless --path . res://scratch/trade_bot.tscn -- --role=a     (asks)
##   godot --headless --path . res://scratch/trade_bot.tscn -- --role=b     (accepts)
## Each makes a character with one named item in its bag and offers it; both get Ready; the trade goes
## through. Each checks its item left its bag and the other's is in its stash. Then "a" cheats: it puts
## the item it gave back in its bag and saves, and checks the server kept it out of its saved bag.
## Prints "trade <role>: N checks, M failed".

var role := "a"
var _checks := 0
var _failed := 0
var _offered := false
var _readied := false
var _done := false
var _got: Array = []
var _mine: ItemInstance


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
	Net.test_key = ("trade-bot-" + role).rpad(40, "0")
	Net.join("127.0.0.1")
	await Net.account_ready
	for c in GameState.characters.duplicate():
		GameState.delete_character(c.id)
	GameState.select_character(GameState.create_character("Trader" + role.to_upper(), "warrior"))
	add_child(load("res://scenes/town.tscn").instantiate())  # a player, and into town
	await get_tree().create_timer(1.0).timeout
	_mine = LootGenerator.roll_item(10, ItemInstance.Rarity.RARE, "weapon")
	_mine.display_name = "Blade of " + role.to_upper()
	GameState.player.bag.add(_mine)
	GameState.save()
	Net.trade_asked.connect(func(from_id, _n):
		if role == "b":
			Net.answer_trade(from_id, true))
	Net.trade_changed.connect(_on_trade)
	Net.trade_finished.connect(func(items):
		_done = true
		_got = items)
	if role == "a":
		while Net.others.is_empty():
			await get_tree().create_timer(0.3).timeout
		await get_tree().create_timer(1.0).timeout
		Net.trade_with(Net.others.keys()[0])
	var t := 0.0
	while not _done and t < 20.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_check(_done, "the trade went through")
	var p: Player = GameState.player
	_check(not p.inventory.has(_mine), "my item left my bag")
	var theirs := "Blade of " + ("B" if role == "a" else "A")
	var in_stash: Array = GameState.stash.items().filter(func(it): return it.display_name == theirs) + \
		GameState.stash_overflow.filter(func(it): return it.display_name == theirs)
	_check(_got.size() == 1 and not in_stash.is_empty(), "their item is in my stash (%d got)" % _got.size())
	if role == "a":
		# Cheat: put back the item I gave away and save; the server must keep it out of my saved bag
		var copy := ItemInstance.from_dict(_mine.to_dict())
		p.bag.add(copy)
		GameState.save()
		await get_tree().create_timer(1.0).timeout
		Net._rpc_account_files.rpc_id(1)
		await Net.account_ready
		var saved := GameState._read_json(GameState._char_path(GameState.last_character))
		var names: Array = saved.get("inventory", []).map(func(e): return String(e.item.get("name", "")))
		_check(not ("Blade of A" in names), "the server kept the traded-away item out of my save (%s)" % [names])
	else:
		await get_tree().create_timer(3.0).timeout
	print("trade %s: %d checks, %d failed" % [role, _checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _on_trade(state: Dictionary) -> void:
	if state.is_empty():
		return
	if not _offered:
		_offered = true
		Net.trade_offer([_mine.uid])
		return
	if not state.get("mine", []).is_empty() and not state.get("theirs", []).is_empty() and not state.get("ready_me", false) and not _readied:
		_readied = true
		if "--shot" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/net_trade.png"))
			print("saved net_trade")
		Net.trade_ready(true)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
