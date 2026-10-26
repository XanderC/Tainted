extends Node2D
## Screenshot of the character panel's paperdoll with gear on every slot (scratch/doll.png). Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_doll.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	for id in ["leather_jerkin", "iron_gauntlets", "gilded_bracers", "frost_kilt", "strapped_pauldrons"]:
		var it := LootGenerator.roll_item(12, ItemInstance.Rarity.MAGIC, "")
		it.base = LootGenerator.base_by_id(id)
		it.display_name = it.base.display_name
		p.bag.add(it)
		p.equip_to(it, it.base.slot)
	town.menu.open()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://scratch/doll.png")
	get_tree().quit()
