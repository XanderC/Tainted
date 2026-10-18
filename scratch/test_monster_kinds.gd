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
				check(RigSprite.skin_parts(s).size() == RigSprite.SKIN_PARTS.size(), "%s: all parts of %s" % [id, s])
	for id in MonsterKinds.BOSSES:
		check(not RigSprite.skin_parts(MonsterKinds.BOSSES[id]["skin"]).is_empty(), "boss %s has art" % id)
	for npc in ["blacksmith", "merchant", "stash_keeper", "battlemaster", "jeweler", "sage"]:
		check(not RigSprite.skin_parts(npc).is_empty(), "NPC %s has art" % npc)

	check(MonsterKinds.pool(1).size() < MonsterKinds.pool(10).size(), "deeper rifts add kinds")
	check(not MonsterKinds.pool(1).has("ghost_knight") and MonsterKinds.pool(10).has("ghost_knight"), "ghost knights only deep")

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
