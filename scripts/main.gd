extends Node2D
## A rift run: hand-made mazes (MazeLibrary) full of monster packs. Fight your way through, step
## into the portal for another random maze, and once enough monsters are dead (DungeonRun) the boss
## appears. Move: left-thumb joystick (or arrow keys on desktop).
## With a party (Net.coop, kind "rift") it's the party's rift: Coop shares it, the other players
## are there (NetPresence), and the instance's host loads the mazes (start_host) while the others
## load what it loads (remote_maze) and ask it to go through the portal (party_travel).
## A town portal scroll (TownPortals) takes you to town and back: a solo rift is saved going through
## its portal (snapshot) and carried on with coming back (_restore); a party's waits on the server
## when the last one out leaves while a portal leads into it (Net.save_rift).

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
var coop: Coop = null
var rift_key := ""  ## which rift this is (TownPortals): a party's is its instance
var portals: TownPortals
var _left := false


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

	var portrait := HirelingPortrait.new()  # your hireling, top left: tap for its equipment
	portrait.position = Vector2(16, 10)
	portrait.on_open = func(): menu.open("hireling")
	layer.add_child(portrait)
	TownPortals.add_button(layer, self)

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
	player.died.connect(func(): death_label.visible = coop == null)  # a party's rift: PartyDeath
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
	var party_rift: bool = Net.online() and String(Net.coop.get("kind", "")) == "rift"
	if party_rift:
		run.forced_level = int(Net.coop.get("level", 1))
		run.remote = true  # until it's known who hosts
	var resume: Dictionary = {} if party_rift else GameState.rift_resume  # back through a portal: as you left it
	GameState.rift_resume = {}
	if not resume.is_empty():
		run.forced_level = int(resume.get("level", 1))
	rift_key = String(Net.coop.inst) if party_rift else "solo:%d" % randi()
	portals = TownPortals.new()
	add_child(portals)
	add_child(run)
	run.boss_summoned.connect(func(_pos):
		if portal != null:
			portal.active = false
	)
	if party_rift:
		var presence := NetPresence.new()  # the party's other players, here with you
		presence.instance = String(Net.coop.inst)
		add_child(presence)
		coop = Coop.new()
		coop.main = self
		add_child(coop)
		var fall := PartyDeath.new()
		fall.main = self
		add_child(fall)
		_fade.color.a = 1.0  # dark until the maze is known (start_host / remote_maze)
	elif not resume.is_empty():
		_restore(resume)
	else:
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
		if coop != null and not coop.is_host:
			if not coop.travel_asked:
				coop.travel_asked = true  # the host takes the party through
				Net.send_event(-1, "travel", {})
		else:
			_travel()

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TownPortals.SCROLL_KEY:
		TownPortals.read_scroll(self)
		return
	if player.dead and coop == null and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		return_to_town()


## Fell in a party's rift and waited (PartyDeath): up again at the maze's start, at full life.
func get_up() -> void:
	player.revive(1.0)
	player.global_position = maze.start_pos


## Back to town (you fell alone, gave up in a party's rift, or took the cleared rift's way home).
func return_to_town() -> void:
	_leave_rift(false)
	_go_to_town("start")


## Through a town portal (yours or a party member's: TownPortals): to town, and the rift waits for
## you (what lies on the ground here too).
func portal_to_town() -> void:
	if _left or _travelling:
		return
	TownPortals.remember_loot(self, portal_place())
	_leave_rift(true)
	_go_to_town("portal")


func _go_to_town(entry: String) -> void:
	_left = true
	ActDB.travel(get_tree(), ActDB.TOWN, entry)


## Leaving: a solo rift is saved into your portal going through it (else the portal closes: the rift
## is gone). In a party's, the last one out saves it while anyone's portal leads into it.
func _leave_rift(through_portal: bool) -> void:
	if maze == null or _left:
		return
	var ok := run.state != DungeonRun.State.FAILED
	if coop == null:
		var mine: Dictionary = GameState.town_portal
		if String(mine.get("key", "")) == rift_key:
			if through_portal and ok:
				mine["save"] = snapshot()
			else:
				TownPortals.close_mine()
	elif ok and coop.is_host and Net.others.is_empty() and TownPortals.all().any(func(e):
			return String(e.tp.get("key", "")) == rift_key and int(e.tp.get("maze", 0)) == mazes_visited):
		Net.save_rift(rift_key, snapshot())


## Where a town portal read here stands (TownPortals): this rift and maze.
func portal_place() -> Dictionary:
	if maze == null:
		return {}
	return {"kind": "rift", "key": rift_key, "maze": mazes_visited, "level": run.level,
		"inst": String(Net.coop.get("inst", "")) if coop != null else ""}


## The rift as it is: its maze, the run, the monsters left and the cleared rift's way home.
func snapshot() -> Dictionary:
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and not e._dead and not e.remote and not e.is_queued_for_deletion():
			enemies.append(Coop.describe(e))
	var exit: Array = []
	for n in get_tree().get_nodes_in_group("town_portals"):
		if n.tp_id == 0 and not n.is_queued_for_deletion():
			exit = [n.position.x, n.position.y]
	return {"key": rift_key, "level": run.level, "map": maze.map_id, "n": mazes_visited, "kills": kills,
		"packs": _pack_kind, "run": run.save_state(), "enemies": enemies, "exit": exit}


## Carry on with a rift as it was left (snapshot).
func _restore(r: Dictionary) -> void:
	rift_key = String(r.get("key", rift_key))
	kills = int(r.get("kills", 0))
	_pack_kind = r.get("packs", {})
	run.load_state(r.get("run", {}))
	mazes_visited = int(r.get("n", 1)) - 1
	_load_maze(String(r.get("map", "")), false)
	for d in r.get("enemies", []):
		_restore_enemy(d)
	var exit: Array = r.get("exit", [])
	if exit.size() == 2:
		var tp := TownPortal.new()
		tp.position = Vector2(float(exit[0]), float(exit[1]))
		add_child(tp)
	if coop != null:
		coop.maze_loaded()
	_maze_known()


## A monster as it was left (Coop.describe), the real thing again.
func _restore_enemy(d) -> void:
	if not d is Dictionary:
		return
	var e := Enemy.new()
	e.kind = String(d.get("kind", "zombie"))
	e.skin = String(d.get("skin", ""))
	e.display_name = String(d.get("name", ""))
	e.tier = int(d.get("tier", 0))
	e.affixes.assign(Array(d.get("affixes", [])).map(func(a): return String(a)))
	e.max_hp = float(d.get("max_hp", 25.0))
	e.speed = float(d.get("speed", 100.0))
	e.touch_damage = float(d.get("touch", 5.0))
	e.size_mult = float(d.get("size", 1.0))
	e.ranged = bool(d.get("ranged", false))
	e.is_boss = bool(d.get("boss", false))
	e.pack = String(d.get("pack", ""))
	e.aggro_range = float(d.get("aggro", PACK_AGGRO))
	e.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	e.target = player
	e.maze = maze
	if not e.is_boss:
		e.died.connect(_on_enemy_died.bind(e.kill_weight()))
		e.minion_spawned.connect(func(m: Enemy): m.died.connect(_on_enemy_died.bind(1)))
	add_child(e)
	if e.pack != "":
		e.add_to_group(e.pack)
	e.hp = clampf(float(d.get("hp", e.max_hp)), 1.0, e.max_hp)
	if e.is_boss:
		run.boss_arrived(e, true)
	e.hp_changed.emit(e.hp, e.max_hp)


## Which maze this is is known (loaded, and numbered): portals into the mazes before close, the ones
## here show, and arriving back through one you stand by it, with what you left lying about.
func _maze_known() -> void:
	var mine: Dictionary = GameState.town_portal
	if String(mine.get("kind", "")) == "rift" and String(mine.get("key", "")) == rift_key \
			and int(mine.get("maze", 0)) != mazes_visited:
		TownPortals.close_mine()
	if coop != null and coop.is_host:
		Net.rift_maze(rift_key, mazes_visited)
	var where := portal_place()
	portals.set_place(where)
	var at := TownPortals.take_arrival(where)
	GameState.portal_arrival = {}
	if at.is_finite():
		player.global_position = at
		_cam.reset_smoothing()
	TownPortals.restore_loot(self, where)


# ---------- mazes ----------

## This game hosts the party's rift: the first maze, as for a solo rift.
func start_host() -> void:
	run.remote = false
	var saved := Net.take_rift_save(rift_key)  # left by the last one out, with a portal still open into it
	if saved.is_empty():
		_load_maze()
	else:
		_restore(saved)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.45)


## A copy of the host's monster (Coop): its death counts here as your kills do.
func coop_copy(e: Enemy, _d: Dictionary) -> void:
	e.died.connect(_on_enemy_died.bind(e.kill_weight()))


## A party member stepped into the portal: through it we all go (the host's game).
func party_travel() -> void:
	if not _travelling and portal != null and portal.active:
		_travel()


## The host loaded a maze (`d`: {"map", "n"}): load the same one, without monsters (the host's
## arrive as copies). `instant`: just arrived, no fade out first.
func remote_maze(d: Dictionary, instant: bool) -> void:
	var map := String(d.get("map", ""))
	if map == "":
		return
	var load_it := func():
		_load_maze(map, false)
		mazes_visited = int(d.get("n", mazes_visited))
		coop.travel_asked = false
		_maze_known()
	if instant:
		load_it.call()
		create_tween().tween_property(_fade, "color:a", 0.0, 0.45)
		return
	_travelling = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	t.tween_callback(load_it)
	t.tween_property(_fade, "color:a", 0.0, 0.45)
	t.tween_callback(func(): _travelling = false)


## Replace the current maze with a random different one (or `map`) and, if `spawn`, fill it with
## monster packs.
func _load_maze(map := "", spawn := true) -> void:
	var prev := ""
	if maze != null:
		prev = maze.map_id
		maze.queue_free()
		portal.queue_free()
		if spawn:  # a party member's copies go when the host says so ("gone")
			for e in get_tree().get_nodes_in_group("enemies"):
				if not e.is_boss:
					e.queue_free()
	maze = MazeMap.new()
	# The map editor's "Test in Game" plays one map over and over (GameState.test_map)
	if map == "":
		map = GameState.test_map if GameState.test_map != "" else MazeLibrary.random_name(prev)
	maze.setup(map)
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

	if not spawn:
		run.announce("%s  —  maze %d" % [maze.map_name, mazes_visited], Color(0.85, 0.7, 1.0))
		return
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
	if coop != null:
		coop.maze_loaded()
	_maze_known()


## Step through the portal: fade out, new maze, fade in.
func _travel() -> void:
	_travelling = true
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	t.tween_callback(_load_maze)
	t.tween_property(_fade, "color:a", 0.0, 0.45)
	t.tween_callback(func(): _travelling = false)


var _pack_kind := {}  # pack -> MonsterKinds id: a pack is all one kind of monster


func _spawn_enemy(pos: Vector2, pack: String, tier := 0) -> Enemy:
	var e := Enemy.new()
	e.position = pos
	e.target = player
	e.maze = maze
	e.aggro_range = PACK_AGGRO
	e.pack = pack
	var lvl := run.level
	e.max_hp = (25.0 + kills * 1.5) * DungeonRun.hp_mult(lvl) * Coop.hp_scale()
	e.touch_damage *= DungeonRun.damage_mult(lvl)
	e.speed *= DungeonRun.speed_mult(lvl)
	if not _pack_kind.has(pack):
		_pack_kind[pack] = MonsterKinds.random_kind(lvl)
	e.set_kind(_pack_kind[pack])
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


## Currency on the ground was picked up (its label tapped: CurrencyPickup); it's in the shared stash.
func currency_taken(text: String, col: Color) -> void:
	drop_label.text = text
	drop_label.modulate = col


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
		GameState.build_title(),
		s.get_stat("damage"), s.get_stat("attack_speed"), int(round(s.get_stat("crit_chance") * 100.0)),
		int(s.get_stat("armor")), int(s.get_stat("move_speed")),
		player.equipment.size(), player.bag_cells_used(), Player.BAG_SIZE, GameState.orb_count("chaos"),
	]
