class_name LootChest
extends Interactable
## A chest in a zone (Breakables places them): walk up and press the prompt (E, or tap it): it opens and spills
## its loot (the zone rolls it, see Breakables.drop_loot). Opened once; a solo zone is kept whole, so it
## stays open while you are away.

signal opened(at: Vector2)

var is_open := false
var _t := 0.0


func _init() -> void:
	prompt = "Open the chest"
	radius = 120.0


func _ready() -> void:
	super._ready()
	action = open


func _process(delta: float) -> void:
	if not is_open:
		_t += delta
		queue_redraw()


## Opens it (once).
func open() -> void:
	if is_open:
		return
	is_open = true
	remove_from_group("interactables")
	queue_redraw()
	opened.emit(global_position)


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-34, 4), Vector2(0, 14), Vector2(34, 4), Vector2(0, -6)]), Color(0, 0, 0, 0.3))
	var wood := Color(0.45, 0.28, 0.14)
	var dark := Color(0.12, 0.08, 0.05)
	var iron := Color(0.36, 0.36, 0.40)
	draw_rect(Rect2(-26, -28, 52, 28), wood)  # the body
	draw_rect(Rect2(-26, -28, 52, 28), dark, false, 2.5)
	for x in [-18.0, 14.0]:
		draw_rect(Rect2(x, -28, 5, 28), iron)
	if is_open:  # the lid thrown back, and a glow inside
		draw_rect(Rect2(-24, -28, 48, 6), Color(0.95, 0.80, 0.30, 0.8))
		draw_rect(Rect2(-26, -50, 52, 12), wood.lightened(0.1))
		draw_rect(Rect2(-26, -50, 52, 12), dark, false, 2.5)
		return
	draw_rect(Rect2(-28, -40, 56, 14), wood.lightened(0.15))  # the lid
	draw_rect(Rect2(-28, -40, 56, 14), dark, false, 2.5)
	for x in [-18.0, 14.0]:
		draw_rect(Rect2(x, -40, 5, 14), iron)
	draw_rect(Rect2(-5, -30, 10, 10), Color(0.95, 0.80, 0.30))  # the lock
	var glint := 0.5 + 0.5 * sin(_t * 3.0)  # it glints, so it is seen from afar
	draw_arc(Vector2(0, -18), 44.0, 0.0, TAU, 40, Color(1.0, 0.85, 0.3, 0.25 + 0.3 * glint), 3.0)
