extends Node2D
## Screenshot of an item card with socketed gems, a rune and an empty socket (scratch/socket_card.png).
## Needs a window:  godot --path . --resolution 1280x720 res://scratch/capture_socket_card.tscn


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var menu: GameMenu = town.menu
	GameState.attributes = {"str": 300}
	p.refresh_attributes()
	var it := LootGenerator.roll_item(20, ItemInstance.Rarity.RARE, "")
	it.base = LootGenerator.base_by_id("battle_plate")
	it.display_name = "Soul Mantle"
	it.sockets = 4
	it.gems = ["ruby_7", "diamond_3", SocketRune.all_ids()[26]]
	p.bag.add(it)
	p.inventory_changed.emit()
	menu.open()
	Input.warp_mouse(Vector2(1000, 330))
	menu.select(it)
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/socket_card.png"))
	get_tree().quit()
