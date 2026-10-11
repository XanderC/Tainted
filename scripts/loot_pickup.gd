class_name LootPickup
extends Node2D
## An item lying on the ground with a coloured name label, Diablo-style.

var item: ItemInstance
var delay := 0.0  # seconds before it can be picked up (set on items you drop)


func _process(delta: float) -> void:
	delay = maxf(delay - delta, 0.0)
	if item.is_unique():
		queue_redraw()  # animated light beam


func _ready() -> void:
	add_to_group("pickups")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var label := Label.new()
	label.text = item.display_name
	label.modulate = ItemInstance.RARITY_COLORS[item.rarity]
	label.position = Vector2(-50, -62)
	add_child(label)


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
