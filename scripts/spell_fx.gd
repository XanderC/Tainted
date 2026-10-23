class_name SpellFx
extends AnimatedSprite2D
## A hand-drawn spell effect (tools/import_spells.py: a strip of frames in assets/fx/<id>.png, sized
## in fx.json): played once where it's put (spawn), or kept on a character a while (attach: a
## shield, Whirlwind's typhoon, a molten elite's flames). TUNE gives each its speed, its width on
## screen and whether it lies on the ground (under the characters) or stands over them.

## id: [frames a second, px across on screen, lies on the ground]
const TUNE := {
	"earth_fissure": [14, 320, true], "earth_spike": [20, 170, false], "ground_hit": [16, 280, true],
	"fire_explosion": [16, 240, false], "flame": [14, 110, true], "lightning_strike": [22, 130, false],
	"typhoon": [18, 250, false], "earth_shield": [16, 150, false], "fire_shield": [18, 170, false],
	"leaf_shield": [22, 230, false], "lightning_shield": [16, 140, false],
	"hit_physical": [26, 64, false], "hit_fire": [24, 64, false], "hit_cold": [24, 64, false],
	"hit_lightning": [26, 60, false], "hit_poison": [24, 70, false],
}
## The hit spark for each RuneDef.DamageType (PHYSICAL, COLD, FIRE, LIGHTNING, CHAOS)
const HITS := ["hit_physical", "hit_cold", "hit_fire", "hit_lightning", "hit_poison"]

static var _meta := {}
static var _frames := {}  # id -> SpriteFrames

var fx_id := ""
var _until := -1.0  # msec it fades out at (attached ones); -1: when its frames are done
var _fading := false


## Plays effect `id` once at `at` (world position) in `parent`; `size` scales its TUNE width.
static func spawn(parent: Node, id: String, at: Vector2, size := 1.0, flip := false, tint := Color.WHITE) -> SpellFx:
	var fx := _make(id, size)
	if fx == null or parent == null:
		return null
	fx.modulate = tint
	fx.flip_h = flip
	parent.add_child(fx)
	fx.global_position = at
	fx.animation_finished.connect(fx.queue_free)
	fx.play("default")
	return fx


## Keeps effect `id` on `target` (it follows) for `secs`: looping, or (`hold`) played once and held on
## its last frame (a shield forming, then up); then it fades. `lift` raises it off the feet.
## Calling it again while one is on keeps that one longer instead.
static func attach(target: Node2D, id: String, secs: float, size := 1.0, lift := 0.0, hold := false, alpha := 1.0) -> SpellFx:
	if target == null:
		return null
	for c in target.get_children():
		if c is SpellFx and c.fx_id == id and not c._fading:
			c.keep(secs)
			return c
	var fx := _make(id, size)
	if fx == null:
		return null
	if not hold:  # looping: its own copy of the (shared, once-through) frames
		fx.sprite_frames = fx.sprite_frames.duplicate()
		fx.sprite_frames.set_animation_loop("default", true)
	fx.position = Vector2(0, -lift)
	fx.modulate.a = alpha
	target.add_child(fx)
	fx.keep(secs)
	fx.play("default")
	return fx


## Stays on (an attached one) until `secs` from now, if that's later.
func keep(secs: float) -> void:
	_until = maxf(_until, Time.get_ticks_msec() + secs * 1000.0)


func _process(_delta: float) -> void:
	if _until >= 0.0 and not _fading and Time.get_ticks_msec() >= _until:
		_fading = true
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.3)
		t.tween_callback(queue_free)


static func _make(id: String, size: float) -> SpellFx:
	if not TUNE.has(id):
		return null
	var frames := _frames_of(id)
	if frames == null:
		return null
	var m: Dictionary = _meta[id]
	var tune: Array = TUNE[id]
	var fx := SpellFx.new()
	fx.fx_id = id
	fx.sprite_frames = frames
	fx.centered = false
	fx.offset = -Vector2(float(m.cx), float(m.cy))  # the original canvas's centre goes where it's put
	fx.scale = Vector2.ONE * float(tune[1]) * size / float(m.w)
	fx.z_index = -1 if tune[2] else 5
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return fx


static func _frames_of(id: String) -> SpriteFrames:
	if _frames.has(id):
		return _frames[id]
	if _meta.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/fx.json"))
		_meta = d if d is Dictionary else {}
	if not _meta.has(id) or not ResourceLoader.exists("res://assets/fx/%s.png" % id):
		return null
	var m: Dictionary = _meta[id]
	var strip: Texture2D = load("res://assets/fx/%s.png" % id)
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", float(TUNE[id][0]))
	sf.set_animation_loop("default", false)
	for i in int(m.frames):
		var a := AtlasTexture.new()
		a.atlas = strip
		a.region = Rect2(i * float(m.w), 0, float(m.w), float(m.h))
		sf.add_frame("default", a)
	_frames[id] = sf
	return sf
