extends Node2D
## The chat box open: its history (scrolls back through the last 100 lines) with local, party,
## server lines and whispers, the channel set to whisper back. No server: made-up lines. Saved to
## scratch/chat_history.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_chat.tscn


func _ready() -> void:
	GameState.char_name = "Brom"
	add_child(load("res://scenes/town.tscn").instantiate())
	await get_tree().create_timer(1.0).timeout
	var c: ChatUI = Net.chat_ui
	var lines := [[3, "Kael", "local", "anyone up for a rift?"], [4, "Mira", "local", "me! level 4 ok?"],
		[0, "Server", "server", "The server restarts tonight at 2am."], [3, "Kael", "party", "portal's up, come in"],
		[5, "Tobin", "local", "selling a rare axe, 10 alchemy"], [6, "Sera", "whisper", "is the axe still for sale?"],
		[6, "Sera", "whisper_to", "yes, come to the waypoint"], [4, "Mira", "party", "boss down, nice"]]
	for i in 14:
		lines.push_front([7, "Ulric", "local", "older line %d" % (14 - i)])
	for l in lines:
		c._on_chat(l[0], l[1], l[2], l[3])
	c.set_process(false)  # (it hides itself offline; this capture isn't online)
	c._layer.visible = true
	c._set_open(true)
	c._set_channel("whisper")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/chat_history.png"))
	print("saved chat_history")
	get_tree().quit()
