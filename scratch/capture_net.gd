extends Node2D
## Screenshot of the town online (scratch/net_town.png): joins the server at 127.0.0.1, enters town
## and waits for the other players (run a server and a walker bot first, see net_bot.gd).
##   godot --path . --resolution 1600x720 res://scratch/capture_net.tscn


func _ready() -> void:
	GameState.char_name = "Wanderer"
	if "--select" in OS.get_cmdline_user_args():
		# The online screen on character select, with the servers it finds
		var cs = load("res://scenes/character_select.tscn").instantiate()
		add_child(cs)
		await get_tree().process_frame
		if not cs._selected.is_empty():
			cs._online = true
			cs._refresh()
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/net_select.png"))
		print("saved net_select")
		get_tree().quit()
		return
	if "--host" in OS.get_cmdline_user_args():
		Net.host()  # this game is the server; bots join it
	else:
		Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	print("capture: ", Net.status)
	add_child(load("res://scenes/town.tscn").instantiate())
	await get_tree().create_timer(9.0 if Net.mode == Net.Mode.HOST else 4.0).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/net_town.png"))
	print("saved net_town, others: ", Net.others.size())
	Net.leave()
	get_tree().quit()
