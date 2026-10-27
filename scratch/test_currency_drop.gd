extends Node2D
## Checks currency on the ground: a rift boss's orbs, shards, runes and gems drop round it with
## labels (nothing goes to the stash until picked up), walking over a pile doesn't pick it up, tapping
## its label does (into the shared stash), and the result panel lists none of it. Run headless:
##   godot --headless --path . res://scratch/test_currency_drop.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	GameState.give_starter_skills()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var run: DungeonRun = main.run
	var p: Player = main.player
	var orbs0 := GameState.orbs.duplicate()
	var shards0 := GameState.shards.duplicate()
	var gems0 := GameState.gems.duplicate()
	var runes0 := GameState.runes.duplicate()
	run.state = DungeonRun.State.BOSS
	var boss_at := p.global_position + Vector2(400, 0)
	run._on_boss_died(boss_at)
	await get_tree().process_frame
	var piles: Array = get_tree().get_nodes_in_group("currency_pickups")
	var kinds := {}
	var bundles := 0
	for c in piles:
		kinds[c.kind] = true
		if c.kind == "bundle":
			bundles += 1
			for part in c.parts:
				kinds[part[0]] = true  # (what is in a pile)
	check(piles.size() >= 3 and piles.size() <= 8, "the boss's currency lies on the ground in a few piles (%d: %s)" % [piles.size(), kinds.keys()])
	check(bundles == 2, "orbs and shards are one pile, gems and runes another (%d bundles)" % bundles)
	check(kinds.has("orb") and kinds.has("shard") and kinds.has("rune") and kinds.has("gem"), "orbs, shards, runes and gems among them")
	check(piles.all(func(c): return c._plate != null and c._plate.text != ""), "each has a label")
	check(GameState.orbs == orbs0 and GameState.shards == shards0 and GameState.gems == gems0 and GameState.runes == runes0,
		"nothing went to the stash before it was picked up")
	check(not ("_result" in run), "no results panel: what dropped is on the ground to see")
	check(run._banner.visible and "cleared" in run._banner.text, "\"Rift N cleared\" and the time in the middle (%s)" % run._banner.text.replace("\n", " / "))
	var portals: Array = main.get_children().filter(func(n): return n is TownPortal)
	check(portals.size() == 1 and portals[0]._plate.text.contains("Town Portal"), "a town portal near where the boss fell, with a label")
	if DisplayServer.get_name() != "headless":  # a look at the ground round the boss
		p.global_position = boss_at + Vector2(0, 60)
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/rift_drops.png"))
	if not portals.is_empty():
		p.global_position = portals[0].global_position + Vector2(400, 0)
		portals[0]._plate.pressed.emit()  # tapped from afar: the player sets off to it
		check(p._walking and p._walk_target == portals[0].global_position, "tapping its label walks the player there (then home)")
		p._walking = false
	var first = piles[0]
	p.global_position = first.global_position
	await get_tree().create_timer(0.6).timeout
	check(is_instance_valid(first) and first.is_inside_tree(), "standing on a pile doesn't pick it up")
	var n := 0
	for c in piles:
		if is_instance_valid(c):
			p.global_position = c.global_position
			c._plate.pressed.emit()  # its label tapped
			n += 1
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("currency_pickups").is_empty(), "tapping each label picks it up (%d)" % n)
	var more := func(now: Dictionary, before: Dictionary) -> bool:
		return now.keys().any(func(k): return int(now[k]) > int(before.get(k, 0)))
	check(more.call(GameState.orbs, orbs0) and more.call(GameState.gems, gems0) and more.call(GameState.runes, runes0),
		"and it's in the shared stash: orbs, gems, runes")
	print("currency drop: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
