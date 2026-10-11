class_name SkillButton
extends Control
## Round on-screen action button with cooldown sweep and hold-to-repeat attack.
## Index 0 is the primary Main Attack (large central button).

@export var button_size := 100.0

var player: Player
var index := 0

var _is_down := false
var _touch_id := -1


func _ready() -> void:
	if index == 0:
		button_size = 135.0
	else:
		button_size = 96.0
	size = Vector2(button_size, button_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.skills_changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	if _is_down and player != null and player.can_fight and not player.dead:
		player.use_skill(index)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and Rect2(global_position, size).has_point(event.position):
			_is_down = true
			_touch_id = event.index
			player.use_skill(index)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_id:
			_is_down = false
			_touch_id = -1
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Rect2(global_position, size).has_point(event.position):
			_is_down = true
			player.use_skill(index)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _is_down:
			_is_down = false


func _draw() -> void:
	if player == null or index >= player.skills.size():
		return
	var s := player.skills[index]
	if s == null:
		# Empty action-bar slot: faint ring so the layout stays readable
		draw_circle(Vector2(button_size, button_size) * 0.5, button_size * 0.5, Color(0, 0, 0, 0.35))
		draw_arc(Vector2(button_size, button_size) * 0.5, button_size * 0.5 - 3.0, 0.0, TAU, 40, Color(1, 1, 1, 0.15), 2.0)
		return
	var sz := button_size
	var c := Vector2(sz, sz) * 0.5
	var frac := player.cooldown_fraction(index)
	var col := s.get_effective_color()
	if not player.can_afford(index):
		col = col.darkened(0.6)  # not enough Adrenaline / Mana

	# Shadow / outer base
	draw_circle(c, sz * 0.5, Color(0, 0, 0, 0.65))

	# Filled inner circle with press pulse
	var inner_col := Color(col.r, col.g, col.b, 0.85 if frac <= 0.0 else 0.3)
	if _is_down:
		inner_col = inner_col.lightened(0.2)
	draw_circle(c, sz * 0.5 - 5.0, inner_col)

	# Cooldown sweep clock
	if frac > 0.02:
		var start := -PI / 2.0
		var pts := PackedVector2Array([c])
		for i in 21:
			pts.append(c + Vector2.from_angle(start + TAU * frac * float(i) / 20.0) * (sz * 0.5 - 5.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.70))

	# Border ring
	var border_col := Color(col.r, col.g, col.b, 1.0 if frac <= 0.0 else 0.4)
	if index == 0:
		# Main attack has a rich double gold/element ring
		draw_arc(c, sz * 0.5 - 3.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 0.9 if frac <= 0.0 else 0.4), 3.5)
		draw_arc(c, sz * 0.5 - 8.0, 0.0, TAU, 48, border_col, 2.0)
	else:
		draw_arc(c, sz * 0.5 - 3.0, 0.0, TAU, 40, border_col, 3.0)

	# Icon & Name
	var rune_prefix := ""
	for r in s.get_runes():
		if r.category == RuneDef.Category.TRANSMUTATION:
			rune_prefix = r.icon + " "
			break

	var title := rune_prefix + s.display_name
	var font_sz := 17 if index == 0 else 14
	draw_string(ThemeDB.fallback_font, Vector2(0, c.y + 6.0), title,
			HORIZONTAL_ALIGNMENT_CENTER, sz, font_sz, Color.WHITE)

	# Resource cost (or gain) under the name
	if s.resource_gain > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(0, c.y + 24.0), "+%d" % int(round(s.get_effective_gain())),
				HORIZONTAL_ALIGNMENT_CENTER, sz, 12, player.class_def.power_color.lightened(0.3))
	elif s.resource_cost > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(0, c.y + 24.0), "%d" % int(round(player.skill_cost(s))),
				HORIZONTAL_ALIGNMENT_CENTER, sz, 12, player.class_def.power_color.lightened(0.3))

	# Badge label in corner: "MAIN" or slot number
	var tag := "MAIN" if index == 0 else str(index)
	draw_string(ThemeDB.fallback_font, Vector2(12, 22), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.5, 0.85) if index == 0 else Color(1, 1, 1, 0.6))
