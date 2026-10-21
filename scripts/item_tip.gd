class_name ItemTip
extends PanelContainer
## An item's card as a tooltip that works by touch: shown where you tapped (beside the finger, kept
## on screen), it stays until you tap anywhere outside it, and that tap still goes on to whatever
## is under it, so tapping or dragging other items carries on as usual. Add it to a CanvasLayer
## (or full-screen Control) above the window it explains, then show_card().

const WIDTH := 330.0
const OFFSET := 26.0  ## from the finger, so the card doesn't sit under it

var item: ItemInstance = null  ## what it shows (null when hidden)
var _body: VBoxContainer
var _close: BaseButton
var _shown := 0  # which show this is, so a late placement of an older one is ignored


func _init() -> void:
	visible = false
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UIKit.window_box(12, Color.WHITE, false))
	custom_minimum_size = Vector2(WIDTH, 0)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)


## Shows `item`'s card at screen point `at`, its requirements judged by `have` (empty: yours).
## `extra` (optional) adds lines or buttons under the card: Callable(parent: VBoxContainer).
func show_card(it: ItemInstance, at: Vector2, have := {}, extra := Callable()) -> void:
	item = it
	_shown += 1
	var mine := _shown
	UIKit.clear(_body)
	UIKit.item_card(_body, it, true, {}, have)
	if extra.is_valid():
		extra.call(_body)
	if _close == null:
		# Over the card's top right corner rather than a row of its own
		_close = UIKit.close_button(0.65)
		_close.top_level = true
		_close.pressed.connect(close)
		add_child(_close)
	# Laid out off screen first: its height is only known once its text has been measured
	modulate.a = 0.0
	visible = true
	_close.visible = true
	position = Vector2(-4000, -4000)
	size = Vector2(WIDTH, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	if mine != _shown or not visible:
		return
	_place(at)
	modulate.a = 1.0


func close() -> void:
	visible = false
	item = null
	if _close != null:
		_close.visible = false


## Beside the tap: to its right if there is room, else its left; then nudged fully on screen.
func _place(at: Vector2) -> void:
	var screen := get_viewport_rect().size
	size = Vector2(WIDTH, 0)
	var s := get_combined_minimum_size()
	size = s
	var x := at.x + OFFSET if at.x + OFFSET + s.x <= screen.x - 8.0 else at.x - OFFSET - s.x
	var y := at.y - s.y * 0.3
	position = Vector2(clampf(x, 8.0, maxf(8.0, screen.x - s.x - 8.0)), clampf(y, 8.0, maxf(8.0, screen.y - s.y - 8.0)))
	_close.global_position = global_position + Vector2(s.x - _close.size.x - 6.0, 6.0)


## A tap outside closes it, and isn't swallowed: it still reaches what was tapped.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if pressed and not get_global_rect().has_point(event.position):
		close()
