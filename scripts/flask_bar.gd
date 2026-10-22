class_name FlaskBar
extends Control
## The flask slots in the action bar at the bottom centre, between the globes (see HudBars): the
## UI pack's square bar slot for each of the five, the ones the belt opens (Player.flask_slot_count)
## lit, each with its key in the corner. Tap one to drink it (also Q E R T F on a computer). Each
## shows its flask, dimmed and shaded from the top while it recharges.

const KEYS := ["Q", "E", "R", "T", "F"]

var player: Player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # add it to the HUD's CanvasLayer


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pressed:
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	for i in player.flask_slot_count():
		if HudBars.slot_rect(size, i).has_point(local):
			player.use_flask(i)
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	if player == null:
		return
	HudBars.draw_plate(self, size)  # the bar's backdrop, under the slots
	var n := player.flask_slot_count()
	var slot := HudArt.tex("bar_slot")
	for i in HudBars.FLASK_COUNT:
		var r := HudBars.slot_rect(size, i)
		var open := i < n
		# A dark backing so the row reads solid over the ground; a slot the belt doesn't open is darker
		draw_rect(r.grow(-3.0), Color(0.07, 0.07, 0.08, 0.9))
		draw_texture_rect(slot, r, false, Color.WHITE if open else Color(0.45, 0.43, 0.46))
		if not open:
			continue
		var it: ItemInstance = player.flasks[i]
		if it != null:
			var frac := player.flask_cooldown_fraction(i)
			var ready := frac <= 0.0
			if it.base.icon != null:
				draw_texture_rect(it.base.icon, r.grow(-6.0), false, Color.WHITE if ready else Color(1, 1, 1, 0.45))
			if not ready:
				# The share still recharging, shaded down from the top
				var inner := r.grow(-4.0)
				draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * frac)), Color(0, 0, 0, 0.6))
		HudArt.label(self, Vector2(r.position.x, r.end.y - 5.0), KEYS[i], 12, Color(0.93, 0.90, 0.82), r.size.x - 6.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
