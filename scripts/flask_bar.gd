class_name FlaskBar
extends Control
## The flask slots in the action bar at the bottom centre, between the globes (see HudBars): the UI pack's
## square bar slot for each of the two flasks (Path of Exile 2: a life flask, then a mana flask), each with its
## key in the corner. Tap one to drink it (also Q and E on a computer). A flask shows its icon with the share of
## charges it holds as a fill from the bottom, dimmed while it cannot be drunk; the charges and what a drink
## costs are written under the key. The rest of the row's slots are the charm slots (CharmBar draws those).

const KEYS := ["Q", "E"]

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
	for i in Player.FLASK_SLOTS:
		if HudBars.slot_rect(size, i).has_point(local):
			player.use_flask(i)
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	if player == null:
		return
	HudBars.draw_plate(self, size)  # the bar's backdrop, under the slots
	var slot := HudArt.tex("bar_slot")
	for i in HudBars.FLASK_COUNT:
		var r := HudBars.slot_rect(size, i)
		var flask := i < Player.FLASK_SLOTS
		# A dark backing so the row reads solid over the ground; a slot that is not a flask's is darker
		draw_rect(r.grow(-3.0), Color(0.07, 0.07, 0.08, 0.9))
		draw_texture_rect(slot, r, false, Color.WHITE if flask else Color(0.45, 0.43, 0.46))
		if not flask:
			continue
		var it: ItemInstance = player.flasks[i]
		if it != null:
			var frac := player.flask_charge_fraction(i)
			var ready := player.flask_ready(i)
			var inner := r.grow(-4.0)
			if it.base.icon != null:
				draw_texture_rect(it.base.icon, r.grow(-6.0), false, Color.WHITE if ready else Color(1, 1, 1, 0.45))
			# The charges it holds, as a tint rising from the bottom, and the empty share shaded from the top
			var empty := inner.size.y * (1.0 - frac)
			draw_rect(Rect2(inner.position, Vector2(inner.size.x, empty)), Color(0, 0, 0, 0.55))
			HudArt.label(self, Vector2(r.position.x, r.position.y + 14.0), "%d" % int(it.charges_now()), 11,
				Color(0.93, 0.90, 0.82) if ready else Color(0.9, 0.5, 0.45), r.size.x - 6.0, HORIZONTAL_ALIGNMENT_RIGHT)
		HudArt.label(self, Vector2(r.position.x, r.end.y - 5.0), KEYS[i], 12, Color(0.93, 0.90, 0.82), r.size.x - 6.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
