class_name ItemTip
extends Control
## An item's card as a tooltip that works by touch: shown where you tapped (beside the finger, kept
## on screen), it stays until you tap anywhere outside it, and that tap still goes on to whatever
## is under it, so tapping or dragging other items carries on as usual. Given an item to compare
## with (what is worn in its slot), that card is shown beside it, further from the finger.
## Add it to a CanvasLayer (or full-screen Control at the origin) above the window it explains,
## then show_card().

const WIDTH := 330.0
const OFFSET := 26.0  ## from the finger, so the card doesn't sit under it
const GAP := 8.0  ## between the card and the one it is compared with

var item: ItemInstance = null  ## what it shows (null when hidden)
var compare: ItemInstance = null  ## the item shown beside it to compare with (null for none)
var _main: PanelContainer
var _body: VBoxContainer
var _cmp: PanelContainer
var _cmp_body: VBoxContainer
var _close: BaseButton
var _shown := 0  # which show this is, so a late placement of an older one is ignored


func _init() -> void:
	visible = false
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = _card_panel()
	_body = _main.get_child(0)
	_cmp = _card_panel()
	_cmp_body = _cmp.get_child(0)
	_close = UIKit.close_button(0.65)  # over the card's top right corner rather than a row of its own
	_close.pressed.connect(close)
	add_child(_close)


func _card_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UIKit.window_box(12, Color.WHITE, false)
	# Clear of the frame's art: the text would otherwise sit on its edge
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_bottom = 20.0
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(WIDTH, 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	p.add_child(body)
	add_child(p)
	return p


## Shows `it`'s card at screen point `at`, its requirements judged by `have` (empty: yours).
## `extra` (optional) adds lines or buttons under the card: Callable(parent: VBoxContainer).
## `against` (optional) is shown beside it to compare with, both cards marking each stat with
## `deltas` (UIKit.equip_deltas: green if the tapped item has more, red if less).
func show_card(it: ItemInstance, at: Vector2, have := {}, extra := Callable(), against: ItemInstance = null, deltas := {}) -> void:
	item = it
	compare = against
	_shown += 1
	var mine := _shown
	UIKit.clear(_body)
	UIKit.item_card(_body, it, true, deltas, have)
	if extra.is_valid():
		extra.call(_body)
	UIKit.clear(_cmp_body)
	_cmp.visible = against != null
	if against != null:
		var l := UIKit.label("EQUIPPED", 12, Color(0.60, 0.55, 0.48))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cmp_body.add_child(l)
		UIKit.item_card(_cmp_body, against, true, deltas, have)
	_present(at, mine)


## Shows a card of anything else (a skill gem, say) at `at`: `build` fills it,
## Callable(parent: VBoxContainer).
func show_content(at: Vector2, build: Callable) -> void:
	item = null
	compare = null
	_shown += 1
	var mine := _shown
	UIKit.clear(_body)
	build.call(_body)
	UIKit.clear(_cmp_body)
	_cmp.visible = false
	_present(at, mine)


func _present(at: Vector2, mine: int) -> void:
	# Laid out off screen first: its height is only known once its text has been measured
	modulate.a = 0.0
	visible = true
	_main.position = Vector2(-4000, -4000)
	_cmp.position = Vector2(-4000, -4000)
	await get_tree().process_frame
	await get_tree().process_frame
	if mine != _shown or not visible:
		return
	_place(at)
	modulate.a = 1.0
	# Wrapped text can settle its height a frame later: size it again
	await get_tree().process_frame
	if mine == _shown and visible:
		_place(at)


func close() -> void:
	visible = false
	item = null
	compare = null


## Beside the tap: to its right if there is room (the compared card further right), else its left
## (that card further left); then the pair nudged fully on screen.
func _place(at: Vector2) -> void:
	var screen := get_viewport_rect().size
	var s := _fit(_main)
	var c := _fit(_cmp) if _cmp.visible else Vector2.ZERO
	var both := s.x + (c.x + GAP if _cmp.visible else 0.0)
	var right := at.x + OFFSET + both <= screen.x - 8.0
	var x := at.x + OFFSET if right else at.x - OFFSET - s.x
	var cx := x + s.x + GAP if right else x - GAP - c.x
	# Keep the pair on screen together
	var left_edge := minf(x, cx) if _cmp.visible else x
	var right_edge := maxf(x + s.x, cx + c.x) if _cmp.visible else x + s.x
	var dx := 0.0
	if right_edge > screen.x - 8.0:
		dx = screen.x - 8.0 - right_edge
	if left_edge + dx < 8.0:
		dx = 8.0 - left_edge
	var top := at.y - s.y * 0.3
	_main.position = Vector2(x + dx, clampf(top, 8.0, maxf(8.0, screen.y - s.y - 8.0)))
	if _cmp.visible:
		_cmp.position = Vector2(cx + dx, clampf(_main.position.y, 8.0, maxf(8.0, screen.y - c.y - 8.0)))  # tops level
	_close.position = _main.position + Vector2(s.x - _close.size.x - 6.0, 6.0)


func _fit(p: PanelContainer) -> Vector2:
	p.size = Vector2(WIDTH, 0)
	p.size = p.get_combined_minimum_size()
	return p.size


## A tap outside the cards closes them, and isn't swallowed: it still reaches what was tapped.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if pressed and not _main.get_global_rect().has_point(event.position) \
			and not (_cmp.visible and _cmp.get_global_rect().has_point(event.position)):
		close()
