class_name SkillButton
extends Control
## Round on-screen action button with cooldown sweep and hold-to-repeat attack.
## Index 0 is the primary Main Attack (the large ornate frame); 1-5 are rings round it.
## Each is placed by the centre of its opening (CENTRES, from the screen's bottom-right corner).

const MAIN_S := 0.9  # scale of the main attack's frame
const SMALL_R := 42.0  # radius of the other buttons' openings
const CENTRES := {
	0: Vector2(-98, -150),
	1: Vector2(-226, -72),
	2: Vector2(-228, -176),
	3: Vector2(-140, -266),
	4: Vector2(-336, -130),
	5: Vector2(-322, -236),
}

@export var button_size := 100.0

var player: Player
var index := 0

var _is_down := false
var _touch_id := -1


## Radius of button i's opening, the part that is its icon and its tap area.
static func hole_radius(i: int) -> float:
	return float(HudArt.HOLES["frame_main"][1]) * MAIN_S if i == 0 else SMALL_R


## Where button i's control goes, relative to the bottom-right corner.
static func pad_position(i: int) -> Vector2:
	return CENTRES[i] - Vector2.ONE * hole_radius(i)


func _ready() -> void:
	button_size = hole_radius(index) * 2.0
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
	var c := Vector2(button_size, button_size) * 0.5
	var r := button_size * 0.5
	if index == 0:
		HudArt.frame(self, "frame_main", c, MAIN_S)
	else:
		draw_circle(c, r, Color(0.03, 0.025, 0.03, 0.9))
	if s == null:
		# Empty action-bar slot: just the frame, so the layout stays readable
		if index != 0:
			HudArt.disc(self, "icon_ring", c, r * 2.0 + 8.0, Color(1, 1, 1, 0.85))
			draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(0.62, 0.50, 0.32, 0.6), 2.0)
		return
	var frac := player.cooldown_fraction(index)
	var col := s.get_effective_color()
	if not player.can_afford(index):
		col = col.darkened(0.6)  # not enough Adrenaline / Mana

	# Filled inner circle with press pulse
	var inner_col := Color(col.r, col.g, col.b, 0.85 if frac <= 0.0 else 0.3)
	if _is_down:
		inner_col = inner_col.lightened(0.2)
	var inner_r := r - 3.0
	draw_circle(c, inner_r, inner_col)
	HudArt.sweep(self, c, inner_r, frac, Color(0, 0, 0, 0.70))

	# Rim
	var rim := Color(col.r, col.g, col.b, 1.0 if frac <= 0.0 else 0.4)
	if index == 0:
		draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 0.9 if frac <= 0.0 else 0.4), 3.0)
	else:
		HudArt.disc(self, "icon_ring", c, r * 2.0 + 8.0)
		HudArt.disc(self, "ring_gray", c, r * 2.0 - 2.0, rim.lightened(0.15))

	# Icon & Name
	var rune_prefix := ""
	for rn in s.get_runes():
		if rn.category == RuneDef.Category.TRANSMUTATION:
			rune_prefix = rn.icon + " "
			break

	var title := rune_prefix + s.display_name
	var font_sz := 17 if index == 0 else 13
	HudArt.label(self, Vector2(0, c.y + 6.0), title, font_sz, Color.WHITE, button_size)

	# Resource cost (or gain) under the name
	if s.resource_gain > 0.0:
		HudArt.label(self, Vector2(0, c.y + 24.0), "+%d" % int(round(s.get_effective_gain())), 12,
			player.class_def.power_color.lightened(0.3), button_size)
	elif s.resource_cost > 0.0:
		HudArt.label(self, Vector2(0, c.y + 24.0), "%d" % int(round(player.skill_cost(s))), 12,
			player.class_def.power_color.lightened(0.3), button_size)

	# Badge label at the top: "MAIN" or slot number
	var tag := "MAIN" if index == 0 else str(index)
	HudArt.label(self, Vector2(0, c.y - r * 0.5), tag, 13, Color(1, 0.9, 0.5, 0.9) if index == 0 else Color(1, 1, 1, 0.65),
		button_size)
