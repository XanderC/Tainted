extends Node
## Going to a friend in another copy of the town (Net.go_to_friend). Run with a server started with
## --data (the two accounts already friends) and --town-cap=3, the friend "FriendA" and two walkers in
## town first (so this lands in the second copy), one walker leaving after a while:
##   godot --headless --path . res://scratch/friend_bot.tscn -- --key=friend-b
## Prints "friend: N checks, M failed". (A copy runs at the root: the scene is replaced.)

var runner := false
var _checks := 0
var _failed := 0


func _ready() -> void:
	if not runner:
		var r = load(get_script().resource_path).new()
		r.runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--key="):
			Net.test_key = a.get_slice("=", 1).rpad(40, "0")
	Net.join("127.0.0.1")
	await Net.account_ready
	GameState.select_character(GameState.create_character("FriendB", "warrior"))
	get_tree().change_scene_to_file("res://scenes/town.tscn")
	var t := 0.0
	var friend: Dictionary = {}
	while t < 30.0 and friend.is_empty():
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		var f: Array = Net.friends.filter(func(x): return x.name == "FriendA" and x.online and x.get("in_town", false))
		friend = f[0] if not f.is_empty() else {}
	_check(not friend.is_empty(), "its friend FriendA shows in town")
	var fid := int(friend.get("id", 0))
	_check(not Net.others.has(fid), "but in another copy of the town (it sees %d others)" % Net.others.size())
	# A walker in the friend's copy leaves 25 s after it came (the runner's --secs): room there then
	while Time.get_ticks_msec() < 30000:
		await get_tree().create_timer(0.5).timeout
	_check(Net.go_to_friend(fid), "Go to: its friend's copy of the town")
	t = 0.0
	while Net.go_to_peer != 0 and t < 10.0:  # until NetPresence has put it beside them (they keep walking after)
		await get_tree().process_frame
		t += get_process_delta_time()
	var rp = get_tree().get_nodes_in_group("remote_players").filter(func(r): return r.peer_id == fid)
	_check(Net.others.has(fid) and not rp.is_empty(), "it's in its friend's copy now")
	var d: float = GameState.player.global_position.distance_to(rp[0]._target) if not rp.is_empty() else INF
	_check(d < 120.0, "beside them (%d away)" % int(d))
	print("friend: %d checks, %d failed" % [_checks, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
