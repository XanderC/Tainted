extends Node2D
## Gems in 8 Diablo 3 style tiers: names, strength never falls, an old Perfect gem is a Star gem of
## the same worth, an old Sapphire is a Ruby, every tier's icon exists, combining goes to the top and
## stops there, and the 33 rune icons are all there. Run:
##   godot --headless --path . res://scratch/test_gem_tiers.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	check(GemDef.MAX_TIER == 8 and GemDef.TIER_NAMES.size() == 8, "8 tiers")
	check(GemDef.TYPES.size() == 5 and not GemDef.TYPES.has("sapphire"), "five gem types, no Sapphire")
	for type in GemDef.TYPES:
		var last := -1.0
		check(GemDef.TYPES[type].values.size() == 8, "%s has 8 values" % type)
		for tier in range(1, 9):
			var id := GemDef.make_id(type, tier)
			var g := GemDef.info(id)
			check(not g.is_empty() and float(g.value) > last, "%s is stronger than the tier below" % id)
			last = float(g.value)
			check(ResourceLoader.exists("res://assets/icons/gems/%s.png" % id), "%s has its icon" % id)
			check(GemDef.icon(id) != null, "%s has a texture" % id)
			check(GemDef.next_id(id) == (GemDef.make_id(type, tier + 1) if tier < 8 else ""), "%s combines up (not past the top)" % id)
			check(not GemDef.combine_cost_of(id).is_empty(), "%s has a combine cost" % id)
	check(GemDef.info("ruby_1").name == "Chipped Ruby" and GemDef.info("topaz_3").name == "Topaz", "names")
	check(GemDef.info("emerald_5").name == "Star Emerald" and GemDef.info("diamond_8").name == "Flawless Royal Diamond", "top names")
	check(GemDef.info("ruby_5").text == "+55 Max Life", "an old Perfect Ruby keeps its 55 life")
	check(GemDef.current_id("sapphire_4") == "ruby_4" and GemDef.info("sapphire_4").type == "ruby", "an old Sapphire is a Ruby")
	check(GameState._migrate_gems({"sapphire_2": 2, "ruby_2": 3, "emerald_1": 1}) == {"ruby_2": 5, "emerald_1": 1}, "saved gems are renamed and added up")
	for i in range(100):
		var id := GemDef.random_drop(8)
		check(not GemDef.info(id).is_empty(), "a drop is a real gem: %s" % id)
	check(SocketRune.LADDER.size() == 33, "33 runes")
	for rank in range(1, 34):
		check(ResourceLoader.exists("res://assets/icons/runes/%d.png" % rank), "rune %d has its icon" % rank)
	print("gem tiers: ", "ok" if fails == 0 else "%d failed" % fails)
	get_tree().quit(fails)
