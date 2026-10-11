extends Node2D

func _ready() -> void:
	GameState._new_game()
	GameState.skill_points = 10
	GameState.unlock_or_upgrade_skill("whirlwind")
	GameState.unlock_or_upgrade_skill("frenzy")
	
	var ui := SkillTreeUI.new()
	add_child(ui)
	ui.open("berserker")
	
	# Wait for layout and rendering
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null:
				img.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/skill_tree_action_bar_dock.png")
				print("Saved skill_tree_action_bar_dock.png successfully!")
	
	# Trigger a drag hover over slot 1
	var slot1_pos: Vector2 = ui._ab_slot_cards[1].get_global_rect().get_center()
	ui._press_source = "skill_node"
	ui._press_skill_id = "frenzy"
	ui._start_drag_skill()
	ui._update_drag_skill(slot1_pos)
	
	await get_tree().create_timer(0.3).timeout
	if vp != null:
		var tex2 := vp.get_texture()
		if tex2 != null:
			var img2 := tex2.get_image()
			if img2 != null:
				img2.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/skill_drag_hover_action_bar.png")
				print("Saved skill_drag_hover_action_bar.png successfully!")
	
	get_tree().quit(0)
