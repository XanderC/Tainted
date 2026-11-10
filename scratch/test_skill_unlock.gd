extends Node2D
## Skill Gems unlock skills: a Skill Gem (the account's) is cut into a skill of your choice for this character for
## good, the level gate holds, an unlocked skill goes into slots without being used up, skills are listed by
## category in the Skills window with a Cut button, and the shop sells no skill gems. Run headless:
##   godot --headless --path . res://scratch/test_skill_unlock.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 3:
		await get_tree().process_frame
	var menu: GameMenu = town.menu
	GameState.level = 1
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	GameState.cut_skills = {}
	GameState.uncut_gems = 0
	for i in GameState.SKILL_SLOTS:
		GameState.clear_slot_skill(i)

	# Categories
	check(SkillTree.category("quick_shot") == "Bow" and SkillTree.category("cleave") == "Melee"
		and SkillTree.category("firebolt") == "Spell" and SkillTree.category("fan_of_knives") == "Throwing"
		and SkillTree.category("battle_cry") == "Shouts & Buffs", "skills fall into their categories")
	var seen := {}
	for sk in SkillTree.active_skills():
		var c := SkillTree.category(sk.id)
		seen[c] = int(seen.get(c, 0)) + 1
		check(SkillTree.CATEGORIES.has(c), "%s has a listed category (%s)" % [sk.id, c])
	check(seen.size() == SkillTree.CATEGORIES.size(), "every tab has skills (%s)" % [seen])

	# Cutting
	check(GameState.unlock_block_reason("cleave") == "You have no Skill Gem", "no gem: it says so")
	check(not GameState.unlock_skill("cleave") and not GameState.is_skill_unlocked("cleave"), "and cuts nothing")
	GameState.add_skill_gem(2)
	check(GameState.uncut_gems == 2, "a Skill Gem is picked up")
	var high := ""
	for sk in SkillTree.active_skills():
		if SkillTree.gem_level_req(sk.id) > 5:
			high = sk.id
			break
	check(high != "" and GameState.unlock_block_reason(high).begins_with("Needs level"), "a skill above your level cannot be cut yet")
	check(not GameState.unlock_skill(high) and GameState.uncut_gems == 2, "and it keeps the gem")
	check(GameState.unlock_skill("cleave") and GameState.is_skill_unlocked("cleave") and GameState.uncut_gems == 1, "cutting Cleave uses one gem")
	check(GameState.unlock_block_reason("cleave") == "Already cut" and not GameState.unlock_skill("cleave") and GameState.uncut_gems == 1,
		"a skill is cut once")
	check(GameState.unlock_block_reason("hl_guard") != "" or SkillTree.get_skill("hl_guard") == null, "a hireling's skill is not cut")

	# Slots no longer use skills up
	check(GameState.set_slot_skill(1, "cleave") and GameState.slot_skill(1) == "cleave", "an unlocked skill goes in a slot")
	check(not GameState.set_slot_skill(2, "firebolt"), "a skill you have not unlocked does not")
	check(GameState.set_slot_skill(2, "cleave") and GameState.slot_skill(1) == "" and GameState.slot_skill(2) == "cleave"
		or GameState.slot_of("cleave") == 2, "it is in one slot at a time")
	GameState.clear_slot_skill(GameState.slot_of("cleave"))
	check(GameState.is_skill_unlocked("cleave") and GameState.slot_of("cleave") < 0, "taken out, it stays unlocked")

	# Per character: the account's gems, but each character's skills
	var saved := GameState.cut_skills.duplicate()
	GameState.cut_skills = {}
	check(not GameState.is_skill_unlocked("cleave") and GameState.uncut_gems == 1, "another character has not cut it; the gem pool is shared")
	GameState.cut_skills = saved

	# The window
	GameState.level = 40
	menu.open_vendor("jeweler")
	menu.show_panel("skills")
	await get_tree().process_frame
	var sp: SkillGemsPanel = menu.current_panel()
	check(sp.find_child("CutTab_Bow", true, false) == null, "the Skills window opens on the slots")
	(sp.find_child("Mode_Cutting", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	sp = menu.current_panel()
	check(sp.find_child("CutTab_Bow", true, false) != null, "Gem Cutting shows the list")
	var tab_names := sp.find_children("CutTab_*", "Button", true, false).map(func(b): return b.name)
	check(tab_names.size() == SkillTree.CATEGORIES.size(), "the cutting list has a tab per category (%s)" % [tab_names])
	var bow_tab := sp.find_child("CutTab_Bow", true, false) as Button
	bow_tab.pressed.emit()
	await get_tree().process_frame
	sp = menu.current_panel()
	check(sp.find_child("Cut_quick_shot", true, false) != null and sp.find_child("Cut_cleave", true, false) == null, "the Bow tab lists bow skills only")
	var row := sp.find_child("Cut_power_shot", true, false)
	check(row != null, "Power Shot is listed")
	var btn := row.find_child("CutBtn", true, false) as Button
	check(btn != null and not btn.disabled and btn.text == "Cut", "it can be cut with a gem in hand")
	btn.pressed.emit()
	await get_tree().process_frame
	check(GameState.is_skill_unlocked("power_shot") and GameState.uncut_gems == 0, "pressing Cut unlocks it and spends the gem")
	sp = menu.current_panel()
	var done := sp.find_child("Cut_power_shot", true, false).find_child("CutBtn", true, false) as Button
	check(done.disabled and "Unlocked" in done.text, "and the row reads Unlocked")
	var other := sp.find_child("Cut_multishot", true, false).find_child("CutBtn", true, false) as Button
	check(other.disabled, "with no gem left the other rows cannot be cut")
	if DisplayServer.get_name() != "headless":
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/skill_cutting.png"))

	# The shop sells none
	var shop = load("res://scripts/shop_panel.gd")
	check(shop != null, "(the shop script loads)")
	var text := FileAccess.get_file_as_string("res://scripts/shop_panel.gd")
	check(not text.contains("skillgem") and not text.contains("buy_skill_gem"), "the shop no longer sells skill gems")

	# A gem on the ground goes into the account's count
	var c := CurrencyPickup.new()
	c.kind = "skill_gem"
	c.amount = 1
	add_child(c)
	check(c.label_text() == "Skill Gem", "a Skill Gem lies on the ground as 'Skill Gem' (%s)" % c.label_text())
	c.collect()
	check(GameState.uncut_gems == 1, "and picking it up adds one")
	c.queue_free()
	print("skill unlock: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
