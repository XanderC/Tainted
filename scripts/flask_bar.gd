class_name FlaskBar
extends Control
## Round HUD buttons for the flask slots the belt opens (Player.flask_slot_count), left to right,
## also on Q E R T F on a computer. Each shows its flask, the cooldown sweep, and its rarity on the
## rim. The bar grows to the left of its position, which is its bottom right corner.

const KEYS := ["Q", "E", "R", "T", "F"]

var player: Player
var button_size := 64.0
var gap := 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


## Slot i's button, in local coordinates (left of and above the origin).
func _rect(i: int, n: int) -> Rect2:
	var step := button_size + gap
	return Rect2(Vector2(-(n - i) * step + gap, -button_size), Vector2(button_size, button_size))


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pressed:
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	var n := player.flask_slot_count()
	for i in n:
		if _rect(i, n).has_point(local):
			player.use_flask(i)
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	if player == null:
		return
	var n := player.flask_slot_count()
	var font := ThemeDB.fallback_font
	for i in n:
		var r := _rect(i, n)
		var c := r.get_center()
		var rad := button_size * 0.5
		var it: ItemInstance = player.flasks[i]
		var frac := player.flask_cooldown_fraction(i)
		var ready := it != null and frac <= 0.0
		draw_circle(c, rad, Color(0, 0, 0, 0.65))
		var col: Color = it.base.color if it != null else Color(0.35, 0.35, 0.40)
		draw_circle(c, rad - 4.0, Color(col.r, col.g, col.b, 0.35 if ready else 0.12))
		if it != null and it.base.icon != null:
			var s := (rad - 8.0) * 2.0
			draw_texture_rect(it.base.icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false,
				Color.WHITE if ready else Color(1, 1, 1, 0.45))
		if frac > 0.02:
			var pts := PackedVector2Array([c])
			for k in 21:
				pts.append(c + Vector2.from_angle(-PI / 2.0 + TAU * frac * float(k) / 20.0) * (rad - 4.0))
			draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		var rim: Color = ItemInstance.RARITY_COLORS[it.rarity] if it != null else Color(0.4, 0.4, 0.45)
		draw_arc(c, rad - 2.0, 0.0, TAU, 40, Color(rim.r, rim.g, rim.b, 1.0 if ready else 0.45), 3.0)
		draw_string(font, r.position + Vector2(7, 16), KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
