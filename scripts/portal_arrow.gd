class_name PortalArrow
extends Control
## HUD arrow circling the screen centre, pointing at the maze portal while it is off screen,
## with the distance. Set `player` and `target` (a Node2D, or null to hide).

const ORBIT := 230.0

var player: Player
var target: Node2D = null
var label_text := "Portal"
var color := Color(0.80, 0.55, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(target) or not target.visible:
		return
	var to := target.global_position - player.global_position
	var dist := to.length()
	if dist < 420.0:
		return  # on screen already
	var dir := to / dist
	var c := size * 0.5 + dir * ORBIT
	var tip := c + dir * 22.0
	var side := dir.orthogonal() * 13.0
	draw_colored_polygon(PackedVector2Array([tip, c - dir * 6.0 + side, c - dir * 6.0 - side]), color)
	draw_polyline(PackedVector2Array([tip, c - dir * 6.0 + side, c - dir * 6.0 - side, tip]), Color.BLACK, 2.0)
	var font := ThemeDB.fallback_font
	var txt := "%s  %dm" % [label_text, int(dist / 64.0)]
	draw_string_outline(font, c + Vector2(-60, 34), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, 4, Color.BLACK)
	draw_string(font, c + Vector2(-60, 34), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, color)
