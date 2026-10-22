extends Node
## Tests a dedicated server's admin commands (ServerAdmin) from a player's side. Run with a local
## server started with --data=<d> --admin=<a>:
##   godot --headless --path . res://scratch/admin_bot.tscn -- --admin=<a> [--data=<d>]
## It joins as "Vic" and has the server: list it, mute and unmute it, announce, kick it, ban it (and
## refuse it again on rejoining), unban it, save, and shut down. Prints "admin: N checks, M failed".

var admin := ""
var data := ""
var _checks := 0
var _failed := 0
var _notices: Array = []
var _lines: Array = []  # [channel, text]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--admin="): admin = a.trim_prefix("--admin=")
		elif a.begins_with("--data="): data = a.trim_prefix("--data=")
	Net.test_key = "admin-bot".rpad(40, "0")
	GameState.char_name = "Vic"
	GameState.appearance = Appearance.random_look()
	Net.notice.connect(func(t): _notices.append(t))
	Net.chat.connect(func(_f, _n, ch, text): _lines.append([ch, text]))
	await _join()
	_check(Net.online(), "it joins (%s)" % Net.status)

	var s := await _cmd("status")
	_check("Vic" in s and "1 / " in s, "status lists it")

	await _cmd("mute vic 5")
	_notices.clear()
	_lines.clear()
	Net.say("local", "hello there")
	await _wait(1.0)
	_check(_notices.any(func(t): return "muted" in t), "a muted player is told so")
	_check(_lines.is_empty(), "and its line goes nowhere")
	_check("Vic" in await _cmd("mutes"), "mutes lists it")
	await _cmd("unmute Vic")
	await _wait(0.8)
	Net.say("local", "hello again")
	await _wait(1.0)
	_check(_lines.any(func(l): return l[1] == "hello again"), "unmuted, its line comes through")

	_lines.clear()
	await _cmd("say The server is being tested")
	await _wait(1.0)
	_check(_lines.any(func(l): return l[0] == "server" and "tested" in l[1]), "say: a server line in its chat")

	_check("Kicked Vic" in await _cmd("kick Vic testing"), "kick answers")
	await _wait(2.0)
	_check(not Net.online() and "removed" in Net.status and "testing" in Net.status, "kicked: it's told why (%s)" % Net.status)
	await _join()
	_check(Net.online(), "a kicked player can come back")

	_check("Banned Vic" in await _cmd("ban Vic cheating"), "ban answers")
	await _wait(2.0)
	_check(not Net.online() and "banned" in Net.status and "cheating" in Net.status, "banned: sent away and told why (%s)" % Net.status)
	await _join()
	_check(not Net.online() and "banned" in Net.status, "a banned account is refused when it comes back (%s)" % Net.status)
	_check("Vic" in await _cmd("bans"), "bans lists it")
	if data != "":
		_check(FileAccess.file_exists(data.path_join("moderation.json")), "bans are kept on disk")
	_check("Unbanned" in await _cmd("unban vic"), "unban answers")
	await _join()
	_check(Net.online(), "unbanned, it can come back")

	_check("written" in await _cmd("save"), "save answers")
	if data != "":
		_check(DirAccess.get_files_at(data.path_join("accounts")).size() > 0, "its account is on disk")

	await _cmd("shutdown 1")
	await _wait(2.5)
	_check(_notices.any(func(t): return "restarts" in t), "shutdown: everyone is told first")
	_check(Net.mode == Net.Mode.RECONNECTING or not Net.online(), "the server has gone (%s)" % Net.status)
	print("admin: %d checks, %d failed" % [_checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _join() -> void:
	Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	await _wait(1.5)  # a refusal comes just after


## Runs an admin command (as tainted-admin does) and returns its answer.
func _cmd(line: String) -> String:
	var id := "t%d" % Time.get_ticks_usec()
	var f := FileAccess.open(admin.path_join(id + ".tmp"), FileAccess.WRITE)
	f.store_string(line)
	f.close()
	DirAccess.rename_absolute(admin.path_join(id + ".tmp"), admin.path_join(id + ".cmd"))
	var out := admin.path_join(id + ".out")
	for i in 50:
		if FileAccess.file_exists(out):
			var answer := FileAccess.get_file_as_string(out)
			DirAccess.remove_absolute(out)
			print("> %s\n%s" % [line, answer.strip_edges()])
			return answer
		await _wait(0.1)
	return "(no answer)"


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
