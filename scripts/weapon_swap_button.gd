class_name WeaponSwapButton
extends Control
## Small HUD button that swaps between weapon Set 1 and Set 2 (also: X key, handled by Player).

var player: Player
var button_size := Vector2(78, 46)


func _ready() -> void:
	size = button_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed and Rect2(global_position, size).has_point(event.position):
		player.swap_weapon_set()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if player == null:
		return
	HudArt.bar(self, "menu_btn", Rect2(Vector2.ZERO, size), 16.0)
	var font := ThemeDB.fallback_font
	var y := size.y * 0.5 + 6.0
	for i in 2:
		var active := player.active_set == i
		var x := 10.0 + i * 34.0
		draw_string(font, Vector2(x, y), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if active else 15,
			Color(1.0, 0.88, 0.45) if active else Color(0.6, 0.55, 0.5))
	draw_string(font, Vector2(24, y - 1.0), "⇄", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.80, 0.70))
