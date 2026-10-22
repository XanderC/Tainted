extends Node
## Whispers and muting, with two bots on a server that keeps characters (--data):
##   godot --headless --path . res://scratch/chat_bot.tscn -- --role=a   (listens, mutes, unmutes)
##   godot --headless --path . res://scratch/chat_bot.tscn -- --role=b   (talks)
## B whispers to A; A mutes B; B's town line and whisper don't reach A (B still sees its whisper);
## A unmutes; B's next line does. B whispering to someone not online is told so.
## Prints "chat <role>: N checks, M failed".

var role := "a"
var _checks := 0
var _failed := 0
var _heard: Array = []  # [channel, from name, text]
var _notices: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
	Net.test_key = ("chat-bot-" + role).rpad(40, "0")
	GameState.char_name = "Chat" + role.to_upper()
	GameState.appearance = Appearance.random_look()
	Net.chat.connect(func(_f, n, ch, text): _heard.append([ch, n, text]))
	Net.notice.connect(func(t): _notices.append(t))
	Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	Net.enter(Net.TOWN)
	while Net.others.is_empty():
		await _wait(0.3)
	var other := int(Net.others.keys()[0])
	await _wait(1.0)
	if role == "b":
		Net.whisper(other, "psst")
		await _wait(5.0)
		Net.say("local", "hello")
		await _wait(0.8)
		Net.whisper(other, "psst2")
		await _wait(4.0)
		Net.say("local", "hello again")
		await _wait(1.0)
		_check(_heard.filter(func(h): return h[0] == "whisper_to" and h[1] == "ChatA").size() == 2,
			"it sees its whispers, as \"To ChatA\" (even while muted: it isn't told)")
		Net.whisper(987654, "anyone?")
		await _wait(1.0)
		_check(_notices.any(func(t): return "not online" in t), "whispering to someone not online says so")
	else:
		await _wait(2.0)
		_check(_heard.any(func(h): return h[0] == "whisper" and h[1] == "ChatB" and h[2] == "psst"), "a whisper comes, from ChatB")
		Net.mute_chat_of(other)
		await _wait(2.5)
		_check(Net.is_ignored(other), "muted: ChatB is in its muted list (%s)" % [Net.ignored])
		_heard.clear()
		await _wait(3.5)
		_check(not _heard.any(func(h): return h[1] == "ChatB"), "a muted player's line and whisper don't come (%s)" % [_heard])
		Net.unmute_chat(String(Net.ignored[0].account) if not Net.ignored.is_empty() else "")
		await _wait(4.0)
		_check(not Net.is_ignored(other) and _heard.any(func(h): return h[2] == "hello again"), "unmuted, their lines come again")
		await _wait(2.0)
	print("chat %s: %d checks, %d failed" % [role, _checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
