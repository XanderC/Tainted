extends Node2D
## A rift run: hand-made mazes (MazeLibrary) full of monster packs. Fight your way through, step
## into the portal for another random maze, and once enough monsters are dead (DungeonRun) the boss
## appears. Move: left-thumb joystick (or arrow keys on desktop).

const PACKS_PER_MAZE := 6        # how many of a maze's "m" spots get a monster pack
const PACK_SIZE := Vector2i(3, 5)
const PACK_AGGRO := 520.0        # packs wake when you come this close (or when one is hit)
const PORTAL_REACH := 70.0

var player: Player
var hud: Label
var drop_label: Label
var death_label: Label
var kills := 0
const UpgradePopupUIScript = preload("res://scripts/upgrade_popup_ui.gd")

var menu: GameMenu
var skill_tree_ui: SkillTreeUI
var upgrade_popup_ui: CanvasLayer
var run: DungeonRun
var maze: MazeMap
var portal: RiftPortal
var mazes_visited := 0
var _cam: Camera2D
var _arrow: PortalArrow
var _fade: ColorRect
var _travelling := false


func _ready() -> void:
	y_sort_enabled = true  # characters and loot overlap correctly: lower on screen draws in front
	player = Player.new()
	player.class_def = ClassLibrary.get_class_def(GameState.char_class)
	add_child(player)
	_cam = Camera2D.new()
	player.add_child(_cam)

	var layer := CanvasLayer.new()
	add_child(layer)

	var joy := VirtualJoystick.new()
	layer.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.joystick = joy

	# Right-thumb action buttons: large central Main Attack button (0) with skills 1-3 orbiting it
	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	for i in SkillButton.CENTRES:
		var b := SkillButton.new()
		b.player = player
		b.index = i
		b.position = SkillButton.pad_position(i)
		pad.add_child(b)
	# The flask row, between the orbs at the bottom centre
	var flasks := FlaskBar.new()
	flasks.player = player
	layer.add_child(flasks)
	var swap := WeaponSwapButton.new()
	swap.player = player
	swap.position = Vector2(-137, -358)
	pad.add_child(swap)

	var bars := HudBars.new()
	bars.player = player
	layer.add_child(bars)

	hud = Label.new()
	hud.position = Vector2(16, 80)
	layer.add_child(hud)

	drop_label = Label.new()
	drop_label.position = Vector2(16, 190)
	layer.add_child(drop_label)

	death_label = Label.new()
	death_label.text = "YOU DIED\nTap or press any key to return to town"
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	death_label.visible = false
	layer.add_child(death_label)

	player.item_picked.connect(_on_item_picked)
	player.died.connect(func(): death_label.visible = true)
	player.item_dropped.connect(_on_item_dropped)

	_arrow = PortalArrow.new()
	_arrow.player = player
	layer.add_child(_arrow)
	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.0, 0.08, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	run = DungeonRun.new()
	run.player = player
	run.main = self
	add_child(run)
	run.boss_summoned.connect(func(_pos):
		if portal != null:
			portal.active = false
	)
	_load_maze()

	menu = GameMenu.new()
	menu.player = player
	add_child(menu)

	skill_tree_ui = SkillTreeUI.new()
	skill_tree_ui.player = player
	add_child(skill_tree_ui)

	upgrade_popup_ui = UpgradePopupUIScript.new()
	upgrade_popup_ui.player = player
	add_child(upgrade_popup_ui)



func _process(delta: float) -> void:
	if portal != null and portal.active and not _travelling and not player.dead \
			and player.global_position.distance_to(portal.global_position) < PORTAL_REACH:
		_travel()

	for p in get_tree().get_nodes_in_group("currency_pickups"):
		if p.delay <= 0.0 and p.global_position.distance_to(player.global_position) < 70.0:
			drop_label.text = p.collect()
			drop_label.modulate = p.color().lightened(0.3)
			p.queue_free()

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if player.dead and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		return_to_town()


func return_to_town() -> void:
	GameState.save()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/town.tscn")


# ---------- mazes ----------

## Replace the current maze with a random different one and fill it with monster packs.
func _load_maze() -> void:
	var prev := ""
	if maze != null:
		prev = maze.map_id
		maze.queue_free()
		portal.queue_free()
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.is_boss:
				e.queue_free()
	maze = MazeMap.new()
	# The map editor's "Test in Game" plays one map over and over (GameState.test_map)
	maze.setup(GameState.test_map if GameState.test_map != "" else MazeLibrary.random_name(prev))
	add_child(maze)
	mazes_visited += 1

	portal = RiftPortal.new()
	portal.position = maze.portal_pos
	portal.active = run.state == DungeonRun.State.FIGHTING
	add_child(portal)
	_arrow.target = portal

	player.global_position = maze.start_pos
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(maze.cols * MazeMap.CELL)
	_cam.limit_bottom = int(maze.rows * MazeMap.CELL)
	_cam.reset_smoothing()

	# Monster packs on some of the maze's "m" spots (never right next to the start)
	var spots := maze.packs.filter(func(o): return Vector2(o.x, o.y).distance_to(maze.start_pos) > 450.0)
	spots.shuffle()
	for i in mini(PACKS_PER_MAZE, spots.size()):
		var o: Dictionary = spots[i]
		var n := randi_range(int(o.get("min", PACK_SIZE.x)), int(o.get("max", PACK_SIZE.y))) + int(run.level / 5.0)
		var at := Vector2(float(o.x), float(o.y))
		var pack := "pack_%d_%d" % [mazes_visited, i]
		# Some packs are led by an Elite or a Legendary (MonsterAffix)
		var lead_tier := MonsterAffix.roll_tier(run.level)
		if lead_tier == MonsterAffix.Tier.LEGENDARY:
			n += 1
		for j in n:
			_spawn_enemy(at + Vector2(randf_range(-50, 50), randf_range(-50, 50)), pack,
				lead_tier if j == 0 else MonsterAffix.Tier.NORMAL)
	run.announce("%s  —  maze %d" % [maze.map_name, mazes_visited], Color(0.85, 0.7, 1.0))


## Step through the portal: fade out, new maze, fade in.
func _travel() -> void:
	_travelling = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	t.tween_callback(_load_maze)
	t.tween_property(_fade, "color:a", 0.0, 0.45)
	t.tween_callback(func(): _travelling = false)


func _spawn_enemy(pos: Vector2, pack: String, tier := 0) -> Enemy:
	var e := Enemy.new()
	e.position = pos
	e.target = player
	e.maze = maze
	e.aggro_range = PACK_AGGRO
	e.pack = pack
	var lvl := run.level
	e.max_hp = (25.0 + kills * 1.5) * DungeonRun.hp_mult(lvl)
	e.touch_damage *= DungeonRun.damage_mult(lvl)
	e.speed *= DungeonRun.speed_mult(lvl)
	if tier != MonsterAffix.Tier.NORMAL:
		e.make_elite(tier, MonsterAffix.roll_affixes(tier, lvl))
	e.died.connect(_on_enemy_died.bind(e.kill_weight()))
	e.minion_spawned.connect(func(m: Enemy): m.died.connect(_on_enemy_died.bind(1)))
	add_child(e)
	e.add_to_group(pack)
	return e


## Normal monsters drop nothing (they still give XP); the boss drops all the loot (DungeonRun).
func _on_enemy_died(_pos: Vector2, weight := 1) -> void:
	kills += 1
	run.on_enemy_killed(weight)


func spawn_currency(kind: String, id: String, amount: int, pos: Vector2) -> void:
	var c := CurrencyPickup.new()
	c.kind = kind
	c.id = id
	c.amount = amount
	c.position = pos + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 55.0)
	add_child(c)


## An item's name plate was tapped and the player reached it (LootPickup). It goes into the bag;
## an upgrade also gets the popup saying so (equipping is only by dragging it onto its slot).
## False when there's no room for it.
func take_loot(p: LootPickup) -> bool:
	var better := player.is_better_in_slot(p.item)
	if not player.pick_up(p.item):
		return false
	p.queue_free()
	if better:
		upgrade_popup_ui.prompt_upgrade(p.item, null)
	return true


func _on_item_dropped(item: ItemInstance) -> void:
	var pk := LootPickup.new()
	pk.item = item
	pk.delay = 1.5  # so you don't instantly pick it back up
	pk.position = player.global_position + player.facing * 90.0
	add_child(pk)


func _on_item_picked(item: ItemInstance) -> void:
	drop_label.text = "Picked up:\n" + item.get_tooltip()
	drop_label.modulate = ItemInstance.RARITY_COLORS[item.rarity]


func _update_hud() -> void:
	var s := player.stats
	hud.text = "%s\nDMG %.1f   Atk/s %.2f   Crit %d%%\nArmor %d   Move %d\nGear: %d slots filled   Bag: %d/%d cells   Chaos %d" % [
		player.class_def.display_name,
		s.get_stat("damage"), s.get_stat("attack_speed"), int(round(s.get_stat("crit_chance") * 100.0)),
		int(s.get_stat("armor")), int(s.get_stat("move_speed")),
		player.equipment.size(), player.bag_cells_used(), Player.BAG_SIZE, GameState.orb_count("chaos"),
	]
