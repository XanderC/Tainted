extends Node2D
## The support picker with the PoE2 supports, on a bow skill and on a melee one (scratch/support_picker_*.png). Needs a window:
##   godot --path . --resolution 1600x720 res://scratch/capture_support_picker.tscn


func _ready() -> void:
	GameState.give_starter_skills()
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: GameMenu = town.menu
	GameState.level = 40
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	for id in ["quick_shot", "cleave", "arc"]:
		GameState.grant_skill(id)
	GameState.set_slot_skill(0, "quick_shot")
	GameState.set_slot_skill(1, "cleave")
	GameState.set_slot_skill(2, "arc")
	for r in RuneDef.DB.base_runes():
		GameState.runes[r.id] = 1
	GameState.runes["rune_multishot_1@1"] = 1
	GameState.skill_slots[0].supports = []
	GameState.skill_slots[1].supports = []
	GameState.skill_slots[2].supports = []
	menu.open_vendor("jeweler")
	menu.show_panel("skills")
	await get_tree().process_frame
	var sp: SkillGemsPanel = menu.current_panel()
	for slot in [0, 1, 2]:
		sp._pick_support(slot, 0, Vector2(560, 120))
		for i in 6:
			await get_tree().process_frame
		await get_tree().create_timer(0.4, true, false, true).timeout
		for sc in menu.item_tip().find_children("*", "ScrollContainer", true, false):
			(sc as ScrollContainer).scroll_vertical = 100000
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/support_picker_%d.png" % slot))
		sp._close_pick()
		await get_tree().process_frame
	get_tree().quit(0)
