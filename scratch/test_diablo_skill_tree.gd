extends Node2D

func _ready() -> void:
	print("--- TESTING DIABLO SKILL TREE SYSTEM ---")
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)

	await get_tree().process_frame
	await get_tree().process_frame

	var st_ui: SkillTreeUI = town.skill_tree_ui
	st_ui.open("berserker")

	assert(st_ui.is_open(), "Skill tree must be open")
	print("Opened Berserker skill tree successfully.")

	# Give player 10 skill points for testing
	GameState.skill_points = 10
	st_ui._refresh()

	# Select threatening_shout (like in the user's reference image!)
	st_ui._selected_skill_id = "threatening_shout"
	st_ui._refresh()

	# Invest 2 points into threatening shout
	assert(GameState.can_unlock_skill("threatening_shout"), "Should be able to unlock threatening shout")
	GameState.unlock_or_upgrade_skill("threatening_shout")
	GameState.unlock_or_upgrade_skill("threatening_shout")
	st_ui._refresh()

	assert(GameState.get_skill_rank("threatening_shout") == 2, "Rank should be 2")
	print("Threatening Shout rank: ", GameState.get_skill_rank("threatening_shout"))

	# Invest points into Frenzy -> Double Swing -> Whirlwind (testing prerequisite chains)
	assert(GameState.get_skill_rank("frenzy") == 0, "Frenzy starting at 0")
	assert(not GameState.can_unlock_skill("whirlwind"), "Cannot unlock Whirlwind before Double Swing & Frenzy")

	# Unlock Frenzy
	assert(GameState.unlock_or_upgrade_skill("frenzy"), "Unlocked Frenzy")
	# Now Double Swing should be available
	assert(GameState.can_unlock_skill("double_swing"), "Double Swing should be unlockable now")
	assert(GameState.unlock_or_upgrade_skill("double_swing"), "Unlocked Double Swing")
	# Now Whirlwind should be available!
	assert(GameState.can_unlock_skill("whirlwind"), "Whirlwind should be unlockable now")
	assert(GameState.unlock_or_upgrade_skill("whirlwind"), "Unlocked Whirlwind")
	print("Whirlwind successfully unlocked via prerequisite tree!")

	st_ui._selected_skill_id = "whirlwind"
	st_ui._refresh()

	# Wait a frame to capture Berserker screenshot
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	var vp := get_viewport()
	var tex := vp.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/diablo_skill_tree_berserker.png")
			print("Saved screenshot: diablo_skill_tree_berserker.png")

	# Test Juggernaut branch
	st_ui._select_branch("juggernaut")
	st_ui._selected_skill_id = "shield_slam"
	st_ui._refresh()

	await get_tree().create_timer(0.2).timeout
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img.save_png("C:/Users/simon/.gemini/antigravity-ide/brain/42db83ca-0e9d-4806-81ab-575bc706c24f/scratch/diablo_skill_tree_juggernaut.png")
			print("Saved screenshot: diablo_skill_tree_juggernaut.png")

	print("--- ALL DIABLO SKILL TREE TESTS PASSED ---")
	get_tree().quit(0)
