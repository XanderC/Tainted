class_name VirtualJoystick
extends Control
## Floating left-thumb joystick. Touch anywhere on the left 45% of the screen.
## Works with mouse on desktop because emulate_touch_from_mouse is enabled.

@export var radius := 110.0

var output := Vector2.ZERO  # -1..1 on each axis

var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	# The inventory pauses the game; drop any finger that was mid-drag so the
	# stick can't get stuck when play resumes.
	if what == NOTIFICATION_PAUSED:
		_touch_index = -1
		output = Vector2.ZERO
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var vp := get_viewport_rect().size
		# A touch on an item's name plate is for the plate (picking it up), not the stick
		if event.pressed and _touch_index == -1 and event.position.x < vp.x * 0.45 				and not LootPickup.plate_at(get_viewport(), event.position):
			_touch_index = event.index
			_center = event.position
			_knob = event.position
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			output = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var d: Vector2 = (event.position - _center).limit_length(radius)
		_knob = _center + d
		output = d / radius
		queue_redraw()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _touch_index == -1:
		return
	draw_circle(_center, radius, Color(1, 1, 1, 0.10))
	draw_arc(_center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
	draw_circle(_knob, 42.0, Color(1, 1, 1, 0.35))
