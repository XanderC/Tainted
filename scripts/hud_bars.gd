class_name HudBars
extends Control
## Health and Adrenaline/Mana bars (top-left) plus a thin experience bar along the bottom edge.
## Add to a CanvasLayer and set `player`; it fills the screen but ignores input.

const BAR_W := 300.0
const BAR_H := 22.0
const XP_H := 8.0

var player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var font := ThemeDB.fallback_font
	var max_hp := player.stats.get_stat("max_life")
	var cd := player.class_def

	# Level badge
	var badge_c := Vector2(36, 42)
	draw_circle(badge_c, 26.0, Color(0.08, 0.06, 0.10, 0.9))
	draw_arc(badge_c, 26.0, 0.0, TAU, 32, Color(0.95, 0.80, 0.40), 2.5)
	draw_string(font, Vector2(badge_c.x - 26, badge_c.y + 8), str(GameState.level),
			HORIZONTAL_ALIGNMENT_CENTER, 52, 22, Color(1.0, 0.92, 0.6))

	var x := 70.0
	_bar(Rect2(x, 16, BAR_W, BAR_H), player.hp / maxf(max_hp, 1.0), Color(0.80, 0.12, 0.12),
			"%d / %d" % [int(player.hp), int(max_hp)])
	_bar(Rect2(x, 16 + BAR_H + 6, BAR_W, BAR_H), player.resource / maxf(player.max_resource(), 1.0), cd.power_color,
			"%s  %d / %d" % [cd.power_name, int(player.resource), int(player.max_resource())])

	# Experience along the bottom edge
	var need := GameState.xp_to_next(GameState.level)
	var xp_rect := Rect2(0, size.y - XP_H, size.x, XP_H)
	draw_rect(xp_rect, Color(0.05, 0.04, 0.07, 0.85))
	draw_rect(Rect2(xp_rect.position, Vector2(size.x * clampf(GameState.xp / need, 0.0, 1.0), XP_H)), Color(0.65, 0.40, 1.0))
	draw_string(font, Vector2(8, size.y - XP_H - 4), "Lv %d   XP %d / %d" % [GameState.level, int(GameState.xp), int(need)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.75, 1.0, 0.85))


func _bar(r: Rect2, frac: float, col: Color, label: String) -> void:
	draw_rect(r.grow(2.0), Color(0.0, 0.0, 0.0, 0.75))
	draw_rect(r, col.darkened(0.75))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y * 0.35)), Color(1, 1, 1, 0.15))
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + r.size.y - 5), label,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color.WHITE)
