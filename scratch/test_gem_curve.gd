extends Node2D
## Path of Exile 2's level curve on skill gems: each skill is cut at its tier's character level (basic 1, core 6,
## defensive 10, brawling 14, mastery 31, ultimate 58), a gem levels up only when the character is high enough for the
## next gem level, a skill already cut can still be socketed, and a gem's experience bar waits full. Run headless:
##   godot --headless --path . res://scratch/test_gem_curve.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	await get_tree().process_frame
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	GameState.cut_skills = {}
	GameState.gem_levels = {}
	GameState.gem_xp = {}
	GameState.support_levels = {}
	GameState.support_xp = {}
	GameState.uncut_gems = 5
	for i in GameState.SKILL_SLOTS:
		GameState.clear_slot_skill(i)

	# The curve itself
	var curve := [0, 3, 6, 10, 14, 18, 22, 26, 31, 36, 41, 46, 52, 58, 64, 66, 72, 78, 84, 90]
	check(SkillTree.GEM_CHAR_LEVEL == curve, "the curve is PoE2's")
	check(SkillTree.gem_char_level(1) == 1 and SkillTree.gem_char_level(3) == 6 and SkillTree.gem_char_level(14) == 58
		and SkillTree.gem_char_level(20) == 90, "gem level n needs the curve's character level (at least 1)")
	check(SkillTree.gem_char_level(0) == 1 and SkillTree.gem_char_level(99) == 90, "out-of-range gem levels are clamped")

	# A skill's tier sets the level it is cut at
	check(SkillTree.gem_level_req("cleave") == 1 and SkillTree.gem_level_req("quick_shot") == 1, "basic skills: level 1")
	check(SkillTree.gem_level_req("whirlwind") == 6 and SkillTree.gem_level_req("arc") == 6, "core skills: level 6")
	check(SkillTree.gem_level_req("ground_stomp") == 10, "defensive skills: level 10")
	check(SkillTree.gem_level_req("leap_slam") == 14, "brawling skills: level 14")
	check(SkillTree.gem_level_req("earthquake") == 31, "mastery skills: level 31")
	check(SkillTree.gem_level_req("berserk") == 58, "ultimate skills: level 58")

	GameState.level = 5
	check(GameState.unlock_block_reason("whirlwind") == "Needs level 6", "a core skill needs level 6 (%s)" % GameState.unlock_block_reason("whirlwind"))
	GameState.level = 6
	check(GameState.unlock_skill("whirlwind"), "and can be cut at 6")
	GameState.level = 20
	check(GameState.unlock_block_reason("earthquake") == "Needs level 31", "a mastery skill is out of reach at 20")

	# A skill already cut stays usable if the character is below its level (an old character)
	GameState.cut_skills["earthquake"] = true
	check(GameState.skill_gem_block_reason("earthquake") == "", "a skill already cut can be socketed below its level")
	GameState.cut_skills.erase("earthquake")
	check(GameState.skill_gem_block_reason("earthquake") != "", "one that is not cut still needs the level")

	# Levelling: the next gem level's character level
	check(GameState.gem_level_up_block(1, 1) == "Needs character level 3 to level up", "level 1 to 2 needs character level 3")
	check(GameState.gem_level_up_block(3, 1) == "" and GameState.gem_level_up_block(2, 1) != "", "exactly the curve's level opens it")
	check(GameState.gem_level_up_block(1, SkillTree.GEM_MAX_LEVEL) == "", "a gem at the top has nothing to wait for")

	GameState.level = 10   # curve: gem level 4 needs 10, level 5 needs 14
	GameState.gem_levels["cleave"] = 1
	GameState.gem_xp["cleave"] = 0.0
	var up := GameState._add_gem_xp(GameState.gem_levels, GameState.gem_xp, "cleave", 1.0e9)
	check(up and GameState.gem_level("cleave") == 4, "a huge amount of xp at level 10 stops at gem level 4 (%d)" % GameState.gem_level("cleave"))
	check(is_equal_approx(float(GameState.gem_xp["cleave"]), GameState.gem_xp_to_next(4)), "its bar waits full, not overflowing (%s)" % GameState.gem_xp["cleave"])
	GameState.level = 14
	up = GameState._add_gem_xp(GameState.gem_levels, GameState.gem_xp, "cleave", 1.0)
	check(up and GameState.gem_level("cleave") == 5, "a character level later it goes up with the next experience (%d)" % GameState.gem_level("cleave"))

	# The Gemcutter's Prism is not wasted on a gem that is waiting
	GameState.orbs["gemcutter"] = 2
	GameState.level = 14   # gem level 6 needs 18
	GameState.gem_levels["cleave"] = 5
	check(not GameState.use_gemcutter("cleave", false) and GameState.orb_count("gemcutter") == 2, "a waiting gem refuses the Prism and keeps it")
	GameState.level = 18
	check(GameState.use_gemcutter("cleave", false) and GameState.gem_level("cleave") == 6 and GameState.orb_count("gemcutter") == 1,
		"once the character is high enough the Prism levels it")

	# Supports follow the same curve
	GameState.level = 3
	GameState.support_levels["rune_frost"] = 1
	GameState.support_xp["rune_frost"] = 0.0
	GameState._add_gem_xp(GameState.support_levels, GameState.support_xp, "rune_frost", 1.0e9)
	check(GameState.support_level("rune_frost") == 2, "a support at character level 3 stops at gem level 2 (%d)" % GameState.support_level("rune_frost"))

	print("gem curve: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
