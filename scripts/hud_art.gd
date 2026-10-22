class_name HudArt
extends RefCounted
## The HUD's art (the CraftPix RPG & MMO UI pack, in assets/ui/hud, from tools/import_mmo_ui.py)
## and where each frame's round opening is, so fills, icons and cooldowns can be drawn inside it. Frames are placed by their opening,
## not their corner, so a button's position is where its icon goes.

const DIR := "res://assets/ui/hud/"

## Each frame's opening: centre (in the texture's own pixels) and radius.
const HOLES := {
	"globe_bg": [Vector2(128, 125), 119.0],  # the life / resource orb
	"abl_bg": [Vector2(138, 138), 120.0],  # the main attack's button
	"abm_bg": [Vector2(113, 113), 100.0],  # the other skills' buttons
	"joy_bg": [Vector2(188, 188), 170.0],
}

static var _cache := {}


static func tex(name: String) -> Texture2D:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".png")
	return _cache[name]


## Draws frame `name` so its opening is centred on `at`, `s` times its size; returns the opening's radius.
static func frame(ci: CanvasItem, name: String, at: Vector2, s := 1.0, tint := Color.WHITE) -> float:
	var t := tex(name)
	var h: Array = HOLES[name]
	var c: Vector2 = h[0]
	ci.draw_texture_rect(t, Rect2(at - c * s, t.get_size() * s), false, tint)
	return float(h[1]) * s


## Draws `name` centred on `at`, `diameter` px across.
static func disc(ci: CanvasItem, name: String, at: Vector2, diameter: float, tint := Color.WHITE) -> void:
	ci.draw_texture_rect(tex(name), Rect2(at - Vector2(diameter, diameter) * 0.5, Vector2(diameter, diameter)), false, tint)


## Draws `name` centred on `at`, `s` times its own size.
static func centred(ci: CanvasItem, name: String, at: Vector2, s := 1.0, tint := Color.WHITE) -> void:
	var t := tex(name)
	ci.draw_texture_rect(t, Rect2(at - t.get_size() * s * 0.5, t.get_size() * s), false, tint)


## A pie of `frac` (0-1) clockwise from the top, filling a circle: the cooldown sweep.
static func sweep(ci: CanvasItem, c: Vector2, r: float, frac: float, col := Color(0, 0, 0, 0.65)) -> void:
	if frac <= 0.02:
		return
	if frac >= 0.98:
		ci.draw_circle(c, r, col)  # a whole pie's ends meet: a polygon that can't be drawn
		return
	var pts := PackedVector2Array([c])
	for i in 25:
		pts.append(c + Vector2.from_angle(-PI / 2.0 + TAU * frac * float(i) / 24.0) * r)
	ci.draw_colored_polygon(pts, col)


## A horizontal bar stretched to `rect` with its end caps kept undistorted: `cap` is the cap's width
## in texture pixels. `frac` shows only that share of it from the left.
static func bar(ci: CanvasItem, name: String, rect: Rect2, cap: float, frac := 1.0, tint := Color.WHITE) -> void:
	var t := tex(name)
	var ts := t.get_size()
	var k := rect.size.y / ts.y  # the caps' scale
	var cw := cap * k
	var w := rect.size.x * clampf(frac, 0.0, 1.0)
	if w <= 0.5:
		return
	var x0 := rect.position.x
	var mid_w := rect.size.x - cw * 2.0
	# the left cap, then the middle (stretched), then the right cap, each cut off at `w`
	var parts := [
		[Rect2(0, 0, cap, ts.y), Rect2(x0, rect.position.y, cw, rect.size.y)],
		[Rect2(cap, 0, ts.x - cap * 2.0, ts.y), Rect2(x0 + cw, rect.position.y, mid_w, rect.size.y)],
		[Rect2(ts.x - cap, 0, cap, ts.y), Rect2(x0 + cw + mid_w, rect.position.y, cw, rect.size.y)],
	]
	for p in parts:
		var src: Rect2 = p[0]
		var dst: Rect2 = p[1]
		var right := dst.position.x + dst.size.x
		if dst.position.x >= x0 + w:
			continue
		if right > x0 + w:
			var keep := (x0 + w - dst.position.x) / dst.size.x
			src.size.x *= keep
			dst.size.x *= keep
		ci.draw_texture_rect_region(t, dst, src, tint)


## Text with a dark outline, centred on x within `width` (the HUD's readable-on-anything label).
static func label(ci: CanvasItem, pos: Vector2, text: String, size: int, col := Color.WHITE, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := ThemeDB.fallback_font
	ci.draw_string_outline(f, pos, text, align, width, size, 5, Color(0, 0, 0, 0.9))
	ci.draw_string(f, pos, text, align, width, size, col)
