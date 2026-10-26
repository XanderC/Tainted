extends Node2D
## Screenshots of the armour library (assets/gear/<slot>/catalog.json) worn on player figures, saved
## as armour_library_<n>.png in the folder after --out= (default scratch/): every 6th suit of armour
## with gloves and boots from the catalogs, half the figures holding a bow (the archer rig).
##   godot --path . --resolution 1600x900 res://scratch/capture_armour_library.tscn -- --out=<folder>

const COLS := 8


func _ready() -> void:
	var out := "res://scratch/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	RenderingServer.set_default_clear_color(Color(0.36, 0.44, 0.33))
	var cat := {}
	for slot in ["chest", "gloves", "boots"]:
		var ids: Array = load("res://assets/gear/%s/catalog.json" % slot).data.keys()
		ids.sort()
		cat[slot] = ids
	var chests: Array = cat.chest
	var picks := []
	for i in range(0, chests.size(), 6):
		picks.append(i)
	for k in picks.size():
		var i: int = picks[k]
		var j := k % (COLS * 3)
		var r := RigSprite.new()
		r.base_scale = 0.3
		r.weapon_from_gear = true
		var bow := "hunting_bow" if k % 2 == 1 else ""
		r.rig_dir = RigSprite.rig_for_weapon(bow)
		r.position = Vector2(100 + (j % COLS) * 195, 260 + (j / COLS) * 290)
		add_child(r)
		Appearance.apply(r, Appearance.default_look("male" if k % 3 else "female"))
		r.set_gear("chest", chests[i])
		r.set_gear("gloves", cat.gloves[i % cat.gloves.size()])
		r.set_gear("boots", cat.boots[i % cat.boots.size()])
		r.set_gear("weapon", bow)
		var l := Label.new()
		l.text = String(chests[i]).trim_suffix("_armour")
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.position = r.position + Vector2(-80, 8)
		add_child(l)
		if j == COLS * 3 - 1 or k == picks.size() - 1:
			for f in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out + "armour_library_%d.png" % (k / (COLS * 3)))
			for c in get_children():
				c.queue_free()
			await get_tree().process_frame
	get_tree().quit()
