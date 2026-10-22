extends Node
## Tests online characters (a server started with --data=<dir>, Net.accounts):
##   --phase=create  joins, gets its (empty) account from the server, creates a character there, gives
##                   it a level and some orbs, saves, and leaves: nothing is written to the device.
##   --phase=check   (after a server restart) joins again and checks the character came back from the
##                   server as it was left, and that the server refuses a bad save.
## Uses this device's key (Net.device_key), so both phases are the same account.

var phase := "create"
var addr := "127.0.0.1"
var _checks := 0
var _failed := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.get_slice("=", 1)
		elif a.begins_with("--addr="):
			addr = a.get_slice("=", 1)
	Net.test_key = "test-account-bot-0000000000000000000000000000"  # not this device's own account
	var local_chars := GameState.characters.size()
	Net.join(addr)
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	_check(Net.online() and Net.accounts, "the server keeps characters")
	var t := 0.0
	while not GameState.online_saves and t < 10.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	_check(GameState.online_saves, "the account comes from the server")
	if phase == "create":
		for c in GameState.characters.duplicate():  # a clean start for the test
			GameState.delete_character(c.id)
		var id := GameState.create_character("Netbot", "warrior")
		_check(id != "", "a character is created on the server")
		GameState.select_character(id)
		GameState.level = 7
		GameState.orbs["chaos"] = 11
		GameState.save()
		GameState._save_account()
		await get_tree().create_timer(3.5).timeout  # the server writes a moment after a change
		Net.leave()
		_check(not GameState.online_saves and GameState.characters.size() == local_chars,
			"going offline brings back the device's characters (%d)" % GameState.characters.size())
	else:
		var names := GameState.characters.map(func(c): return c.name)
		_check(names == ["Netbot"], "the character came back from the server (%s)" % [names])
		if not GameState.characters.is_empty():
			GameState.select_character(GameState.characters[0].id)
			_check(GameState.level == 7, "its level is kept (%d)" % GameState.level)
			_check(int(GameState.orbs.get("chaos", 0)) == 11, "the account's orbs are kept (%d)" % int(GameState.orbs.get("chaos", 0)))
			# A save the server should refuse: an impossible level
			var bad := GameState._read_json(GameState._char_path(GameState.char_id))
			bad["level"] = 999
			Net._rpc_save_file.rpc_id(1, "characters/" + GameState.char_id, bad)
			Net._rpc_save_file.rpc_id(1, "../../etc/passwd", {"x": 1})
			await get_tree().create_timer(1.0).timeout
			Net._rpc_account_files.rpc_id(1)
			await Net.account_ready
			GameState.select_character(GameState.characters[0].id)
			_check(GameState.level == 7, "the server refused the impossible save (level %d)" % GameState.level)
		Net.leave()
	print("account %s: %d checks, %d failed" % [phase, _checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
