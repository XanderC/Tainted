extends Node2D
## Checks monster kinds and bosses: every skin they use exists, deeper rifts add kinds, set_kind
## applies the name, art and stats, and each boss has art. Run headless:
##   godot --headless --path . res://scratch/test_monster_kinds.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	for id in MonsterKinds.KINDS:
		var k: Dictionary = MonsterKinds.KINDS[id]
		var skins: Array = k.get("skins", [k.get("skin", "")])
		for s in skins:
			check(s == "" or not RigSprite.skin_parts(s).is_empty(), "%s: skin %s has art" % [id, s])
			if s != "":
				var parts := RigSprite.skin_parts(s)
				var weapon: Array = ["Bow", "Arrow"] if k.get("ranged", false) else ["Sword", "SlashFX"]
				var has_all := true
				for p in ["Head", "Face 01", "Body", "Left Arm", "Right Arm", "Left Hand", "Right Hand", "Left Leg", "Right Leg"] + weapon:
					has_all = has_all and parts.has(p)
				check(has_all, "%s: all parts of %s" % [id, s])
				check(RigSprite.is_archer_skin(s) == bool(k.get("ranged", false)), "%s: %s is on the right rig" % [id, s])
	for id in MonsterKinds.BOSSES:
		check(not RigSprite.skin_parts(MonsterKinds.BOSSES[id]["skin"]).is_empty(), "boss %s has art" % id)
	for npc in ["blacksmith", "merchant", "stash_keeper", "battlemaster", "jeweler", "sage"]:
		check(not RigSprite.skin_parts(npc).is_empty(), "NPC %s has art" % npc)

	check(MonsterKinds.pool(1).size() < MonsterKinds.pool(10).size(), "deeper rifts add kinds")
	check(not MonsterKinds.pool(1).has("ghost_knight") and MonsterKinds.pool(10).has("ghost_knight"), "ghost knights only deep")

	# Archers: the archer rig, which shoots where the sword rig slashes
	var r := RigSprite.new()
	r.skin = "elf_archer_1"
	add_child(r)
	check(r.rig_dir == RigSprite.ARCHER_RIG, "an archer skin uses the archer rig")
	check(r.anim_name_for("Slashing") == "Shooting" and r.anim_name_for("Walking") == "Walking", "Slashing plays as Shooting")
	var sw := RigSprite.new()
	add_child(sw)
	check(sw.anim_name_for("Slashing") == "Slashing" and sw.anim_name_for("Shooting") == "", "the sword rig keeps its own")
	var ar := Enemy.new()
	ar.set_kind("bandit_archer")
	check(ar.ranged and RigSprite.is_archer_skin(ar.skin), "an archer kind shoots and has archer art")
	ar.free()

	var e := Enemy.new()
	e.max_hp = 100.0
	e.speed = 100.0
	e.touch_damage = 10.0
	e.set_kind("orc")
	check(e.display_name == "Orc" and e.skin == "orc", "set_kind names and dresses it")
	check(absf(e.max_hp - 140.0) < 0.01 and absf(e.touch_damage - 12.5) < 0.01, "set_kind scales its stats")
	e.make_elite(MonsterAffix.Tier.ELITE, [] as Array[String])
	check(e.display_name == "Elite Orc", "an elite keeps its kind's name (%s)" % e.display_name)
	e.free()

	print("monster kinds: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
