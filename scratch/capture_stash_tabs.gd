extends Node2D
## Screenshots of the stash's tabs (Items, Currency, Materials, Gems) and of the Skills panel
## locked away from the stash. Needs a window:  godot --path . res://scratch/capture_stash_tabs.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: GameMenu = town.menu

	menu.open("skills")  # from the inventory: view-only
	await _settle()
	_shot("skills_locked.png")
	menu.close()

	menu.open_vendor("stash")
	var stash := menu.current_panel() as StashPanel
	for t in ["currency", "materials", "gems"]:
		stash.tab = t
		menu.refresh()
		await _settle()
		_shot("stash_%s.png" % t)
	get_tree().quit(0)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/" + name))
	print("saved ", name)
