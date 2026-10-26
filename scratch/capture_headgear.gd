extends Node2D
## Screenshots of headgear on real rigs (saved in the folder after --out=, default scratch/):
##   headgear_bow.png   - the same look with and without a bow (sword rig / archer rig), bare, with
##                        hair, with a helmet and with a crown, and a scout skin with a helmet
##   headgear_<n>.png   - every piece in assets/gear/helmet/catalog.json, on a player figure
##   godot --path . --resolution 1600x900 res://scratch/capture_headgear.tscn -- --out=<folder>

const PER_SHOT := 40
const COLS := 10

var out := "res://scratch/"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	RenderingServer.set_default_clear_color(Color(0.33, 0.42, 0.30))
	var look := Appearance.default_look("male")
	look["beard"] = "full" if "full" in Appearance.options("beards") else Appearance.options("beards")[1]
	var rows := [["", "hunting_bow"], ["iron_helm", "hunting_bow"], ["royal_crown", "hunting_bow"], ["kettle_helm", "hunting_bow"]]
	var x := 120.0
	for r in rows:
		for w in ["", r[1]]:
			_figure(Vector2(x, 330), look, r[0], w)
			_label(Vector2(x, 360), "%s\n%s" % [r[0] if r[0] != "" else "bare", "bow" if w != "" else "sword rig"])
			x += 170.0
	var scout := RigSprite.new()
	scout.skin = "archer_guy"
	scout.base_scale = 0.45
	scout.position = Vector2(x, 330)
	add_child(scout)
	scout.set_gear("helmet", "iron_helm")
	_label(Vector2(x, 360), "scout skin\niron helm")
	await _shot("headgear_bow")
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame

	var cat: Dictionary = load(RigSprite.HEADGEAR_CATALOG).data
	var ids := cat.keys()
	ids.sort()
	for page in range(0, ids.size(), PER_SHOT):
		for k in range(page, mini(page + PER_SHOT, ids.size())):
			var j := k - page
			var pos := Vector2(80 + (j % COLS) * 155, 190 + (j / COLS) * 205)
			_figure(pos, look, ids[k], "")
			_label(pos + Vector2(0, 4), ids[k])
		await _shot("headgear_%d" % (page / PER_SHOT))
		for c in get_children():
			c.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _figure(pos: Vector2, look: Dictionary, helmet: String, weapon: String) -> void:
	var r := RigSprite.new()
	r.base_scale = 0.45
	r.weapon_from_gear = true
	r.rig_dir = RigSprite.rig_for_weapon(weapon)
	r.position = pos
	add_child(r)
	Appearance.apply(r, look)
	r.set_gear("helmet", helmet)
	r.set_gear("weapon", weapon)


func _label(pos: Vector2, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.size = Vector2(150, 40)
	l.position = pos - Vector2(75, 0)
	add_child(l)


func _shot(n: String) -> void:
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + n + ".png")
