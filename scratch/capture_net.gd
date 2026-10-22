extends Node2D
## Screenshot of the town online (scratch/net_town.png): joins the server at 127.0.0.1, enters town
## and waits for the other players (run a server and a walker bot first, see net_bot.gd).
##   godot --path . --resolution 1600x720 res://scratch/capture_net.tscn


func _ready() -> void:
	GameState.char_name = "Wanderer"
	if "--select" in OS.get_cmdline_user_args():
		# The start screen as it comes up: signing in and joining the Tainted World
		var layer := CanvasLayer.new()  # (so the screen fills the window, as when it's the scene)
		add_child(layer)
		layer.add_child(load("res://scenes/character_select.tscn").instantiate())
		await get_tree().create_timer(4.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/net_select.png"))
		print("saved net_select")
		get_tree().quit()
		return
	if "--world" in OS.get_cmdline_user_args():
		Net.join_world()  # the Tainted World, as the online screen's Join does
	else:
		Net.join("127.0.0.1")
	while Net.mode == Net.Mode.CONNECTING:
		await get_tree().process_frame
	print("capture: ", Net.status)
	add_child(load("res://scenes/town.tscn").instantiate())
	await get_tree().create_timer(4.0).timeout
	if "--inspect" in OS.get_cmdline_user_args():
		# Wear some gear (a bot inspects it), then inspect yourself for a screenshot of the window
		var p: Player = GameState.player
		for spec in [["broad_sword", "weapon"], ["brigandine", "chest"], ["iron_helm", "helmet"], ["iron_gauntlets", "gloves"]]:
			var it := LootGenerator.roll_item(14, ItemInstance.Rarity.RARE, "")
			it.base = LootGenerator.base_by_id(spec[0])
			it.display_name = it.base.display_name
			p.bag.add(it)
			p.equip_to(it, spec[1])
		await get_tree().create_timer(9.0).timeout
		Net.inspect(Net.my_id())
		await get_tree().create_timer(1.5).timeout
		_shot("net_inspect")
		Net.leave()
		get_tree().quit()
		return
	if "--chat" in OS.get_cmdline_user_args():
		# Bots chat in town (net_bot --say): the lines at the bottom left, then the box open
		await get_tree().create_timer(4.0).timeout
		_shot("net_chat")
		Net.chat_ui._set_open(true)
		Net.chat_ui._edit.text = "anyone up for a rift?"
		await get_tree().create_timer(0.5).timeout
		_shot("net_chat_open")
		Net.leave()
		get_tree().quit()
		return
	if "--party" in OS.get_cmdline_user_args():
		# An invite has come (a walker bot with --invite): its popup, then join, the party list, a card
		_shot("net_invite")
		var inv: Array = Net.party_ui._invites
		if not inv.is_empty():
			Net.party_ui._answer(int(inv[0].id), true)
		await get_tree().create_timer(3.0).timeout
		_shot("net_party")
		for m in Net.party.get("members", []):
			if int(m.id) != Net.my_id() and int(m.id) != int(Net.party.leader):
				Net.party_ui.show_card(int(m.id))
		await get_tree().create_timer(0.5).timeout
		_shot("net_card")
		print("party: ", Net.party)
		Net.leave()
		get_tree().quit()
		return
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/net_town.png"))
	print("saved net_town, others: ", Net.others.size())
	Net.leave()
	get_tree().quit()


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/%s.png" % n))
	print("saved ", n)
