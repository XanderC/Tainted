extends Node2D

func _ready() -> void:
	print("--- Running Comprehensive Skill Drag & Drop to Action Bar Test ---")
	
	# Reset game state and give skill points
	GameState._new_game()
	GameState.skill_points = 10
	GameState.unlock_or_upgrade_skill("whirlwind")
	GameState.unlock_or_upgrade_skill("frenzy")
	
	print("Initial equipped skills: ", GameState.equipped_skills)
	
	# --------------------------------------------------------------------------
	# PART 1: TEST SKILL TREE UI ACTION BAR DOCK & DRAG-AND-DROP
	# --------------------------------------------------------------------------
	var tree_ui := SkillTreeUI.new()
	add_child(tree_ui)
	tree_ui.open("berserker")
	
	# Wait two frames for Godot UI layout to compute rects
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 1. Verify Action Bar Dock was created with 4 slots
	assert(tree_ui._action_bar_dock != null, "Action Bar Dock must not be null")
	assert(tree_ui._ab_slot_cards.size() == 4, "Action Bar Dock must have 4 slot cards")
	for i in 4:
		print("SkillTreeUI Slot %d global rect: %s" % [i, tree_ui._ab_slot_cards[i].get_global_rect()])
	print("Action Bar Dock created successfully with 4 slots!")
	
	# 2. Test dragging Action Bar slot 1 onto Action Bar slot 0 in Skill Tree
	print("Testing drag swap between slot 1 and slot 0 on Action Bar Dock...")
	var before_0: String = GameState.equipped_skills[0]
	var before_1: String = GameState.equipped_skills[1]
	
	tree_ui._press_active = true
	tree_ui._press_source = "ab_slot"
	tree_ui._press_ab_slot_idx = 1
	tree_ui._press_skill_id = before_1
	
	var slot0_card: PanelContainer = tree_ui._ab_slot_cards[0]
	var drop_pos: Vector2 = slot0_card.get_global_rect().get_center()
	tree_ui._finish_drag_skill(drop_pos)
	tree_ui._end_drag_all()
	
	print("Equipped skills after slot 1 <-> slot 0 swap: ", GameState.equipped_skills)
	assert(GameState.equipped_skills[0] == before_1, "Slot 0 should now have swapped with slot 1")
	assert(GameState.equipped_skills[1] == before_0, "Slot 1 should now have swapped with slot 0")
	print("Test 1 Passed: Action Bar Dock slot drag-swap verified!")
	
	# Wait for layout refresh
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 3. Test dragging a skill from the tree node onto Action Bar slot 2
	print("Testing drag from skill tree node ('frenzy') onto Action Bar slot 2...")
	tree_ui._press_active = true
	tree_ui._press_source = "skill_node"
	tree_ui._press_skill_id = "frenzy"
	tree_ui._press_ab_slot_idx = -1
	
	var slot2_card: PanelContainer = tree_ui._ab_slot_cards[2]
	var drop_pos2: Vector2 = slot2_card.get_global_rect().get_center()
	tree_ui._finish_drag_skill(drop_pos2)
	tree_ui._end_drag_all()
	
	print("Equipped skills after frenzy drop on slot 2: ", GameState.equipped_skills)
	assert(GameState.equipped_skills[2] == "frenzy", "Slot 2 should now be frenzy")
	print("Test 2 Passed: Tree node skill drag-and-drop to Action Bar verified!")
	
	# Wait for layout after _refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 4. Test dragging an already-equipped skill ('whirlwind') to another slot (e.g. slot 3)
	print("Testing drag already-equipped skill ('whirlwind') to slot 3 (swap!)...")
	var whirlwind_current_idx := GameState.equipped_skills.find("whirlwind")
	var slot3_current_skill: String = GameState.equipped_skills[3]
	
	tree_ui._press_active = true
	tree_ui._press_source = "skill_node"
	tree_ui._press_skill_id = "whirlwind"
	tree_ui._press_ab_slot_idx = -1
	
	var slot3_card: PanelContainer = tree_ui._ab_slot_cards[3]
	var drop_pos3: Vector2 = slot3_card.get_global_rect().get_center()
	tree_ui._finish_drag_skill(drop_pos3)
	tree_ui._end_drag_all()
	
	print("Equipped skills after whirlwind dropped on slot 3: ", GameState.equipped_skills)
	assert(GameState.equipped_skills[3] == "whirlwind", "Slot 3 should now be whirlwind")
	assert(GameState.equipped_skills[whirlwind_current_idx] == slot3_current_skill, "Previous slot should now have swapped with slot 3")
	print("Test 3 Passed: Equipped skill auto-swap on Action Bar verified!")
	
	tree_ui.close()
	
	# --------------------------------------------------------------------------
	# PART 2: TEST INVENTORY UI RUNES & SKILLS ACTION BAR DRAG-SWAP
	# --------------------------------------------------------------------------
	var dummy_player := Player.new()
	add_child(dummy_player)
	
	var inv_ui := InventoryUI.new()
	inv_ui.player = dummy_player
	add_child(inv_ui)
	inv_ui.open()
	inv_ui._set_tab(1)  # Runes & Skills tab
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	assert(inv_ui._action_skill_slot_cards.size() == 4, "Inventory Runes view must track 4 action skill slot cards")
	print("Inventory UI has 4 action skill slot cards ready for drag!")
	
	var inv_before_0: String = GameState.equipped_skills[0]
	var inv_before_1: String = GameState.equipped_skills[1]
	
	print("Testing drag swap in Inventory UI between Action Slot 0 and Action Slot 1...")
	inv_ui._press_active = true
	inv_ui._press_source = "action_slot"
	inv_ui._press_action_slot_idx = 0
	inv_ui._press_skill_id = inv_before_0
	inv_ui._start_drag()
	
	var target_inv_card: PanelContainer = inv_ui._action_skill_slot_cards[1]["card"]
	var inv_drop_pos: Vector2 = target_inv_card.get_global_rect().get_center()
	inv_ui._update_drag(inv_drop_pos)
	inv_ui._finish_drag(inv_drop_pos)
	inv_ui._end_drag()
	
	print("Equipped skills after Inventory UI drag swap: ", GameState.equipped_skills)
	assert(GameState.equipped_skills[0] == inv_before_1, "Inventory UI: Slot 0 should now be %s" % inv_before_1)
	assert(GameState.equipped_skills[1] == inv_before_0, "Inventory UI: Slot 1 should now be %s" % inv_before_0)
	print("Test 4 Passed: Inventory UI Action Bar drag-swap verified successfully!")
	
	# 5. Capture screenshots if renderer produces texture
	tree_ui.open("berserker")
	await get_tree().process_frame
	await get_tree().process_frame
	
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null:
				var save_path := "C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/skill_tree_action_bar_dock.png"
				img.save_png(save_path)
				print("Saved screenshot to: ", save_path)
	
	print("========================================")
	print("=== ALL 4 SKILL DRAG TESTS PASSED! ===")
	print("========================================")
	get_tree().quit(0)
