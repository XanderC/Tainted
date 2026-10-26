class_name RemoteAlly
extends Node2D
## Another player's hireling or summoned Ancient, as your game shows it (their RemotePlayer keeps
## it): how it looks, where it is and what it plays. It fights in its owner's game, where its hits
## go to the instance's host like its owner's do; here it is only seen.

const NAME_COLOR := Color(0.75, 0.85, 0.95)

var kind := "h"  ## "h" a hireling; "a0".."a2" one of the Ancients (Player.ANCIENTS)
var rig: RigSprite
var _target := Vector2.ZERO
var _facing := 1.0
var _anim := "Idle"
var _speed := 1.0
var _oneshot := ""


## `hl`: the owner's hireling as their looks describe it (Net.my_info "hl").
func setup(what: String, hl: Dictionary) -> void:
	kind = what
	add_to_group("remote_allies")
	var sh := Node2D.new()
	sh.draw.connect(func(): RigSprite.draw_shadow(sh, 20.0))
	add_child(sh)
	rig = RigSprite.new()
	rig.base_scale = 0.2
	rig.weapon_from_gear = true
	if kind == "h":
		var skin := String(hl.get("skin", ""))
		if skin in RemoteAlly.hireling_skins():
			rig.skin = skin
		add_child(rig)
		_dress(hl)
		var label := Label.new()
		label.text = String(hl.get("name", ""))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", NAME_COLOR)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 5)
		label.custom_minimum_size = Vector2(160, 0)
		label.position = Vector2(-80, -112)
		label.z_index = 5
		add_child(label)
	else:
		var a: Array = Player.ANCIENTS[clampi(int(kind.substr(1)), 0, Player.ANCIENTS.size() - 1)]
		rig.base_scale = 0.21
		rig.modulate = AncientAlly.GHOST
		add_child(rig)
		rig.set_gear("weapon", String(a[1]))
		rig.set_gear("helmet", "iron_helm")
		rig.set_gear("chest", "chain_mail")
	rig.play_loop("Idle")


## Its gear on the rig (as Hireling._dress): a dressed figure wears it all; an archer holds its bow.
func _dress(hl: Dictionary) -> void:
	var gear: Dictionary = hl.get("gear", {})
	if rig.skin == "":
		var w = gear.get("weapon")
		var want := RigSprite.rig_for_seen(String(w[0]) if w is Array else "", String(w[1]) if w is Array else "")
		if rig.rig_dir != want:  # a bow, a spear, a dagger, a weapon in both hands: its rig
			rig = RigSprite.swap_rig(rig, want)
			rig.play_loop("Idle")
		Appearance.apply(rig, hl.get("look", {}))
		for slot in Player.VISIBLE_SLOTS:
			var g = gear.get(slot)
			rig.set_gear(slot, String(g[0]) if g is Array else "", String(g[1]) if g is Array and slot in DyeDB.SLOTS else "")
		var off = gear.get("offhand")
		rig.set_offhand(String(off[0]) if off is Array else "", off is Array and bool(off[1]))
		return
	var bow = gear.get("weapon")
	var art := "res://assets/gear/weapon/%s/Bow.png" % (String(bow[0]) if bow is Array else "")
	var parts := RigSprite.skin_parts(rig.skin).duplicate()  # its own look, holding the bow
	if bow is Array and ResourceLoader.exists(art):
		parts["Bow"] = load(art)
	rig.set_part_overrides(parts)


## Where it is and what it plays: [kind, position, facing, animation, speed] (Net._ally_state).
func apply(e: Array) -> void:
	_target = e[1]
	_facing = float(e[2])
	var a := String(e[3])
	_speed = float(e[4])
	if a in ["Idle", "Walking", "Running", "Slashing in The Air", "Shooting"]:
		_anim = a
		_oneshot = ""
	elif a != _oneshot:
		_oneshot = a  # a swing or a leap: once
		rig.play_once(a, _speed)


func _process(delta: float) -> void:
	if position.distance_to(_target) > 400.0:
		position = _target  # it caught its owner up at once
	else:
		position = position.lerp(_target, 1.0 - exp(-12.0 * delta))
	rig.set_facing(_facing)
	rig.play_loop(_anim, _speed)


## The hireling looks a game may ask for (an archer's skin): nothing else is loaded.
static func hireling_skins() -> Array:
	var out: Array = []
	for t in HirelingDB.TYPES.values():
		out.append_array(t.get("skins", []))
	return out
