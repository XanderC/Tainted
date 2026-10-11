extends Node2D
## Screenshots of the grid bag (inventory) and the grid stash, with assorted gear in them.
## Needs a window (not --headless):  godot --path . res://scratch/capture_item_grid.tscn

const OUT := "res://scratch/"


func item(id: String, rarity := ItemInstance.Rarity.NORMAL) -> ItemInstance:
	for b in LootGenerator.bases:
		if b.id == id:
			var it := ItemInstance.new()
			it.base = b
			it.rarity = rarity
			it.display_name = b.display_name
			return it
	return null


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()
	GameState.stash.clear()
	var R := ItemInstance.Rarity
	for pair in [["greatsword", R.RARE], ["chain_mail", R.MAGIC], ["rusty_sword", R.NORMAL], ["iron_helm", R.MAGIC],
			["tower_shield", R.RARE], ["oak_staff", R.NORMAL], ["bone_ring", R.RARE], ["old_amulet", R.MAGIC],
			["dagger", R.NORMAL], ["leather_gloves", R.NORMAL], ["bone_ring", R.MAGIC]]:
		p.bag.add(item(pair[0], pair[1]))
	for pair in [["battle_axe", R.RARE], ["padded_vest", R.NORMAL], ["worn_boots", R.MAGIC], ["hunting_bow", R.RARE],
			["war_maul", R.NORMAL], ["wooden_shield", R.MAGIC], ["old_amulet", R.RARE]]:
		GameState.stash.add(item(pair[0], pair[1]))
	p.inventory_changed.emit()

	town.menu.open("details")
	await _settle()
	_shot("grid_bag.png")

	town.menu.close()
	town.menu.open_vendor("stash")
	await _settle()
	_shot("grid_stash.png")
	get_tree().quit(0)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size())
