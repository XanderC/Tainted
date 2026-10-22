class_name TownPortal
extends Node2D
## The way home once a rift is cleared: a blue-gold portal near where the boss fell, with a label like
## the loot's (LootPickup.make_plate, stacked with theirs). Tap the label: the player walks over and
## goes back to town (return_to_town on the nearest ancestor that has it). Walking near it does
## nothing, so gathering the loot round it never sends you home by accident.

const RADIUS := 52.0

var _plate: Button


func _ready() -> void:
	z_index = -1  # flat on the ground, under characters
	add_to_group("pickups")  # its label stacks with the loot's and the joystick leaves it alone
	_plate = LootPickup.make_plate("🏛 Town Portal", Color(0.55, 0.80, 1.0), request_enter)
	_plate.z_as_relative = false  # the portal lies under everything; its label stands with the loot's
	_plate.z_index = 1
	add_child(_plate)
	LootPickup._layout_dirty = true


func _exit_tree() -> void:
	LootPickup._layout_dirty = true


func _process(_delta: float) -> void:
	if LootPickup._layout_dirty:
		LootPickup.layout(get_tree())
	queue_redraw()


## Its label was tapped: walk over (if not there) and go through.
func request_enter() -> void:
	var p := GameState.player
	if not is_instance_valid(p) or p.dead:
		return
	if p.global_position.distance_to(global_position) <= LootPickup.REACH:
		_enter()
	else:
		p.walk_to(global_position, LootPickup.REACH * 0.8, func():
			if is_instance_valid(self) and is_inside_tree():
				_enter()
		)


func _enter() -> void:
	var n := get_parent()
	while n != null and not n.has_method("return_to_town"):
		n = n.get_parent()
	if n != null:
		n.return_to_town()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	draw_circle(Vector2.ZERO, RADIUS, Color(0.05, 0.15, 0.35, 0.55))
	for i in 4:
		var r := RADIUS - i * 11.0 + sin(t * 2.0 + i) * 3.0
		var a0 := -t * (1.0 + i * 0.3)
		var col := Color(0.55, 0.80, 1.0, 0.85 - i * 0.15) if i % 2 == 0 else Color(1.0, 0.85, 0.45, 0.8 - i * 0.15)
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU * 0.78, 40, col, 4.0)
	draw_circle(Vector2.ZERO, 14.0, Color(0.85, 0.95, 1.0, 0.55 + 0.25 * sin(t * 3.0)))
