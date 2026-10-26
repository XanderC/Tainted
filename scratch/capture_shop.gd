extends Node2D
## A picture of the Merchant beside the bag (shop.png in the folder after --out=, default scratch/),
## and of the stash, to check the menu's two panels share the screen.
##   godot --path . --resolution 1600x720 res://scratch/capture_shop.tscn -- --out=<folder>


func _ready() -> void:
	var out := "res://scratch/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 4:
		await get_tree().process_frame
	var menu: GameMenu = town.menu
	menu.open_vendor("shop")
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "shop.png")
	menu.open_vendor("stash")
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "stash.png")
	get_tree().quit()
