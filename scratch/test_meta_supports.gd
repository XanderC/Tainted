extends Node2D
## Meta supports: Cast on Critical Strike and Cast when Damage Taken. One per skill, linked like any support; a
## chosen skill (not the slot's own, not one that moves you) is cast free of cost on the event, with a wait
## between casts and never from another triggered cast; the Skills window lets you choose it; a hireling cannot
## link one. Run headless:
##   godot --headless --path . res://scratch/test_meta_supports.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _rows(tip: ItemTip) -> Array:
	return tip.find_children("*", "Button", true, false).filter(func(b): return b.visible and b.custom_minimum_size.y == SkillGemsPanel.PICK_ROW_H)


func _ready() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	p.stats.add_mod("spirit", StatBlock.ModType.FLAT, 500.0, "test_spirit")  # (several metas at once need Spirit)
	GameState.level = 40
	GameState.attributes = {"str": 300, "dex": 300, "vit": 300, "ene": 300}
	p.refresh_attributes()
	for id in ["iron_skin", "battle_cry", "frost_nova", "leap_slam"]:
		GameState.grant_skill(id)
	GameState.runes["rune_cast_crit"] = 2
	GameState.runes["rune_cast_hurt"] = 2
	GameState.runes["rune_fire"] = 1

	# The supports and their rules
	var crit := RuneDef.DB.get_rune("rune_cast_crit")
	var hurt := RuneDef.DB.get_rune("rune_cast_hurt")
	check(crit != null and crit.category == RuneDef.Category.META and crit.trigger == "crit", "Cast on Critical Strike exists")
	check(hurt != null and hurt.category == RuneDef.Category.META and hurt.trigger == "hurt", "Cast when Damage Taken exists")
	check(crit.cost_mult == 1.0 and crit.stat_lines().contains("critical strike"), "it costs the host nothing extra and says what it does")
	check(not SkillDef.supports_valid(["rune_cast_crit", "rune_cast_hurt"]), "only one meta support per skill")
	check(SkillDef.supports_valid(["rune_cast_crit", "rune_fire"]), "but it goes with an elemental support")
	check(SkillDef.supports_have_meta(["rune_fire", "rune_cast_hurt"]) and not SkillDef.supports_have_meta(["rune_fire"]), "a meta support is told apart")
	check(RuneDef.DB.get_rune("rune_cast_crit@1") != null, "and has the rarer versions")

	# Linking and choosing
	GameState.skill_slots[0].supports = []
	GameState.skill_slots[1].supports = []
	GameState.set_slot_skill(0, "cleave")
	GameState.set_slot_skill(1, "frenzy")
	check(GameState.socket_support(0, 0, "rune_cast_crit") and GameState.slot_meta(0) == crit, "linked in slot 0")
	check(GameState.slot_trigger(0) == "" and GameState.get_triggers().is_empty(), "with no skill chosen nothing fires")
	check(not GameState.set_slot_trigger(1, "iron_skin"), "a slot with no meta support chooses nothing")
	check(not GameState.set_slot_trigger(0, "cleave"), "not the slot's own skill (%s)" % GameState.trigger_block_reason(0, "cleave"))
	check(not GameState.set_slot_trigger(0, "leap_slam"), "not one that moves you (%s)" % GameState.trigger_block_reason(0, "leap_slam"))
	check(not GameState.set_slot_trigger(0, "meteor"), "not one you have not unlocked (%s)" % GameState.trigger_block_reason(0, "meteor"))
	check(GameState.set_slot_trigger(0, "iron_skin") and GameState.slot_trigger(0) == "iron_skin", "Iron Skin chosen")
	var trig := GameState.get_triggers()
	check(trig.size() == 1 and trig[0].event == "crit" and trig[0].skill.id == "iron_skin", "it is a crit trigger of Iron Skin")
	check(p._triggers.size() == 1, "and the player has it")

	# A critical strike casts it
	var dummy := Enemy.new()
	dummy.max_hp = 1.0e9
	dummy.speed = 0.0
	dummy.touch_damage = 0.0
	dummy.set_kind("zombie")
	main.add_child(dummy)
	dummy.global_position = p.global_position + Vector2(90, 0)
	await get_tree().process_frame
	p.can_fight = true
	var swing := func(): p._hit_area(p.global_position, Vector2.RIGHT, 200.0, 360.0, p.skills[0])
	p.item_powers["no_crit"] = 1.0
	swing.call()
	check(not p._iron_skin_active, "no critical strike: nothing cast")
	p.item_powers.erase("no_crit")
	p.stats.add_mod("crit_chance", StatBlock.ModType.FLAT, 1.0, "test")
	var mana0 := p.mana
	var res0 := p.resource
	swing.call()
	check(p._iron_skin_active, "a critical strike casts Iron Skin")
	check(p.mana >= mana0 - 0.01 and p.resource >= res0 - 0.01, "free of cost")
	p._iron_skin_active = false
	swing.call()
	check(not p._iron_skin_active, "and it waits between casts")
	await get_tree().create_timer(0.6).timeout
	swing.call()
	check(p._iron_skin_active, "then casts again")
	check(not p._trigger_busy, "(never left busy)")

	# A triggered cast does not trigger another: Frost Nova is a crit-capable area hit
	GameState.set_slot_trigger(0, "frost_nova")
	await get_tree().create_timer(0.6).timeout
	swing.call()
	check(not p._trigger_busy and float(p._triggers[0].cd) > 0.0, "a triggered cast that crits does not loop")

	# One hit with a projectile (an arrow) crits too
	GameState.set_slot_trigger(0, "iron_skin")
	await get_tree().create_timer(0.6).timeout
	p._iron_skin_active = false
	p._hit_one(dummy, p.skills[0])
	check(p._iron_skin_active, "a single hit (an arrow, a bolt) that crits casts it too")
	p.stats.remove_source("test")

	# Damage taken
	check(GameState.socket_support(1, 0, "rune_cast_hurt") and GameState.slot_meta(1) == hurt, "Cast when Damage Taken linked in slot 1")
	check(GameState.set_slot_trigger(1, "battle_cry"), "choosing Battle Cry")
	p._buff_active = false
	p.take_damage(1.0)
	check(p._buff_active, "taking damage casts Battle Cry")
	p._buff_active = false
	p.take_damage(1.0)
	check(not p._buff_active, "and it waits (%.1f s)" % RuneDef.TRIGGER_COOLDOWN.hurt)
	await get_tree().create_timer(1.1).timeout
	p.take_damage(1.0)
	check(p._buff_active, "then again")

	# Taking it out
	GameState.unsocket_support(0, 0)
	check(GameState.slot_meta(0) == null and GameState.slot_trigger(0) == "" and p._triggers.size() == 1,
		"unlinking the meta support ends its trigger (the other stays)")

	# The window: the skill cell and its dropdown
	GameState.gem_station = true
	var menu: GameMenu = main.menu if "menu" in main else null
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	menu = town.menu
	GameState.socket_support(0, 0, "rune_cast_crit")
	GameState.set_slot_trigger(0, "iron_skin")
	menu.open_vendor("jeweler")
	menu.show_panel("skills")
	await get_tree().process_frame
	var sp: SkillGemsPanel = menu.current_panel()
	check(sp.find_child("Trigger_0", true, false) != null and sp.find_child("Trigger_1", true, false) != null,
		"slots with a meta support show a skill cell")
	check(sp.find_child("Trigger_2", true, false) == null, "and others do not")
	sp._pick_trigger(0, Vector2(400, 300))
	await get_tree().process_frame
	var names := _rows(menu.item_tip()).map(func(b): return b.find_children("*", "Label", true, false)[0].text)
	check(names.any(func(t): return "Battle Cry" in t) and names.any(func(t): return "Frost Nova" in t), "the dropdown lists unlocked skills (%d)" % names.size())
	check(not names.any(func(t): return "Iron Skin" in t), "except the chosen one")
	check(menu.item_tip().find_children("*", "Button", true, false).any(func(b): return b.visible and "Take it out" in b.text), "and can clear it")
	if DisplayServer.get_name() != "headless":
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/meta_pick.png"))
	GameState.gem_station = false
	print("meta supports: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
