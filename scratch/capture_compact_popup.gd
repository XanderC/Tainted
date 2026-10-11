extends SceneTree

func _init() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var town = load("res://scenes/town.tscn").instantiate()
	vp.add_child(town)

	await create_timer(0.2).timeout

	var player: Player = town.player
	var popup_ui: UpgradePopupUI = town.upgrade_popup_ui

	var sword := LootGenerator.roll_item(10, ItemInstance.Rarity.RARE, "weapon")
	sword.affixes.append({
		"id": "brutal",
		"stat": "damage",
		"mod_type": StatBlock.ModType.FLAT,
		"value": 25.0,
		"text": "+25 Physical Damage"
	})
	sword.display_name = "Doomblade of Carnage"
	player.pick_up(sword)
	popup_ui.prompt_upgrade(sword, null)

	await create_timer(0.3).timeout

	var tex := vp.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/compact_upgrade_popup.png")
			print("Visual screenshot successfully captured!")

	quit(0)
