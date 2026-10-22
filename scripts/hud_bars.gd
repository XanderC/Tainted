class_name HudBars
extends Control
## The action bar at the bottom centre, laid out as the UI pack's: the life globe (left) and the
## Adrenaline/Mana globe (right) sitting on the bottom edge, the row of square flask slots between
## them (drawn by FlaskBar, on the bar's plate: HudBars.draw_plate) that runs from globe to globe,
## the experience line along the top of the row with a tag over its end, and a curl at the foot of each globe.
## Add to a CanvasLayer and set `player`; it fills the screen but ignores input.

const FLASK_COUNT := 5  # the row always has room for every slot a belt can open
const SLOT := 58.0  # a flask slot's side
const SLOT_GAP := 3.0
const BOTTOM := 6.0  # the row's gap above the screen's bottom edge
const ORB_R := 68.0  # a globe's radius (its fill)
const ORB_DROP := 0.25  # how much of a globe hangs below the screen's edge (of its radius)
const XP_H := 7.0
const CURL_S := 0.55  # the curls' scale

var player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


## The flask row's width.
static func row_width() -> float:
	return SLOT * FLASK_COUNT + SLOT_GAP * (FLASK_COUNT - 1)


## Flask slot i's square, for a screen of `screen` px.
static func slot_rect(screen: Vector2, i: int) -> Rect2:
	var x0 := screen.x * 0.5 - row_width() * 0.5
	return Rect2(x0 + (SLOT + SLOT_GAP) * i, screen.y - BOTTOM - SLOT, SLOT, SLOT)


## Centre of the life globe (left) or the resource globe (right): its rim against the row's end.
static func orb_centre(screen: Vector2, right: bool) -> Vector2:
	var dx := row_width() * 0.5 + ORB_R + 4.0
	return Vector2(screen.x * 0.5 + (dx if right else -dx), screen.y - ORB_R * (1.0 - ORB_DROP))


func _draw() -> void:
	if player == null:
		return
	var max_hp := player.stats.get_stat("max_life")
	var cd := player.class_def
	_orb(orb_centre(size, false), false, player.hp / maxf(max_hp, 1.0), Color.WHITE, "%d" % int(player.hp))
	_orb(orb_centre(size, true), true, player.resource / maxf(player.max_resource(), 1.0), cd.power_color,
		"%d" % int(player.resource))
	_curls()
	_xp()


## The bar's backdrop behind the slots and the experience line, drawn on `ci` (FlaskBar draws it under
## its slots; the globes, drawn after, cover its ends): the pack's window panel from one globe's
## middle to the other's, its bottom edge below the screen.
static func draw_plate(ci: CanvasItem, screen: Vector2) -> void:
	var l := orb_centre(screen, false).x
	var r := orb_centre(screen, true).x
	var top := slot_rect(screen, 0).position.y - XP_H - 12.0
	var sb := StyleBoxTexture.new()
	sb.texture = UIKit.mmo("window")
	sb.set_texture_margin_all(12.0)
	ci.draw_style_box(sb, Rect2(l, top, r - l, screen.y + 14.0 - top))


## The curls at the foot of the globes, in the wedge between each globe and the row's end.
func _curls() -> void:
	var t := HudArt.tex("bar_curl_left")
	var s := t.get_size() * CURL_S
	var row_l := size.x * 0.5 - row_width() * 0.5
	var y := size.y - s.y
	draw_texture_rect(t, Rect2(Vector2(row_l - s.x + 2.0, y), s), false)
	draw_texture_rect(HudArt.tex("bar_curl_right"), Rect2(Vector2(row_l + row_width() - 2.0, y), s), false)


## The experience line along the top of the row, with a tag over the end of its fill:
## level, how far through it, and the experience itself.
func _xp() -> void:
	var need := GameState.xp_to_next(GameState.level)
	var frac := clampf(GameState.xp / maxf(need, 1.0), 0.0, 1.0)
	var top := slot_rect(size, 0).position.y
	var xr := Rect2(size.x * 0.5 - row_width() * 0.5, top - XP_H - 2.0, row_width(), XP_H)
	HudArt.bar(self, "xp_bg", xr, 8.0)
	var inner := xr.grow_individual(-3.0, -1.5, -3.0, -1.5)
	HudArt.bar(self, "xp_bar_fill", inner, 2.0, frac)
	# The tag, its arrow pointing down at the fill's end (kept over the line)
	var text := "Lv %d   %d%%   %d / %d" % [GameState.level, int(frac * 100.0), int(GameState.xp), int(need)]
	var f := ThemeDB.fallback_font
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	var ax := inner.position.x + inner.size.x * frac
	var tx := clampf(ax - tw * 0.5, xr.position.x - 20.0, xr.end.x + 20.0 - tw)
	var tag := Rect2(tx, xr.position.y - 26.0, tw, 20.0)
	var sb := StyleBoxTexture.new()
	sb.texture = HudArt.tex("xp_tag")
	sb.set_texture_margin_all(6.0)
	draw_style_box(sb, tag)
	var arrow := HudArt.tex("xp_tag_arrow")
	draw_texture_rect(arrow, Rect2(Vector2(ax - 6.0, tag.end.y - 1.0), Vector2(12, 7)), false, Color(0.20, 0.21, 0.21))
	draw_string(f, Vector2(tag.position.x, tag.position.y + 14.5), text, HORIZONTAL_ALIGNMENT_CENTER, tw, 12,
		Color(0.92, 0.90, 0.84))


## One globe: its gold-rimmed frame, the empty glass sphere, and the fill rising to `frac`. Life is
## the pack's red sphere; the resource globe its grey one in `col` (the class's power colour).
func _orb(c: Vector2, right: bool, frac: float, col: Color, text: String) -> void:
	var r := HudArt.frame(self, "globe_bg", c, ORB_R / float(HudArt.HOLES["globe_bg"][1]))
	var d := r * 2.0
	HudArt.disc(self, "globe_fill_empty", c, d)
	var fill := HudArt.tex("globe_fill_grey" if right else "globe_fill_red")
	frac = clampf(frac, 0.0, 1.0)
	if frac > 0.0:
		var src_h := fill.get_height() * frac
		var dst_h := d * frac
		draw_texture_rect_region(fill, Rect2(c.x - d * 0.5, c.y + d * 0.5 - dst_h, d, dst_h),
			Rect2(0, fill.get_height() - src_h, fill.get_width(), src_h), col)
	# The value in the part of the globe above the screen's edge
	HudArt.label(self, Vector2(c.x - r, c.y + 2.0), text, 22, Color(1, 0.97, 0.9), r * 2.0)
