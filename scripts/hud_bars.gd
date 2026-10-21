class_name HudBars
extends Control
## The life orb (left) and Adrenaline/Mana orb (right) at the bottom centre, with the flask row
## between them (drawn by FlaskBar) and the experience bar above it.
## Add to a CanvasLayer and set `player`; it fills the screen but ignores input.

const ORB_S := 0.72  # the orb frame's scale
const FLASK_S := 0.75  # a flask frame's scale
const FLASK_COUNT := 5  # the row always has room for every slot a belt can open
const FLASK_GAP := 4.0
const FILL_S := 0.742  # the fill disc, a touch under the orb opening
const XP_H := 14.0

var player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


static func flask_width() -> float:
	return HudArt.tex("frame_flask").get_width() * FLASK_S


## Centre of the opening of flask slot i, for a screen of `screen` px.
static func flask_centre(screen: Vector2, i: int) -> Vector2:
	var step := flask_width() + FLASK_GAP
	var x0 := screen.x * 0.5 - step * (FLASK_COUNT - 1) * 0.5
	return Vector2(x0 + step * i, screen.y - 60.0)


## Centre of the opening of the life orb (left) or the resource orb (right).
static func orb_centre(screen: Vector2, right: bool) -> Vector2:
	var half_row := (flask_width() + FLASK_GAP) * FLASK_COUNT * 0.5
	var dx := half_row + 79.0
	return Vector2(screen.x * 0.5 + (dx if right else -dx), screen.y - 72.0)


func _draw() -> void:
	if player == null:
		return
	var max_hp := player.stats.get_stat("max_life")
	var cd := player.class_def
	_orb(orb_centre(size, false), false, player.hp / maxf(max_hp, 1.0), Color(0.95, 0.16, 0.14), "%d" % int(player.hp))
	_orb(orb_centre(size, true), true, player.resource / maxf(player.max_resource(), 1.0), cd.power_color,
		"%d" % int(player.resource))

	# Experience above the flask row
	var need := GameState.xp_to_next(GameState.level)
	var row_w := (flask_width() + FLASK_GAP) * FLASK_COUNT - FLASK_GAP
	var xr := Rect2(size.x * 0.5 - row_w * 0.5, size.y - 120.0 - XP_H, row_w, XP_H)
	HudArt.bar(self, "xp_empty", xr, 40.0)
	var inner := xr.grow_individual(-xr.size.y * 0.4, -xr.size.y * 0.25, -xr.size.y * 0.4, -xr.size.y * 0.25)
	HudArt.bar(self, "xp_fill", inner, 20.0, clampf(GameState.xp / need, 0.0, 1.0))
	HudArt.label(self, Vector2(xr.position.x, xr.position.y - 3.0), "Lv %d   XP %d / %d" % [GameState.level, int(GameState.xp), int(need)],
		13, Color(0.88, 0.80, 1.0), xr.size.x)


## One orb: its frame, the fill rising to `frac` in `col`, then the rim and glass over it.
func _orb(c: Vector2, right: bool, frac: float, col: Color, text: String) -> void:
	var r := HudArt.frame(self, "orb_frame_right" if right else "orb_frame_left", c, ORB_S)
	var fill := HudArt.tex("orb_fill")
	var d := fill.get_width() * FILL_S
	frac = clampf(frac, 0.0, 1.0)
	if frac > 0.0:
		var src_h := fill.get_height() * frac
		var dst_h := d * frac
		draw_texture_rect_region(fill, Rect2(c.x - d * 0.5, c.y + d * 0.5 - dst_h, d, dst_h),
			Rect2(0, fill.get_height() - src_h, fill.get_width(), src_h), col)
	HudArt.disc(self, "orb_border", c, r * 2.0)
	HudArt.disc(self, "orb_glass", c, r * 2.0 * 0.97)
	HudArt.label(self, Vector2(c.x - r, c.y + 7.0), text, 20, Color(1, 0.97, 0.9), r * 2.0)
