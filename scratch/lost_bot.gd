extends Node
## The game is online only: a game that loses the server for good goes back to the start screen,
## which says why. Run with a local server, which the test kills once this is in town:
##   godot --headless --path . res://scratch/lost_bot.tscn
## Prints "lost: N checks, M failed". (A copy of it runs at the root: the scene is replaced.)

var runner := false
var _checks := 0
var _failed := 0


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	Net.status_changed.connect(func(): print("lost: status: ", Net.status))
	GameState.char_name = "Lost"
	GameState.appearance = Appearance.random_look()
	Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	_check(Net.online(), "it joins (%s)" % Net.status)
	get_tree().change_scene_to_file("res://scenes/town.tscn")
	await get_tree().create_timer(2.0).timeout
	print("lost: in town, waiting for the server to go")  # the test kills it now
	var t := 0.0
	while t < 150.0 and not get_tree().current_scene is CharacterSelect:  # it tries to reconnect a while first
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	var cs = get_tree().current_scene
	_check(cs is CharacterSelect, "losing the server for good takes it back to the start screen (%.0f s)" % t)
	await get_tree().create_timer(1.0).timeout
	_check(cs is CharacterSelect and is_instance_valid(cs._net_status) and "Lost the connection" in cs._net_status.text,
		"which says why (%s)" % (cs._net_status.text if cs is CharacterSelect and is_instance_valid(cs._net_status) else "?"))
	_check(GameState.characters.is_empty() and GameState.online_saves, "with no characters until an account comes (none from the device)")
	print("lost: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
