extends Node2D
## A picture of weapon looks in the hand (the folder after --out=, default scratch/): pack designs,
## characters' own weapons, unique looks, and bows on the archer rig.
##   godot --path . --resolution 1600x600 res://scratch/capture_weapon_looks.tscn -- --out=<folder>

const LOOKS := ["rusty_sword", "axe_3_4", "medieval_knight_weapon", "reaper_man_1_weapon", "devil_weapon",
	"citizen_women_1_weapon", "u_maelstrom_edge", "u_emberheart", "staff_7_5", "long_bow", "elf_archer_1_bow",
	"u_windpiercer", "u_hellrack"]


func _ready() -> void:
	var out := "res://scratch/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	RenderingServer.set_default_clear_color(Color(0.36, 0.44, 0.33))
	for i in LOOKS.size():
		var r := RigSprite.new()
		r.base_scale = 0.32
		r.weapon_from_gear = true
		r.rig_dir = RigSprite.rig_for_weapon(LOOKS[i])
		r.position = Vector2(70 + i * 120, 330)
		add_child(r)
		Appearance.apply(r, Appearance.default_look())
		r.set_gear("weapon", LOOKS[i])
		var l := Label.new()
		l.text = String(LOOKS[i]).replace("_weapon", "").replace("_", " ")
		l.add_theme_font_size_override("font_size", 11)
		l.position = r.position + Vector2(-55, 10)
		add_child(l)
	for f in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "weapon_looks.png")
	get_tree().quit()
