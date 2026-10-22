class_name LootPickup
extends Node2D
## An item lying on the ground, Diablo / Path of Exile style: a name plate in the item's rarity
## colour (currency on the ground has one too: CurrencyPickup). Walking over it does nothing; tap (or click) the plate to pick it up. When it's out of
## reach the player walks over first. The scene it lies in takes it (take_loot(pickup) -> bool on
## the nearest ancestor that has it), so each scene decides bag / equip / upgrade prompt.
## Plates near each other stack upwards instead of overlapping (layout()).

const REACH := 90.0  # how close the player must be to take it
const PLATE_GAP := 2.0
const PLATE_FONT := 15

var item: ItemInstance
var delay := 0.0  # kept for spawners; a tap always works

var _plate: Button
var _msg := ""
var _msg_t := 0.0

static var _layout_dirty := true


func _ready() -> void:
	add_to_group("pickups")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_plate = make_plate(item.display_name, ItemInstance.RARITY_COLORS[item.rarity], request_pickup)
	add_child(_plate)
	_layout_dirty = true


func _exit_tree() -> void:
	_layout_dirty = true


## A name plate for something on the ground (an item, currency: CurrencyPickup): its name in `col`,
## pressed to pick it up.
static func make_plate(text: String, col: Color, on_press: Callable) -> Button:
	var plate := Button.new()
	plate.text = text
	plate.focus_mode = Control.FOCUS_NONE
	plate.add_theme_font_size_override("font_size", PLATE_FONT)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		plate.add_theme_color_override(st, col)
	plate.add_theme_color_override("font_hover_color", col.lightened(0.35))
	plate.add_theme_stylebox_override("normal", _plate_box(Color(0, 0, 0, 0.72)))
	plate.add_theme_stylebox_override("hover", _plate_box(Color(0.16, 0.14, 0.20, 0.85), col))
	plate.add_theme_stylebox_override("pressed", _plate_box(Color(0.24, 0.20, 0.28, 0.9), col))
	plate.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	plate.pressed.connect(on_press)
	return plate


static func _plate_box(bg: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _process(delta: float) -> void:
	delay = maxf(delay - delta, 0.0)
	if _layout_dirty:
		layout(get_tree())
	if _msg_t > 0.0:
		_msg_t -= delta
		queue_redraw()
	elif item.is_unique():
		queue_redraw()  # animated light beam


## Tapped: take it if the player is close enough, otherwise walk over and then take it.
func request_pickup() -> void:
	var p := GameState.player
	if not is_instance_valid(p) or p.dead:
		return
	if p.global_position.distance_to(global_position) <= REACH:
		_take()
	else:
		p.walk_to(global_position, REACH * 0.8, func():
			if is_instance_valid(self) and is_inside_tree():
				_take()
		)


func _take() -> void:
	var n := get_parent()
	while n != null and not n.has_method("take_loot"):
		n = n.get_parent()
	if n != null and not n.take_loot(self):
		say("Not enough room")


## A short message over the item (e.g. no room in the bag).
func say(msg: String) -> void:
	_msg = msg
	_msg_t = 1.6
	queue_redraw()


## Places every plate above its item, moving one up while it would overlap a plate already
## placed (nearest the bottom of the screen first), like Diablo's item labels.
static func layout(tree: SceneTree) -> void:
	_layout_dirty = false
	var all: Array = tree.get_nodes_in_group("pickups").filter(func(p): return p._plate != null)
	all.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
	var placed: Array[Rect2] = []
	for p in all:
		var sz: Vector2 = p._plate.get_combined_minimum_size()
		var r := Rect2(p.global_position + Vector2(-sz.x * 0.5, -48.0 - sz.y), sz)
		for tries in 40:
			var hit := -1
			for i in placed.size():
				if placed[i].grow(PLATE_GAP * 0.5).intersects(r):
					hit = i
					break
			if hit == -1:
				break
			r.position.y = placed[hit].position.y - sz.y - PLATE_GAP
		placed.append(r)
		p._plate.size = sz
		p._plate.position = r.position - p.global_position


## True when a screen position (viewport coordinates) is over an item's plate, so the
## joystick leaves that touch to the plate.
static func plate_at(vp: Viewport, screen_pos: Vector2) -> bool:
	var world := vp.get_canvas_transform().affine_inverse() * screen_pos
	for p in vp.get_tree().get_nodes_in_group("pickups"):
		if p._plate != null and p._plate.visible and p._plate.get_global_rect().has_point(world):
			return true
	return false


func _draw() -> void:
	var col: Color = ItemInstance.RARITY_COLORS[item.rarity]
	if item.is_unique():
		# Legendary / Set items: a pulsing pillar of light so they can't be missed
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
		for i in 4:
			var w := 26.0 - i * 6.0
			draw_rect(Rect2(-w * 0.5, -260, w, 250), Color(col, 0.07 * pulse * (i + 1)))
		draw_set_transform(Vector2(0, -6), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, 40.0, Color(col, 0.30 * pulse))
		draw_set_transform(Vector2.ZERO)
	var box := Rect2(-22, -34, 44, 44)
	draw_rect(box, Color(0, 0, 0, 0.55))
	if item.base.icon != null:
		draw_texture_rect(item.base.icon, Rect2(-20, -32, 40, 40), false)
	else:
		draw_rect(Rect2(-9, -18, 18, 18), item.base.color)
	draw_rect(box, col, false, 3.0)
	if _msg_t > 0.0:
		var f := ThemeDB.fallback_font
		draw_string_outline(f, Vector2(-80, 30), _msg, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 4, Color.BLACK)
		draw_string(f, Vector2(-80, 30), _msg, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color(1.0, 0.45, 0.45))
