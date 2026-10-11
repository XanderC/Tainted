class_name RiftPortal
extends Node2D
## Swirling portal at a maze's P spot. Walking into it takes you to another random maze
## (handled by main.gd). Hidden once the rift boss has been summoned.

const RADIUS := 64.0

var active := true


func _ready() -> void:
	z_index = -1  # flat on the ground, under characters


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var t := Time.get_ticks_msec() / 1000.0
	draw_circle(Vector2.ZERO, RADIUS, Color(0.25, 0.05, 0.35, 0.55))
	for i in 4:
		var r := RADIUS - i * 13.0 + sin(t * 2.0 + i) * 3.0
		var a0 := t * (1.0 + i * 0.3)
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU * 0.78, 40, Color(0.75, 0.4, 1.0, 0.85 - i * 0.15), 4.0)
	draw_circle(Vector2.ZERO, 16.0, Color(0.9, 0.7, 1.0, 0.55 + 0.25 * sin(t * 3.0)))
