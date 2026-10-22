class_name CurrencyPickup
extends Node2D
## Orbs, orb shards and recipe pages lying on the ground, labelled like gear (a LootPickup name plate,
## stacked with theirs): tap (or click) the label to pick it up, walking over first when it's out of
## reach; walking over it does nothing. Orbs and shards go straight into the shared stash (the
## account's currency), a page is learned. The scene shows what you got: currency_taken(text, colour)
## on the nearest ancestor that has it. A rift's runes and gems drop this way too.
## kind: "orb" | "shard" | "recipe" | "rune" (a skill rune) | "gem" (a socket gem or rune) | "skill_gem"

var kind := "shard"
var id := ""
var amount := 1
var delay := 0.3  # kept for spawners; a tap always works
var _t := 0.0
var _plate: Button  # its label (LootPickup.layout places it)


func _ready() -> void:
	add_to_group("currency_pickups")
	add_to_group("pickups")  # its label stacks with the items' and the joystick leaves it alone
	_t = randf() * TAU
	_plate = LootPickup.make_plate(label_text(), color().lightened(0.25), request_pickup)
	add_child(_plate)
	LootPickup._layout_dirty = true


func _exit_tree() -> void:
	LootPickup._layout_dirty = true


func _process(delta: float) -> void:
	delay = maxf(delay - delta, 0.0)
	_t += delta * 4.0
	if LootPickup._layout_dirty:
		LootPickup.layout(get_tree())
	queue_redraw()


func label_text() -> String:
	match kind:
		"orb": return ("%d %s" % [amount, CraftingDB.ORBS[id].short]) if amount > 1 else String(CraftingDB.ORBS[id].short)
		"recipe": return "%s: %s" % ["Plan" if CraftingDB.is_plan(id) else "Recipe", CraftingDB.RECIPES[id].name]
		"rune": return _counted(RuneDef.DB.get_rune(id).display_name)
		"gem": return _counted(String(GemDef.info(id).get("name", id)))
		"skill_gem": return _counted("Skill Gem: " + SkillTree.get_skill(id).display_name)
	return "%d %s Shards" % [amount, CraftingDB.ORBS.get(id, {}).get("short", "Orb")]


func _counted(name: String) -> String:
	return "%d %s" % [amount, name] if amount > 1 else name


func color() -> Color:
	match kind:
		"orb": return CraftingDB.ORBS[id].color
		"recipe": return CraftingDB.recipe_color(id)
		"rune": return RuneDef.DB.get_rune(id).rarity_color()
		"gem": return Color(GemDef.info(id).get("color", Color.WHITE))
		"skill_gem": return SkillTree.get_skill(id).color
	return CraftingDB.ORBS.get(id, {}).get("color", Color(1.0, 0.85, 0.2))


## Its label was tapped: take it if the player is close enough, else walk over and then take it.
func request_pickup() -> void:
	var p := GameState.player
	if not is_instance_valid(p) or p.dead:
		return
	if p.global_position.distance_to(global_position) <= LootPickup.REACH:
		_take()
	else:
		p.walk_to(global_position, LootPickup.REACH * 0.8, func():
			if is_instance_valid(self) and is_inside_tree():
				_take()
		)


func _take() -> void:
	var text := collect()
	var n := get_parent()
	while n != null and not n.has_method("currency_taken"):
		n = n.get_parent()
	if n != null:
		n.currency_taken(text, color().lightened(0.3))
	queue_free()


## Hands the contents over (into the shared stash, or a page learned). Returns a message to show.
func collect() -> String:
	match kind:
		"orb": GameState.add_orb(id, amount)
		"rune": GameState.add_rune(id, amount)
		"gem": GameState.add_gem(id, amount)
		"skill_gem": GameState.add_skill_gem(id, amount)
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
		"gem", "skill_gem":  # a cut stone
			var d := PackedVector2Array([p + Vector2(0, -11), p + Vector2(9, -2), p + Vector2(0, 10), p + Vector2(-9, -2)])
			draw_colored_polygon(d, c)
			draw_polyline(d + PackedVector2Array([d[0]]), c.darkened(0.5), 2.0)
			draw_circle(p + Vector2(-2, -4), 2.5, Color(1, 1, 1, 0.7))
		"rune":  # a carved tablet
			draw_rect(Rect2(p + Vector2(-8, -10), Vector2(16, 20)), c.darkened(0.35))
			draw_rect(Rect2(p + Vector2(-8, -10), Vector2(16, 20)), c, false, 2.0)
			draw_line(p + Vector2(-3, -5), p + Vector2(3, 5), c.lightened(0.3), 2.0)
		_:
			draw_circle(p, 8, c.darkened(0.4))
			draw_circle(p, 6, c)
