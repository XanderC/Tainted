extends Node2D

func _ready() -> void:
	GameState._new_game()
	
	var dummy_player := Player.new()
	add_child(dummy_player)
	
	var inv_ui := InventoryUI.new()
	inv_ui.player = dummy_player
	add_child(inv_ui)
	inv_ui.open()
	inv_ui._set_tab(1)  # Runes & Skills view
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null:
				img.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/inventory_action_skills_drag.png")
				print("Saved inventory_action_skills_drag.png successfully!")
	
	get_tree().quit(0)
