class_name CurrencyPickup
extends Node2D
## Orbs, materials, gold and recipe pages lying on the ground. Collected by walking near.
## kind: "orb" | "material" | "gold" | "recipe"

var kind := "gold"
var id := ""
var amount := 1
var delay := 0.3
var _t := 0.0


func _ready() -> void:
	add_to_group("currency_pickups")
	_t = randf() * TAU


func _process(delta: float) -> void:
	delay = maxf(delay - delta, 0.0)
	_t += delta * 4.0
	queue_redraw()


func label_text() -> String:
	match kind:
		"orb": return "%s" % CraftingDB.ORBS[id].short
		"material": return "%d %s" % [amount, CraftingDB.MATERIALS[id].name]
		"recipe": return "Recipe: %s" % CraftingDB.RECIPES[id].name
	return "%d Gold" % amount


func color() -> Color:
	match kind:
		"orb": return CraftingDB.ORBS[id].color
		"material": return CraftingDB.MATERIALS[id].color
		"recipe": return Color(0.9, 0.75, 0.5)
	return Color(1.0, 0.85, 0.2)


## Hands the contents to the player. Returns a message to show.
func collect() -> String:
	match kind:
		"orb": GameState.add_orb(id, amount)
		"material": GameState.add_material(id, amount)
		"recipe":
			if not GameState.learn_recipe(id):
				GameState.add_gold(40)
				return "Recipe already known: +40 Gold"
			return "Learned recipe: %s" % CraftingDB.RECIPES[id].name
		_: GameState.add_gold(amount)
	return "+" + label_text()


func _draw() -> void:
	var c := color()
	var bob := sin(_t) * 3.0
	var p := Vector2(0, -14 + bob)
	match kind:
		"orb":
			draw_circle(p, 11, c.darkened(0.5))
			draw_circle(p, 8, c)
			draw_circle(p + Vector2(-3, -3), 3, Color(1, 1, 1, 0.7))
		"material":
			var pts := PackedVector2Array([p + Vector2(0, -10), p + Vector2(9, 0), p + Vector2(0, 10), p + Vector2(-9, 0)])
			draw_colored_polygon(pts, c)
			draw_polyline(pts + PackedVector2Array([pts[0]]), c.lightened(0.5), 2.0)
		"recipe":
			draw_rect(Rect2(p + Vector2(-9, -11), Vector2(18, 22)), c)
			draw_rect(Rect2(p + Vector2(-9, -11), Vector2(18, 22)), c.darkened(0.5), false, 2.0)
			for i in 3:
				draw_line(p + Vector2(-5, -5 + i * 5), p + Vector2(5, -5 + i * 5), c.darkened(0.5), 2.0)
		_:
			draw_circle(p, 8, c.darkened(0.4))
			draw_circle(p, 6, c)
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(-40, -32), label_text(), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, c.lightened(0.3))
