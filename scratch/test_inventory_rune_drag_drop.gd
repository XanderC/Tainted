extends Node2D

func _ready() -> void:
	print("--- Starting Inventory & Rune Drag-and-Drop Test ---")
	
	# Ensure game state is loaded/initialized
	GameState._new_game()
	
	print("Initial equipped skills: ", GameState.equipped_skills)
	print("Initial cleave runes: ", GameState.skill_runes.get("cleave", []))
	print("Initial runes in pouch: ", GameState.runes)
	
	# Test 1: Swap socket with inventory directly
	var initial_frost_count: int = GameState.rune_count("rune_frost")
	var initial_fire_count: int = GameState.rune_count("rune_fire")
	
	print("Testing swap_socket_with_inventory on Cleave slot 0...")
	# Cleave already has rune_frost in slot 0. Swapping with rune_fire:
	var swap_ok := GameState.swap_socket_with_inventory("cleave", 0, "rune_fire")
	assert(swap_ok, "Swap failed!")
	assert(GameState.skill_runes["cleave"][0] == "rune_fire", "Cleave slot 0 should now be rune_fire")
	assert(GameState.rune_count("rune_frost") == initial_frost_count + 1, "rune_frost should be returned to inventory pouch")
	assert(GameState.rune_count("rune_fire") == initial_fire_count - 1, "rune_fire count should decrease by 1")
	print("Test 1 Passed: Swapped occupied socket with inventory rune cleanly!")
	
	# Test 2: Swap sockets between skills
	print("Testing swap_runes_between_skills...")
	# Put rune_lightning into Whirlwind slot 0
	GameState.socket_rune_into_skill("whirlwind", "rune_lightning")
	assert(GameState.skill_runes["whirlwind"][0] == "rune_lightning")
	
	# Swap Cleave slot 0 (fire) and Whirlwind slot 0 (lightning)
	var skill_swap_ok := GameState.swap_runes_between_skills("cleave", 0, "whirlwind", 0)
	assert(skill_swap_ok, "Skill swap failed!")
	assert(GameState.skill_runes["cleave"][0] == "rune_lightning", "Cleave slot 0 should now be rune_lightning")
	assert(GameState.skill_runes["whirlwind"][0] == "rune_fire", "Whirlwind slot 0 should now be rune_fire")
	print("Test 2 Passed: Swapped runes across skills cleanly!")
	
	# Test 3: Unsocket rune back to inventory
	print("Testing unsocket_rune_from_skill...")
	var pre_light_count: int = GameState.rune_count("rune_lightning")
	GameState.unsocket_rune_from_skill("cleave", 0)
	assert(GameState.rune_count("rune_lightning") == pre_light_count + 1, "rune_lightning returned to inventory")
	assert(GameState.skill_runes["cleave"].is_empty(), "Cleave sockets should now be empty")
	print("Test 3 Passed: Unsocketed rune cleanly back to pouch!")
	
	# Reset game state and instantiate Player & InventoryUI
	GameState._new_game()
	
	var player := Player.new()
	player.position = Vector2(640, 360)
	add_child(player)
	
	var inv_ui := InventoryUI.new()
	inv_ui.player = player
	add_child(inv_ui)
	
	# Wait 2 frames for UI to construct
	await get_tree().process_frame
	await get_tree().process_frame
	
	inv_ui.open()
	await get_tree().process_frame
	
	# Screenshot 1: Gear Tab
	var img1 := get_viewport().get_texture().get_image()
	img1.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/inventory_gear_tab.png")
	print("Saved inventory_gear_tab.png")
	
	# Switch to Runes Tab
	inv_ui._set_tab(1)
	await get_tree().process_frame
	
	# Screenshot 2: Runes & Skill Sockets Tab
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/inventory_runes_tab.png")
	print("Saved inventory_runes_tab.png")
	
	# Test 4: Simulate UI Drag from Pouch to Cleave Socket 1
	print("Simulating UI Drag from Pouch (rune_echo) to Cleave Socket 1...")
	inv_ui._press_active = true
	inv_ui._press_source = "pouch_rune"
	inv_ui._press_rune_id = "rune_echo"
	inv_ui._press_start_pos = Vector2(600, 200)
	inv_ui._start_drag()
	
	assert(inv_ui._is_dragging, "Should be dragging")
	assert(inv_ui._is_dragging_rune, "Should be dragging rune")
	
	# Move to Cleave socket 1
	var target_card: PanelContainer = null
	for sc in inv_ui._skill_socket_cards:
		if sc["skill_id"] == "cleave" and sc["socket_idx"] == 1:
			target_card = sc["card"]
			break
	assert(target_card != null, "Cleave socket 1 card not found")
	
	var target_pos := target_card.global_position + Vector2(20, 20)
	inv_ui._update_drag(target_pos)
	
	# Capture Screenshot 3: Active Drag Ghost hovering over socket
	await get_tree().process_frame
	var img3 := get_viewport().get_texture().get_image()
	img3.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/inventory_rune_drag_hover.png")
	print("Saved inventory_rune_drag_hover.png")
	
	# Drop onto socket
	inv_ui._finish_drag(target_pos)
	inv_ui._end_drag()
	
	assert(GameState.skill_runes["cleave"].has("rune_echo"), "Cleave should now have rune_echo socketed!")
	print("Test 4 Passed: UI Drag & Drop successfully socketed rune_echo into Cleave!")
	
	# Test 5: Drag rune_lightning onto occupied socket 0 (which has rune_frost) -> SWAP!
	print("Simulating Drag rune_lightning onto occupied Cleave socket 0 (swap)...")
	inv_ui._press_active = true
	inv_ui._press_source = "pouch_rune"
	inv_ui._press_rune_id = "rune_lightning"
	inv_ui._start_drag()
	
	var socket0_card: PanelContainer = null
	for sc in inv_ui._skill_socket_cards:
		if sc["skill_id"] == "cleave" and sc["socket_idx"] == 0:
			socket0_card = sc["card"]
			break
	var s0_pos := socket0_card.global_position + Vector2(20, 20)
	inv_ui._update_drag(s0_pos)
	inv_ui._finish_drag(s0_pos)
	inv_ui._end_drag()
	
	assert(GameState.skill_runes["cleave"][0] == "rune_lightning", "Cleave slot 0 should now be swapped to lightning!")
	assert(GameState.rune_count("rune_frost") > 0, "Old frost rune returned to inventory!")
	print("Test 5 Passed: UI Drag & Drop swap executed flawlessly!")
	
	await get_tree().process_frame
	var img4 := get_viewport().get_texture().get_image()
	img4.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/inventory_runes_after_swaps.png")
	print("Saved inventory_runes_after_swaps.png")
	
	print("--- ALL INVENTORY RUNE DRAG-AND-DROP TESTS PASSED! ---")
	get_tree().quit(0)
