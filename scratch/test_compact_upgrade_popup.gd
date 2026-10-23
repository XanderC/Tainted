extends Node2D

func _ready() -> void:
	print("--- TEST COMPACT UPGRADE POPUP IN LIVE TOWN ---")
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)

	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = town.player
	var popup_ui: UpgradePopupUI = town.upgrade_popup_ui
	GameState.attributes = {"str": 40, "dex": 40, "ene": 40}  # whatever weapon it rolls, it can wield
	player.refresh_attributes()

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

	# 4. Picking up never equips
	# Equipping is only by dragging: picking it up left it in the bag, and the popup only says how
	assert(player.inventory.has(rare_sword), "The picked-up upgrade must be in the bag")
	assert(player.equipment["weapon"] == basic_sword, "Picking up must never equip it")
	assert(not popup_ui.has_method("_on_equip_pressed"), "The popup has no Equip action")
	assert(popup_ui._hint_lbl.text.contains("drag"), "The popup says to drag it onto its slot")
	popup_ui.close()
	# An empty slot doesn't change that
	var helm_drop := LootGenerator.roll_item(5, ItemInstance.Rarity.MAGIC, "helmet")
	assert(not player.equipment.has("helmet"), "No helmet worn yet")
	assert(player.pick_up(helm_drop), "Helmet picked up")
	assert(not player.equipment.has("helmet") and player.inventory.has(helm_drop), "Even into an empty slot, pickup goes to the bag")
	print("Upgrades stay in the bag until dragged onto their slot")

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
