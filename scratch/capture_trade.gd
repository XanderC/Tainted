extends Node2D
## The trade window with items and orbs on both sides (no server: a made-up trade state), saved to
## scratch/trade_orbs.png.
##   godot --path . --resolution 1600x720 res://scratch/capture_trade.tscn


func _ready() -> void:
	GameState.char_name = "Brom"
	add_child(load("res://scenes/town.tscn").instantiate())
	await get_tree().create_timer(1.0).timeout
	var p: Player = GameState.player
	for i in 6:
		p.bag.add(LootGenerator.roll_item(12, ItemInstance.Rarity.RARE if i % 2 == 0 else ItemInstance.Rarity.MAGIC))
	for id in ["transmute", "alteration", "alchemy", "chance", "regal", "scour"]:
		GameState.orbs[id] = [34, 12, 7, 3, 2, 5][["transmute", "alteration", "alchemy", "chance", "regal", "scour"].find(id)]
	var mine: Array = [p.inventory.filter(func(it): return it != null)[0].to_dict()]
	var theirs: Array = [LootGenerator.roll_item(14, ItemInstance.Rarity.RARE).to_dict(), LootGenerator.roll_item(14, ItemInstance.Rarity.MAGIC).to_dict()]
	Net.trade_ui._on_state({"with": 2, "name": "Kael", "mine": mine, "theirs": theirs, "mine_orbs": {"alchemy": 3, "transmute": 10},
		"theirs_orbs": {"regal": 1}, "ready_me": false, "ready_them": true})
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/trade_orbs.png"))
	print("saved trade_orbs")
	get_tree().quit()
