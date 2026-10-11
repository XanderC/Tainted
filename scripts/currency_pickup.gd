class_name CurrencyPickup
extends Node2D
## Orbs, orb shards and recipe pages lying on the ground. Collected by walking near.
## kind: "orb" | "shard" | "recipe"

var kind := "shard"
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
		"recipe": return "%s: %s" % ["Plan" if CraftingDB.is_plan(id) else "Recipe", CraftingDB.RECIPES[id].name]
	return "%d %s Shards" % [amount, CraftingDB.ORBS.get(id, {}).get("short", "Orb")]


func color() -> Color:
	match kind:
		"orb": return CraftingDB.ORBS[id].color
		"recipe": return CraftingDB.recipe_color(id)
	return CraftingDB.ORBS.get(id, {}).get("color", Color(1.0, 0.85, 0.2))


## Hands the contents to the player. Returns a message to show.
func collect() -> String:
	match kind:
		"orb": GameState.add_orb(id, amount)
		"recipe":
			if not GameState.learn_recipe(id):
				GameState.add_shards("alchemy", 5)
				return "Already known: +5 Alchemy Shards"
			return "Learned %s: %s" % ["plan" if CraftingDB.is_plan(id) else "recipe", CraftingDB.RECIPES[id].name]
		_: GameState.add_shards(id, amount)
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
