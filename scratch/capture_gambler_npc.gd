extends Node2D
## A picture of Lucky Mott the Gambler in Ashfall (gambler_npc.png in the folder after --out=).
##   godot --path . --resolution 1600x720 res://scratch/capture_gambler_npc.tscn -- --out=<folder>


func _ready() -> void:
	var out := "res://scratch/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	town.player.global_position = town.GAMBLER + Vector2(-150, 60)
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "gambler_npc.png")
	get_tree().quit()
