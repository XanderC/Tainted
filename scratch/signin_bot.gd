extends Node
## Tests Autharr sign-in (a server started with --data and --auth=<Autharr URL>):
##   godot --headless --path . res://scratch/signin_bot.tscn -- --auth=http://host:15180 --email=... --password=... [--phase=first|again]
## first: joining unsigned is refused; a wrong password is refused; signing in works and the server
##        lets it in, to its account. again: (later) the kept sign-in signs it in with no password.
## Its kept sign-in is its own file (Net.auth_file), deleted at the end of "again".

var _checks := 0
var _failed := 0


func _ready() -> void:
	var auth := ""
	var email := ""
	var password := ""
	var phase := "first"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auth="): auth = a.get_slice("=", 1)
		elif a.begins_with("--email="): email = a.get_slice("=", 1)
		elif a.begins_with("--password="): password = a.get_slice("=", 1)
		elif a.begins_with("--phase="): phase = a.get_slice("=", 1)
	Net.auth_url = auth
	Net.auth_file = "user://test_autharr.dat"
	Net.test_key = "signin-bot".rpad(40, "0")
	if phase == "first":
		if FileAccess.file_exists(Net.auth_file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Net.auth_file))
		Net.join("127.0.0.1")
		await _settle()
		_check(not Net.online() and "Sign in" in Net.status, "joining unsigned is refused (%s)" % Net.status)
		await Net.sign_in(email, password + "-wrong")
		_check(Net.signed_in_as == "" and Net.sign_in_error != "", "a wrong password is refused (%s)" % Net.sign_in_error)
		await Net.sign_in(email, password)
		_check(Net.signed_in_as != "", "signing in works (as %s)" % Net.signed_in_as)
	else:
		await Net.resume_sign_in()
		_check(Net.signed_in_as != "", "the kept sign-in signs in again with no password (as %s)" % Net.signed_in_as)
	Net.join("127.0.0.1")
	await _settle()
	_check(Net.online() and Net.accounts, "the server lets it in (%s)" % Net.status)
	var t := 0.0
	while not GameState.online_saves and t < 5.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	_check(GameState.online_saves, "its account comes from the server")
	if phase == "first":
		GameState.create_character("Signedin", "warrior")
		await get_tree().create_timer(3.0).timeout
	else:
		_check(GameState.characters.map(func(c): return c.name).has("Signedin"), "its character is there, kept for its Autharr account")
		Net.sign_out()
		_check(not FileAccess.file_exists(Net.auth_file), "signing out forgets the kept sign-in")
	Net.leave()
	print("signin %s: %d checks, %d failed" % [phase, _checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _settle() -> void:
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout  # a refusal comes just after the welcome would


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
