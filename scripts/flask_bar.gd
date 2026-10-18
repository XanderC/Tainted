class_name FlaskBar
extends Control
## The flask row at the bottom centre, between the life and resource orbs (see HudBars): a frame
## for each of the five slots, the ones the belt opens (Player.flask_slot_count) lit. Tap one to
## drink it (also Q E R T F on a computer). Each shows its flask, the cooldown sweep, and its
## rarity on the rim.

const KEYS := ["Q", "E", "R", "T", "F"]

var player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # add it to the HUD's CanvasLayer


func _process(_delta: float) -> void:
	queue_redraw()


## Slot i's tap area, in screen coordinates.
func _rect(i: int) -> Rect2:
	var c := HudBars.flask_centre(size, i)
	var w := HudBars.flask_width()
	return Rect2(c.x - w * 0.5, c.y - 54.0, w, 112.0)


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pressed:
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	for i in player.flask_slot_count():
		if _rect(i).has_point(local):
			player.use_flask(i)
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	if player == null:
		return
	var n := player.flask_slot_count()
	for i in HudBars.FLASK_COUNT:
		var c := HudBars.flask_centre(size, i)
		var open := i < n
		var it: ItemInstance = player.flasks[i]
		var frac := player.flask_cooldown_fraction(i)
		var ready := open and it != null and frac <= 0.0
		var r := HudArt.frame(self, "frame_flask", c, HudBars.FLASK_S, Color.WHITE if open else Color(0.4, 0.38, 0.42))  # a locked slot is dark, not see-through
		if open and it != null:
			var col: Color = it.base.color
			draw_circle(c, r, Color(col.r, col.g, col.b, 0.30 if ready else 0.10))
			if it.base.icon != null:
				var s := r * 2.0
				draw_texture_rect(it.base.icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false,
					Color.WHITE if ready else Color(1, 1, 1, 0.45))
			HudArt.sweep(self, c, r, frac)
			var rim: Color = ItemInstance.RARITY_COLORS[it.rarity]
			draw_arc(c, r - 1.0, 0.0, TAU, 36, Color(rim.r, rim.g, rim.b, 1.0 if ready else 0.45), 2.0)
		if open:
			HudArt.label(self, Vector2(c.x - 20.0, c.y + r + 15.0), KEYS[i], 11, Color(1, 1, 1, 0.75), 40.0)
