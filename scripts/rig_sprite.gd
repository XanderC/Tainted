class_name RigSprite
extends Node2D
## A skeletal character made of sprites, animated from baked rig data (see RigData).
## The node's origin is the character's feet, and the art faces right (flipped for left).
##
## Equipment is drawn as extra layers:
##   weapon -> swaps the image of the rig's Sword object, which is bolted to the hand
##   helmet -> overlay that follows the Head
##   chest  -> overlays that follow the Body and both arms
## Gear art lives at  res://assets/gear/<slot>/<gear id>/<Object name>.png

signal one_shot_finished(anim_name: String)

const STRIDE := RigData.STRIDE
const GEAR_ROOT := "res://assets/gear"
## mode "replace": swap the texture of one rig object.
## mode "overlay": extra sprites that copy the transform of the listed objects and draw just above
## them (or above the objects listed in "above", e.g. the helmet must sit over the Face too).
const GEAR_LAYERS := {
	"weapon": {"mode": "replace", "objects": ["Sword"]},
	"helmet": {"mode": "overlay", "objects": ["Head"], "above": ["Head", "Face 01"]},
	"chest": {"mode": "overlay", "objects": ["Body", "Right Arm", "Left Arm"]},
}

@export var rig_dir := "res://assets/rigs/zombie"
@export var base_scale := 0.2
## true (player): the weapon is shown whenever one is equipped and hidden otherwise.
## false (enemies): the animation data decides; this pack only shows the sword while slashing.
@export var weapon_from_gear := false
## Update every Nth baked frame. 2 = 30 fps, cheaper for crowds.
@export var frame_skip := 1

var rig: RigData
var current_anim := ""

var _n := 0
var _sprites: Array[Sprite2D] = []
var _tex_of: Array = []
var _pivot_of := PackedVector2Array()
var _z := PackedFloat32Array()
var _sword_i := -1
var _slash_i := -1
var _weapon_equipped := false
var _weapon_tex: Texture2D = null
var _gear := {}
var _overlays: Array = []  # {sprite, obj, slot, z2}

var _time := 0.0
var _speed := 1.0
var _loop_anim := "Idle"
var _loop_speed := 1.0
var _oneshot := ""
var _oneshot_hold := false
var _held := false
var _facing_left := false
var _pulse := 1.0


static func draw_shadow(ci: CanvasItem, radius: float) -> void:
	ci.draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.38))
	ci.draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ready() -> void:
	# The art is drawn large and shown small; mipmaps stop it shimmering.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rig = RigData.load_rig(rig_dir)
	if rig == null:
		set_process(false)
		return
	_n = rig.objects.size()
	_sword_i = rig.objects.find("Sword")
	_slash_i = rig.objects.find("SlashFX")
	var first_anim: Dictionary = rig.animations.values()[0]
	for i in _n:
		# Draw order never changes between frames in this rig, so sort the children once.
		_z.append(first_anim["data"][i * STRIDE + 7])
		var s := Sprite2D.new()
		s.centered = false
		add_child(s)
		_sprites.append(s)
		_tex_of.append(null)
		_pivot_of.append(Vector2(-1, -1))
	_update_scale()
	_reorder()
	_start(_loop_anim, 1.0)


# ---------------------------------------------------------------- animation API

## Locomotion-style animation that repeats. Ignored while a one-shot is playing, and resumed after it.
func play_loop(anim_name: String, speed := 1.0) -> void:
	if rig == null or not rig.animations.has(anim_name):
		return
	_loop_anim = anim_name
	_loop_speed = speed
	if _oneshot != "":
		return
	if current_anim == anim_name:
		_speed = speed
		return
	_start(anim_name, speed)


## Attack / hurt / death. Interrupts what is playing, then returns to the loop (or holds the last frame).
func play_once(anim_name: String, speed := 1.0, hold_last := false) -> void:
	if rig == null or not rig.animations.has(anim_name):
		return
	_oneshot = anim_name
	_oneshot_hold = hold_last
	_held = false
	_start(anim_name, speed)


func is_busy() -> bool:
	return _oneshot != ""


func oneshot_name() -> String:
	return _oneshot


func randomize_phase() -> void:
	if rig != null and current_anim != "":
		_time = randf() * rig.animations[current_anim]["length"]


func set_facing(dir_x: float) -> void:
	if absf(dir_x) < 0.05:
		return
	var left := dir_x < 0.0
	if left != _facing_left:
		_facing_left = left
		_update_scale()


func pulse(amount := 0.15, duration := 0.3) -> void:
	var t := create_tween()
	t.tween_method(_set_pulse, 1.0, 1.0 + amount, duration * 0.4)
	t.tween_method(_set_pulse, 1.0 + amount, 1.0, duration * 0.6)


func _set_pulse(v: float) -> void:
	_pulse = v
	_update_scale()


func _update_scale() -> void:
	var s := base_scale * _pulse
	scale = Vector2(-s if _facing_left else s, s)


func _start(anim_name: String, speed: float) -> void:
	current_anim = anim_name
	_speed = speed
	_time = 0.0
	if _n > 0:
		_apply_frame()


func _process(delta: float) -> void:
	if rig == null or current_anim == "":
		return
	var length: float = rig.animations[current_anim]["length"]
	_time += delta * _speed
	if _oneshot != "" and current_anim == _oneshot:
		if _time >= length:
			if _oneshot_hold:
				_time = length - 0.001
				if not _held:
					_held = true
					one_shot_finished.emit(_oneshot)
			else:
				var finished := _oneshot
				_oneshot = ""
				_start(_loop_anim, _loop_speed)
				one_shot_finished.emit(finished)
				return
	else:
		_time = fposmod(_time, length)
	_apply_frame()


# ---------------------------------------------------------------- gear

## slot: "weapon" | "helmet" | "chest". gear_id "" clears it. gear_id is the ItemBase id.
func set_gear(slot: String, gear_id: String) -> void:
	if rig == null or not GEAR_LAYERS.has(slot) or _gear.get(slot, "") == gear_id:
		return
	_gear[slot] = gear_id
	var cfg: Dictionary = GEAR_LAYERS[slot]
	if cfg["mode"] == "replace":
		_weapon_equipped = gear_id != ""
		# No art for this weapon yet: it falls back to the rig's own sword image.
		_weapon_tex = _gear_texture(slot, gear_id, cfg["objects"][0])
	else:
		for ov in _overlays.duplicate():
			if ov["slot"] == slot:
				remove_child(ov["sprite"])
				ov["sprite"].queue_free()
				_overlays.erase(ov)
		if gear_id != "":
			for obj_name in cfg["objects"]:
				var tex := _gear_texture(slot, gear_id, obj_name)
				var obj_i := rig.objects.find(obj_name)
				if tex == null or obj_i < 0:
					continue
				var s := Sprite2D.new()
				s.centered = false
				s.texture = tex
				add_child(s)
				var top := _z[obj_i]
				for above in cfg.get("above", []):
					var ai := rig.objects.find(above)
					if ai >= 0:
						top = maxf(top, _z[ai])
				_overlays.append({"sprite": s, "obj": obj_i, "slot": slot, "z2": top * 2.0 + 1.0})
		_reorder()
	if current_anim != "":
		_apply_frame()


func gear_id(slot: String) -> String:
	return _gear.get(slot, "")


## Number of overlay sprites currently drawn for a slot (for tests / debugging).
func overlay_count(slot: String) -> int:
	var c := 0
	for ov in _overlays:
		if ov["slot"] == slot:
			c += 1
	return c


func _gear_texture(slot: String, gear_id_: String, obj_name: String) -> Texture2D:
	if gear_id_ == "":
		return null
	var path := "%s/%s/%s/%s.png" % [GEAR_ROOT, slot, gear_id_, obj_name]
	return load(path) if ResourceLoader.exists(path) else null


func _reorder() -> void:
	var entries: Array = []
	for i in _n:
		entries.append([_z[i] * 2.0, _sprites[i]])
	for ov in _overlays:
		entries.append([ov["z2"], ov["sprite"]])
	entries.sort_custom(func(a, b): return a[0] < b[0])
	for k in entries.size():
		move_child(entries[k][1], k)


# ---------------------------------------------------------------- per-frame placement

func _apply_frame() -> void:
	var anim: Dictionary = rig.animations[current_anim]
	var frames: int = anim["frames"]
	var idx := int(_time * rig.fps)
	if _held:
		idx = frames - 1
	idx = mini(idx, frames - 1)
	if frame_skip > 1:
		idx -= idx % frame_skip
	var data: PackedFloat32Array = anim["data"]
	var base := idx * _n * STRIDE

	for i in _n:
		var o := base + i * STRIDE
		var s := _sprites[i]
		var fi := int(data[o])
		if fi < 0:
			s.visible = false
			continue
		var alpha := data[o + 6]
		var tex: Texture2D = rig.textures[fi]
		if i == _sword_i:
			if _weapon_tex != null:
				tex = _weapon_tex
			if weapon_from_gear:
				alpha = 1.0 if _weapon_equipped else 0.0
		elif i == _slash_i and weapon_from_gear and not _weapon_equipped:
			alpha = 0.0
		if alpha <= 0.001:
			s.visible = false
			continue
		s.visible = true
		var pivot := Vector2(data[o + 8], data[o + 9])
		if tex != _tex_of[i] or pivot != _pivot_of[i]:
			s.texture = tex
			var sz := tex.get_size()
			s.offset = Vector2(-sz.x * pivot.x, -sz.y * (1.0 - pivot.y))
			_tex_of[i] = tex
			_pivot_of[i] = pivot
		s.position = Vector2(data[o + 1], data[o + 2])
		s.rotation = data[o + 3]
		s.scale = Vector2(data[o + 4], data[o + 5])
		s.modulate.a = alpha

	for ov in _overlays:
		var o2: int = base + int(ov["obj"]) * STRIDE
		var s2: Sprite2D = ov["sprite"]
		if int(data[o2]) < 0 or data[o2 + 6] <= 0.001:
			s2.visible = false
			continue
		s2.visible = true
		var sz2 := s2.texture.get_size()
		s2.offset = Vector2(-sz2.x * data[o2 + 8], -sz2.y * (1.0 - data[o2 + 9]))
		s2.position = Vector2(data[o2 + 1], data[o2 + 2])
		s2.rotation = data[o2 + 3]
		s2.scale = Vector2(data[o2 + 4], data[o2 + 5])
		s2.modulate.a = data[o2 + 6]
