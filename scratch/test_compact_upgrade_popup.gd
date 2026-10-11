extends Node2D

func _ready() -> void:
	print("--- TEST COMPACT UPGRADE POPUP IN LIVE TOWN ---")
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)

	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = town.player
	var popup_ui: UpgradePopupUI = town.upgrade_popup_ui

	# 1. Equip a basic weapon using equip_with_overflow
	var basic_sword := LootGenerator.roll_item(1, ItemInstance.Rarity.NORMAL, "weapon")
	basic_sword.display_name = "Rusty Shortsword"
	player.equip_with_overflow(basic_sword)
	print("Initial gear: ", player.equipment["weapon"].display_name, " (DMG: ", player.stats.get_stat("damage"), ")")

	# 2. Roll a powerful rare upgrade weapon
	var rare_sword := LootGenerator.roll_item(10, ItemInstance.Rarity.RARE, "weapon")
	rare_sword.affixes.append({
		"id": "brutal",
		"stat": "damage",
		"mod_type": StatBlock.ModType.FLAT,
		"value": 30.0,
		"text": "+30 Physical Damage"
	})
	rare_sword.display_name = "Doomblade of Carnage"
	assert(player.is_better_in_slot(rare_sword), "Rare sword should be better in slot!")
	print("Upgrade item generated: ", rare_sword.display_name)

	# 3. Simulate walking over pickup into bag
	assert(player.pick_up(rare_sword), "Should pick up into bag")
	popup_ui.prompt_upgrade(rare_sword, null)

	# Assertions on non-interference
	assert(popup_ui.is_open(), "Popup should be open")
	assert(not get_tree().paused, "GAMEPLAY MUST NOT BE PAUSED!")
	assert(popup_ui._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Root mouse filter must be IGNORE so it doesn't block gameplay")

	print("Summary delta: ", player.get_compact_upgrade_summary(rare_sword))
	print("Replaced gear name: ", player.get_replaced_gear_name(rare_sword))

	# Wait a couple frames and capture screenshot if renderer has texture
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	var vp := get_viewport()
	var tex := vp.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/compact_upgrade_popup.png")
			print("Saved screenshot to compact_upgrade_popup.png")

	# 4. Test Equip Now button
	popup_ui._on_equip_pressed()
	assert(not popup_ui.is_open(), "Popup should close after equip")
	assert(player.equipment["weapon"] == rare_sword, "Rare sword must now be equipped!")
	assert(player.inventory.has(basic_sword), "Previous basic sword must now be safely swapped into bag!")
	print("Equip success! Current weapon: ", player.equipment["weapon"].display_name, " (DMG: ", player.stats.get_stat("damage"), ")")
	print("Bag contains swapped old gear: ", basic_sword.display_name)

	# 5. Test auto-dismiss
	var helm_upgrade := LootGenerator.roll_item(10, ItemInstance.Rarity.MAGIC, "helmet")
	popup_ui.prompt_upgrade(helm_upgrade, null)
	assert(popup_ui.is_open(), "Popup open for helmet")
	# Simulate 7 seconds of game time passing
	popup_ui._process(7.0)
	assert(not popup_ui.is_open(), "Popup must auto-dismiss after timer without user intervention!")
	print("Auto-dismiss verified!")

	print("--- ALL COMPACT UPGRADE POPUP TESTS PASSED ---")
	get_tree().quit(0)
