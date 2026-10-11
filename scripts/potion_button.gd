class_name PotionButton
extends Control
## Round HUD button that drinks the potion in the potion slot (also: Q key, handled by Player).
## Shows the potion, how many are left, and the cooldown sweep.

var player: Player
var button_size := 78.0


func _ready() -> void:
	size = Vector2(button_size, button_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed and Rect2(global_position, size).has_point(event.position):
		player.drink_potion()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if player == null:
		return
	var c := size * 0.5
	var r := button_size * 0.5
	var pid := GameState.potion_slot
	var count := GameState.potion_count(pid) if pid != "" else 0
	var frac := player.potion_cooldown_fraction()
	draw_circle(c, r, Color(0, 0, 0, 0.65))
	var p := PotionDef.info(pid, player.class_def.power_name)
	var col: Color = p.get("color", Color(0.4, 0.4, 0.4))
	var usable := count > 0 and frac <= 0.0
	draw_circle(c, r - 5.0, Color(col.r, col.g, col.b, 0.35 if usable else 0.12))
	var tex := PotionDef.icon(pid) if pid != "" else null
	if tex != null:
		var s := (r - 10.0) * 2.0
		draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false,
			Color.WHITE if usable else Color(1, 1, 1, 0.4))
	if frac > 0.02:
		var pts := PackedVector2Array([c])
		for i in 21:
			pts.append(c + Vector2.from_angle(-PI / 2.0 + TAU * frac * float(i) / 20.0) * (r - 5.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	draw_arc(c, r - 3.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 1.0 if usable else 0.4), 3.0)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(0, button_size - 6.0), str(count), HORIZONTAL_ALIGNMENT_RIGHT, button_size - 8.0, 18, 5, Color.BLACK)
	draw_string(font, Vector2(0, button_size - 6.0), str(count), HORIZONTAL_ALIGNMENT_RIGHT, button_size - 8.0, 18,
		Color.WHITE if count > 0 else Color(0.9, 0.4, 0.4))
	draw_string(font, Vector2(10, 20), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
