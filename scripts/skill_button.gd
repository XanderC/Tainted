class_name SkillButton
extends Control
## Round on-screen skill button with a cooldown sweep. Tap to use.

const SZ := 110.0

var player: Player
var index := 0


func _ready() -> void:
	size = Vector2(SZ, SZ)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventScreenTouch and event.pressed:
		if Rect2(global_position, size).has_point(event.position):
			player.use_skill(index)


func _draw() -> void:
	if player == null or index >= player.skills.size():
		return
	var s := player.skills[index]
	var c := Vector2(SZ, SZ) * 0.5
	var frac := player.cooldown_fraction(index)
	draw_circle(c, SZ * 0.5, Color(0, 0, 0, 0.5))
	draw_circle(c, SZ * 0.5 - 6.0, Color(s.color.r, s.color.g, s.color.b, 0.8 if frac <= 0.0 else 0.3))
	if frac > 0.02:
		var start := -PI / 2.0
		var pts := PackedVector2Array([c])
		for i in 21:
			pts.append(c + Vector2.from_angle(start + TAU * frac * float(i) / 20.0) * (SZ * 0.5 - 6.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	draw_arc(c, SZ * 0.5 - 3.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(0, c.y + 5.0), s.display_name,
			HORIZONTAL_ALIGNMENT_CENTER, SZ, 18)
	draw_string(ThemeDB.fallback_font, Vector2(10, 22), str(index),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
