extends Node2D
## Big props go see-through while the player stands behind them (PropFader): the geometry (behind =
## above the base line and inside the picture), small props left alone, and the fade itself.
##   godot --headless --path . res://scratch/test_prop_fader.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func prop(map: Node, pos: Vector2, sc: float) -> Sprite2D:
	var tex: Texture2D = load("res://assets/icons/orbs/chaos.png")  # 128 x 128
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.9)
	s.scale = Vector2(sc, sc)
	s.position = pos
	map.add_child(s)
	return s


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var map := Node2D.new()
	town.add_child(map)
	var at := p.global_position
	var big := prop(map, at + Vector2(0, 40), 1.2)  # its base is 40 below the player, who stands inside its picture
	var far := prop(map, at + Vector2(900, 40), 1.2)
	var small := prop(map, at + Vector2(0, 40), 0.3)
	check(PropFader.covers(big, at), "behind a big prop: covered")
	check(not PropFader.covers(big, at + Vector2(0, 90)), "in front of its base: not covered")
	check(not PropFader.covers(big, at + Vector2(400, 0)), "beside it: not covered")
	check(not PropFader.covers(big, at + Vector2(0, -400)), "far above its picture: not covered")
	PropFader.attach(map, big)
	PropFader.attach(map, far)
	PropFader.attach(map, small)
	var f := map.get_node("PropFader") as PropFader
	check(f.sprites.size() == 2 and not small in f.sprites, "a small prop is not registered")
	for i in 40:
		await get_tree().process_frame
	check(big.modulate.a < 0.4, "the prop the player is behind fades: %.2f" % big.modulate.a)
	check(is_equal_approx(far.modulate.a, 1.0), "a far prop stays solid")
	p.global_position = at + Vector2(0, 200)  # steps out in front of it
	for i in 60:
		await get_tree().process_frame
	check(big.modulate.a > 0.99, "it comes back: %.2f" % big.modulate.a)
	print("prop fader: ", "ok" if fails == 0 else "%d failed" % fails)
	get_tree().quit(fails)
