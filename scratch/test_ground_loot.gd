extends Node2D
## Items dropped in a zone lie unidentified (Magic and better; Normal and flasks stay as they are), and an
## item on the ground is just its icon. Takes scratch/ground_loot.png.
##   godot --path . --resolution 1600x720 res://scratch/test_ground_loot.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	await get_tree().create_timer(1.2).timeout
	var at: Vector2 = zone.player.global_position + Vector2(0, 160)
	var rare := LootGenerator.roll_item(5, ItemInstance.Rarity.RARE)
	var magic := LootGenerator.roll_item(5, ItemInstance.Rarity.MAGIC, "weapon")
	var plain := LootGenerator.roll_item(5, ItemInstance.Rarity.NORMAL)
	zone._drop_item(rare, at + Vector2(-120, 0))
	zone._drop_item(magic, at)
	zone._drop_item(plain, at + Vector2(120, 0))
	check(not rare.identified and not magic.identified, "magic and rare drops are unidentified")
	check(rare.display_name == rare.base.display_name, "and show only their base name (%s)" % rare.display_name)
	check(plain.identified, "a normal drop is plain")
	# A dropped-by-the-player item keeps its state
	var mine := LootGenerator.roll_item(5, ItemInstance.Rarity.RARE)
	zone._on_item_dropped(mine)
	check(mine.identified, "an item you drop yourself stays identified")
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/ground_loot.png"))
	print("ground loot: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
