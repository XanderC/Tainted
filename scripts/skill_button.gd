class_name SkillButton
extends Control
## Round on-screen action button with cooldown sweep and hold-to-repeat attack.
## Index 0 is the primary Main Attack (the large round button); 1-5 are smaller ones round it.
## Each is placed by the centre of its opening (CENTRES, from the screen's bottom-right corner).

const MAIN_S := 0.45  # scale of the main attack's frame
const SMALL_R := 42.0  # radius of the other buttons' openings
const SMALL_S := SMALL_R / 100.0  # their frame's scale (its opening is 100 px)
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
	return float(HudArt.HOLES["abl_bg"][1]) * MAIN_S if i == 0 else SMALL_R


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
	HudArt.frame(self, "abl_bg" if index == 0 else "abm_bg", c, MAIN_S if index == 0 else SMALL_S)
	if s == null:
		return  # an empty slot: just its frame, so the layout stays readable
	var frac := player.cooldown_fraction(index)
	var col := s.get_effective_color()
	var blocked := player.skill_block_reason(s) != ""  # its weapon isn't in hand, or not enough of its attribute
	if not player.can_use(index):
		col = col.darkened(0.6)  # that, or not enough Adrenaline / Mana

	# The skill's painted icon filling the button (or a coloured disc without one), dimmed while it
	# can't be used, with the cooldown sweeping over it
	var inner_r := r - 3.0
	var tex := SkillIcons.texture(s.id)
	var usable := frac <= 0.0 and player.can_use(index)
	if tex != null:
		var shade := Color.WHITE if usable else Color(0.45, 0.45, 0.48)
		if _is_down:
			shade = Color(1.25, 1.25, 1.25)
		SkillIcons.draw_round(self, tex, c, inner_r, shade)
	else:
		var inner_col := Color(col.r, col.g, col.b, 0.85 if frac <= 0.0 else 0.3)
		if _is_down:
			inner_col = inner_col.lightened(0.2)
		draw_circle(c, inner_r, inner_col)
	HudArt.sweep(self, c, inner_r, frac, Color(0, 0, 0, 0.70))

	# A glow round it in the skill's colour while it is ready
	if frac <= 0.0:
		HudArt.disc(self, "abm_glow", c, r * 2.0 * 0.98, Color(col.r, col.g, col.b, 0.9).lightened(0.2))

	# An elemental support linked to it: its icon as a small badge at the top right
	for rn in s.get_runes():
		if rn.category == RuneDef.Category.TRANSMUTATION:
			var bt := rn.get_icon()
			var bc := c + Vector2(r * 0.68, -r * 0.68)
			var br := maxf(r * 0.28, 10.0)
			draw_circle(bc, br + 2.0, Color(0, 0, 0, 0.8))
			SkillIcons.draw_round(self, bt, bc, br)
			break

	# Without a painted icon the name says what it is
	if tex == null:
		HudArt.label(self, Vector2(0, c.y + 6.0), s.display_name, 17 if index == 0 else 13, Color.WHITE, button_size)

	# Resource cost (or gain) at the bottom
	var cost_txt := ""
	if s.resource_gain > 0.0:
		cost_txt = "+%d" % int(round(s.get_effective_gain()))
	elif s.resource_cost > 0.0:
		cost_txt = "%d" % int(round(player.skill_cost(s)))
	if cost_txt != "":
		var pool_col := HudBars.MANA_COLOR if s.uses_mana() else HudBars.ADRENALINE_COLOR
		var pc := pool_col.lightened(0.35) if player.can_afford(index) else Color(1.0, 0.45, 0.4)
		HudArt.label(self, Vector2(0, c.y + r * 0.82), cost_txt, 15 if index == 0 else 13, pc, button_size)
	if blocked:  # a lock over it
		HudArt.label(self, Vector2(0, c.y - 10.0), "🔒", 20 if index == 0 else 16, Color(1, 1, 1, 0.9), button_size)

	# The slot number (keys 1-5) at the top left; the main attack needs none
	if index > 0:
		HudArt.label(self, c + Vector2(-r * 0.95, -r * 0.5), str(index), 13, Color(1, 1, 1, 0.8), r * 0.6)
