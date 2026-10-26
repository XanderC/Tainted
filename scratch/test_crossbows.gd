extends Node2D
## Tests and visual verification of the 7 new crossbows.
## Run with: godot --headless --path . -s res://scratch/test_crossbows.gd
## or with visuals: godot --path . --resolution 1600x720 res://scratch/test_crossbows.tscn

const CROSSBOW_IDS := [
	"hunting_crossbow",
	"light_crossbow",
	"arbalest",
	"repeating_crossbow",
	"siege_crossbow",
	"runic_arbalest",
	"dragon_crossbow"
]

func _ready() -> void:
	print("--- Testing Crossbows Integration ---")
	
	# 1. Test bases in LootGenerator
	for id in CROSSBOW_IDS:
		var base: ItemBase = LootGenerator.base_by_id(id)
		assert(base != null, "Base not found: %s" % id)
		assert(base.weapon_type == "crossbow", "Expected weapon_type 'crossbow', got '%s'" % base.weapon_type)
		assert(base.two_handed == true, "Expected two_handed == true")
		assert(base.slot == "weapon", "Expected slot 'weapon'")
		assert(base.icon != null, "Expected base.icon to be loaded for %s" % id)
		assert(base.bag_size() == Vector2i(2, 3), "Expected 2x3 bag size, got %s" % [base.bag_size()])
		var reqs := Attributes.requirements(base)
		print("Crossbow base '%s' (lvl %d, dmg %.0f) reqs: %s, icon size: %s" % [
			base.display_name, base.drop_level, base.implicit_value, reqs, base.icon.get_size()
		])
	
	# 2. Test rig assignment
	for id in CROSSBOW_IDS:
		var want_rig := RigSprite.rig_for_weapon(id)
		assert(want_rig == RigSprite.ARCHER_RIG, "Crossbows should map to ARCHER_RIG, got: %s" % want_rig)
	
	# 3. Test unique items
	var buriza = UniqueItems.LEGENDARIES.get("buriza")
	assert(buriza != null, "Buriza unique item definition missing")
	var hellrack = UniqueItems.LEGENDARIES.get("hellrack")
	assert(hellrack != null, "Hellrack unique item definition missing")
	print("Unique crossbows verified: Buriza (%s), Hellrack (%s)" % [buriza["base"], hellrack["base"]])

	# 4. Visual rendering of characters holding each crossbow
	RenderingServer.set_default_clear_color(Color(0.28, 0.25, 0.22))
	var rigs: Array = []
	for i in CROSSBOW_IDS.size():
		var id = CROSSBOW_IDS[i]
		var r := RigSprite.new()
		r.base_scale = 0.35
		r.weapon_from_gear = true
		r.rig_dir = RigSprite.ARCHER_RIG
		r.position = Vector2(110 + (i % 4) * 390, 260 + (i / 4) * 320)
		add_child(r)
		Appearance.apply(r, Appearance.default_look())
		r.set_gear("weapon", id)
		r.play_loop("Idle")
		rigs.append(r)
		
		# Label
		var lbl := Label.new()
		var base = LootGenerator.base_by_id(id)
		lbl.text = "%s (Lvl %d)" % [base.display_name, base.drop_level]
		lbl.position = Vector2(r.position.x - 70, r.position.y + 40)
		add_child(lbl)

	for i in 6:
		await get_tree().process_frame
	
	for r in rigs:
		r.play_once("Shooting", 0.8)
	
	await get_tree().create_timer(0.15).timeout
	var img = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path("res://scratch/crossbows_in_game.png"))
		print("Saved visual verification screenshot to scratch/crossbows_in_game.png")
	
	print("--- All Crossbow Tests Passed Successfully! ---")
	get_tree().quit(0)
