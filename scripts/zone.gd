class_name Zone
extends Node2D
## A story zone (ActDB): an open area built from its map file, with every monster pack placed (they
## come back each time you enter), its area level setting their strength and loot, exits to other
## zones and town, a waypoint, NPCs, quest objects, story triggers and quest bosses. Which zone and
## where you arrive: GameState.current_zone and zone_entry (set by ActDB.travel).

const SCENE := "res://scenes/zone.tscn"
const PACK_AGGRO := 520.0
const CELLS_PER_PACK := 10.0 # a zone gets about one monster pack per this many floor cells (PackSpots)
const ARENA_CLEAR := 400.0  # no ordinary pack within this beyond a boss arena's ring (see _in_boss_arena)
const EXIT_REACH := 70.0
const WAYPOINT_REACH := 110.0
const ITEM_DROP_CHANCE := 0.10  # a normal monster's chance to drop an item (elites always do)
const SHARD_DROP_CHANCE := 0.09  # (a Currency pile is one label: CurrencyPickup bundles)
const SCROLL_DROP_CHANCE := 0.03  # a Scroll of Town Portal from a normal monster...
const SCROLL_ELITE_CHANCE := 0.25  # ...and from an elite
const UpgradePopupUIScript = preload("res://scripts/upgrade_popup_ui.gd")

var zone_id := ""
var area_level := 1
var player: Player
var maze: MazeMap
var menu: GameMenu
var skill_tree_ui: SkillTreeUI
var upgrade_popup_ui: CanvasLayer
var dialogue: DialogueUI
var quest_log: QuestLogUI
var waypoint_ui: WaypointUI

var _cam: Camera2D
var _exits: Array = []  # [{"node", "target"}]
var _waypoint: Interactable = null
var _triggers: Array = []  # trigger objects not yet walked into this visit
var _quest_objects: Array = []  # [{"node", "id"}]
var _boss: Enemy = null
var _boss_bar: BossBar  ## its name, health and what it shouts (BossBar), for a boss with an entry in BossDB
var _talk_btn: Button
var _toast: Label
var _boss_lbl: Label
var _death: Label
var _near: Interactable = null
var _leaving := false
var coop: Coop = null  ## the party's zone (Net.coop kind "zone"): shared with the party
var portals: TownPortals  ## the town portals open here, yours and your party's
var _hud_layer: CanvasLayer
var _inst := ""  # the party's instance of this zone ("" alone)


func _ready() -> void:
	y_sort_enabled = true
	get_tree().paused = false
	zone_id = GameState.current_zone if ActDB.ZONES.has(GameState.current_zone) else ActDB.ZONES.keys()[0]
	var z := ActDB.zone(zone_id)
	area_level = int(z.get("area_level", 1))
	maze = MazeMap.new()
	maze.setup(String(z["map"]))
	add_child(maze)
	_make_player()

	# With a party, the party's copy of this zone: the first member in runs its monsters (Coop)
	var party_zone := Net.online() and Net.in_party()
	if party_zone:
		Net.coop = {"inst": "zone:%d:%s" % [int(Net.party.id), zone_id], "kind": "zone"}
		_inst = String(Net.coop.inst)
	# The world: made once. A solo zone is kept as you leave it (ZoneInstances) and comes back by resume().
	_place_objects(not party_zone)
	if not party_zone:
		_spawn_packs()
		ZoneEncounters.roll(self)  # a cottage in the woods, a cult at its ritual: sometimes
	_enter()


## The player (and their camera): made when the zone is, and again each time they come back to it.
func _make_player() -> void:
	player = Player.new()
	player.class_def = ClassLibrary.get_class_def(GameState.char_class)
	add_child(player)
	_cam = GameCamera.make()
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(maze.cols * MazeMap.CELL)
	_cam.limit_bottom = int(maze.rows * MazeMap.CELL)
	player.add_child(_cam)
	player.died.connect(func(): _death.visible = coop == null)  # a party's zone: PartyDeath
	player.item_dropped.connect(_on_item_dropped)


## The player arrives: where they stand, their town portals, and the screen's buttons and windows.
func _enter() -> void:
	player.global_position = _arrival()
	GameState.portal_arrival = {}
	portals = TownPortals.new()
	portals.place = portal_place()
	add_child(portals)
	if _inst != "":  # a party's zone: what lay on the ground waits (a solo zone is kept whole instead)
		TownPortals.restore_loot(self, portal_place())
		var presence := NetPresence.new()
		presence.instance = String(Net.coop.inst)
		add_child(presence)
		coop = Coop.new()
		coop.main = self
		add_child(coop)
		var fall := PartyDeath.new()
		fall.main = self
		add_child(fall)
	_cam.reset_smoothing()

	_build_hud()
	menu = GameMenu.new()
	menu.player = player
	add_child(menu)
	skill_tree_ui = SkillTreeUI.new()
	skill_tree_ui.player = player
	add_child(skill_tree_ui)
	upgrade_popup_ui = UpgradePopupUIScript.new()
	upgrade_popup_ui.player = player
	add_child(upgrade_popup_ui)
	dialogue = DialogueUI.new()
	dialogue.player = player
	add_child(dialogue)
	quest_log = QuestLogUI.new()
	add_child(quest_log)
	waypoint_ui = WaypointUI.new()
	waypoint_ui.here = zone_id
	add_child(waypoint_ui)

	Quests.notify("zone", zone_id)
	_flash(ActDB.zone_name(zone_id), Color(1.0, 0.88, 0.6))


# ---------- kept between visits (ZoneInstances) ----------

## The player leaves and the zone is kept as it is: whatever is theirs is taken away (the player, their
## hireling, pet and allies, the screen's buttons and windows) and made again by resume(). A boss fight in
## progress is not kept: the boss is back asleep at full life, with its arena open and its adds gone.
func suspend() -> void:
	_reset_boss_fight()
	for g in ["hireling", "pet", "ancients", "town_portals"]:  # (the town portals are drawn again from GameState)
		for n in get_tree().get_nodes_in_group(g):
			if is_ancestor_of(n):
				n.queue_free()
	Hirelings.node = null
	PetDB.node = null
	for n in [player, menu, skill_tree_ui, upgrade_popup_ui, dialogue, quest_log, waypoint_ui, portals, _hud_layer]:
		if is_instance_valid(n):
			n.queue_free()
	_hud_layer = null
	_toast = null
	_talk_btn = null
	_boss_lbl = null
	_boss_bar = null
	_death = null
	player = null
	_near = null


## The player comes back to the zone as it was: a new player, the monsters turned on them, the story's
## triggers armed again, the screen made again. `entry` is how they came (GameState.zone_entry's values).
func resume(entry: String) -> void:
	_leaving = false
	GameState.current_zone = zone_id
	GameState.zone_entry = entry
	get_tree().paused = false
	_make_player()
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_ancestor_of(e):
			e.target = player
	for a in get_tree().get_nodes_in_group("boss_arena"):
		if is_ancestor_of(a):
			a.player = player
	_triggers = MapData.objects_of(maze.data, "trigger").duplicate()  # a spot passed earlier counts again
	_enter()


## Puts a boss fight that was begun back to the start: the boss is made again, asleep and at full life.
func _reset_boss_fight() -> void:
	if not is_instance_valid(_boss) or _boss._dead:
		return
	if not (_boss._aggro or (_boss.brain != null and _boss.brain.state != BossBrain.S.SLEEP)):
		return
	var id := String(_boss.get_meta("boss_id", ""))
	for g in ["boss_adds", "boss_arena"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_ancestor_of(n):
				n.queue_free()
	_boss.queue_free()
	_boss = null
	for o in MapData.objects_of(maze.data, "boss"):
		if String(o.get("id", "")) == id and Quests.boss_alive(id):
			_spawn_boss(o)


## Where you appear: at the waypoint, the town portal spot, the exit to the zone you came from, or
## the map's start.
func _arrival() -> Vector2:
	var entry := GameState.zone_entry
	if entry == "waypoint" and _waypoint != null:
		return _waypoint.global_position + Vector2(0, 90)
	if entry == "portal":
		var at := TownPortals.take_arrival(portal_place())
		if at.is_finite():
			return at
	for e in _exits:
		if e["target"] == entry:
			var to_start: Vector2 = (maze.start_pos - e["node"].global_position).normalized()
			return e["node"].global_position + to_start * 140.0  # just inside, so you don't walk straight back out
	return maze.start_pos


# ---------- the map's objects ----------

## The map's exits, waypoint, NPCs and quest things, and (`bosses`) its quest bosses still alive.
func _place_objects(bosses := true) -> void:
	for o in maze.portals:
		var target := String(o.get("target", "town"))
		if target == "":
			target = ActDB.TOWN
		var p := RiftPortal.new()
		p.position = Vector2(float(o.x), float(o.y))
		add_child(p)
		_label(p, "→ " + ActDB.zone_name(target), Color(0.85, 0.7, 1.0))
		_exits.append({"node": p, "target": target})
	for o in MapData.objects_of(maze.data, "waypoint"):
		_waypoint = _add_waypoint(Vector2(float(o.x), float(o.y)))
	for o in MapData.objects_of(maze.data, "npc"):
		_add_npc(o)
	for o in MapData.objects_of(maze.data, "quest_object"):
		_add_quest_object(o)
	for o in MapData.objects_of(maze.data, "trigger"):
		_triggers.append(o)
	for o in MapData.objects_of(maze.data, "boss"):
		if bosses and Quests.boss_alive(String(o.get("id", ""))):
			_spawn_boss(o)


## This game hosts the party's zone: its monsters, as on a solo visit (Coop).
func start_host() -> void:
	_spawn_packs()
	for o in MapData.objects_of(maze.data, "boss"):
		if Quests.boss_alive(String(o.get("id", ""))):
			_spawn_boss(o)


## A copy of the host's monster (Coop): its death here is as a monster's: XP, quest credit, and loot
## rolled in this game (each player's own). A quest boss's death counts for its quest.
func coop_copy(e: Enemy, _d: Dictionary) -> void:
	var boss_id := String(e.get_meta("boss_id", ""))
	if e.is_boss and boss_id != "":
		e.died.connect(func(at: Vector2): _on_boss_died(e, boss_id, at))
		_setup_boss(e, boss_id)
	else:
		e.died.connect(func(at: Vector2): _on_monster_died(e, at))


func _add_waypoint(pos: Vector2) -> Interactable:
	var w := Interactable.new()
	w.position = pos
	w.prompt = "Waypoint"
	w.radius = WAYPOINT_REACH + 20.0
	w.action = func(): waypoint_ui.open()
	w.z_index = -1
	add_child(w)
	w.set_process(true)
	w.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var lit := zone_id in GameState.waypoints
		w.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		w.draw_circle(Vector2.ZERO, 70, Color(0.15, 0.18, 0.22, 0.85))
		w.draw_arc(Vector2.ZERO, 70, 0, TAU, 48, Color(0.55, 0.85, 1.0, 0.9) if lit else Color(0.4, 0.4, 0.45), 5.0)
		w.draw_set_transform(Vector2.ZERO)
		var glow := Color(0.5, 0.85, 1.0, 0.45 + 0.25 * sin(t * 2.5)) if lit else Color(0.4, 0.4, 0.45, 0.4)
		w.draw_rect(Rect2(-14, -95, 28, 95), Color(0.22, 0.20, 0.24))
		w.draw_rect(Rect2(-14, -95, 28, 95), glow, false, 3.0)
		w.draw_circle(Vector2(0, -105), 14, glow)
	)
	_label(w, "Waypoint", Color(0.6, 0.9, 1.0), -130.0)
	var redraw := Timer.new()
	redraw.wait_time = 0.05
	redraw.autostart = true
	redraw.timeout.connect(w.queue_redraw)
	w.add_child(redraw)
	return w


func _add_npc(o: Dictionary) -> void:
	var id := String(o.get("id", ""))
	var info := QuestDB.npc(id)
	var npc := Interactable.new()
	npc.position = Vector2(float(o.x), float(o.y))
	npc.prompt = "Talk to " + String(info["name"])
	npc.action = func(): dialogue.open(id)
	add_child(npc)
	var rig := RigSprite.new()
	rig.base_scale = 0.2
	rig.skin = String(info.get("skin", ""))
	npc.add_child(rig)
	rig.play_loop("Idle")
	rig.set_facing(float(o.get("facing", -1.0)))
	var sh := Node2D.new()
	sh.draw.connect(func(): RigSprite.draw_shadow(sh, 24.0))
	npc.add_child(sh)
	npc.move_child(sh, 0)
	_label(npc, String(info["name"]), Color(1.0, 0.9, 0.5), -130.0)
	var mk := QuestMarker.new()
	mk.npc_id = id
	mk.position = Vector2(0, -150)
	npc.add_child(mk)


## Something to use for a quest (a strongbox, a totem): there only while a quest wants it used.
func _add_quest_object(o: Dictionary) -> void:
	var id := String(o.get("id", ""))
	var it := Interactable.new()
	it.position = Vector2(float(o.x), float(o.y))
	it.prompt = String(o.get("prompt", "Use"))
	add_child(it)
	var sprite := String(o.get("sprite", ""))
	var tex := MapTheme.load_sprite(maze.theme, sprite)
	if tex == null:
		# No art: a small iron-banded chest
		var chest := Node2D.new()
		chest.draw.connect(func():
			chest.draw_rect(Rect2(-26, -34, 52, 34), Color(0.42, 0.26, 0.13))
			chest.draw_rect(Rect2(-28, -44, 56, 14), Color(0.52, 0.33, 0.16))
			for x in [-18.0, 14.0]:
				chest.draw_rect(Rect2(x, -44, 5, 44), Color(0.35, 0.35, 0.38))
			chest.draw_rect(Rect2(-5, -34, 10, 10), Color(0.95, 0.80, 0.30))
			chest.draw_rect(Rect2(-28, -44, 56, 44), Color(0.12, 0.08, 0.05), false, 2.5)
		)
		it.add_child(chest)
	else:
		var s := Sprite2D.new()
		s.texture = tex
		s.offset = Vector2(0, -tex.get_height() * 0.45)
		s.scale = Vector2.ONE * float(o.get("scale", 0.45))
		it.add_child(s)
	var glow := Node2D.new()
	glow.z_index = -1
	glow.draw.connect(func(): glow.draw_arc(Vector2.ZERO, 46, 0, TAU, 40, Color(1.0, 0.85, 0.3, 0.8), 3.0))
	it.add_child(glow)
	it.action = func():
		Quests.notify("use", id)
		_flash(String(o.get("text", "Done.")), Color(1.0, 0.88, 0.5))
		it.visible = false
		it.remove_from_group("interactables")
	_quest_objects.append({"node": it, "id": id})


func _label(parent: Node2D, text: String, col: Color, y := -110.0) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", GameCamera.text(16))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", GameCamera.text(6))
	l.size = Vector2(260, 24)
	l.position = Vector2(-130, y)
	parent.add_child(l)


# ---------- monsters ----------

func _spawn_packs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zone_id)  # the same kind at the same spot every visit
	var pool := MonsterKinds.pool(area_level)
	# The map's own packs, then more across the floor (PackSpots: the same ones every visit)
	var spots := PackSpots.for_map(maze, CELLS_PER_PACK)
	for i in spots.size():
		var o: Dictionary = spots[i]
		var kind := String(o.get("kind", ""))
		if not MonsterKinds.KINDS.has(kind):
			kind = pool[rng.randi() % pool.size()]
		var at := Vector2(float(o.x), float(o.y))
		if at.distance_to(maze.start_pos) < 400.0 or _in_boss_arena(at):
			continue
		var n := randi_range(int(o.get("min", 3)), int(o.get("max", 5)))
		var lead := MonsterAffix.roll_tier(area_level)
		var pack := "zpack_%d" % i
		for j in n:
			_spawn_enemy(at + Vector2(randf_range(-50, 50), randf_range(-50, 50)), pack, kind,
				lead if j == 0 else MonsterAffix.Tier.NORMAL)


## Whether `at` is in (or close enough to wake into) the arena of a boss still to be fought: its fight is
## its own, without the ordinary packs round it joining in from the ring's edge.
func _in_boss_arena(at: Vector2) -> bool:
	for o in MapData.objects_of(maze.data, "boss"):
		var id := String(o.get("id", ""))
		if BossDB.has(id) and Quests.boss_alive(id):
			var reach := float(BossDB.def(id).get("arena", 560.0)) + ARENA_CLEAR
			if at.distance_to(Vector2(float(o.x), float(o.y))) < reach:
				return true
	return false


func _spawn_enemy(pos: Vector2, pack: String, kind: String, tier: int) -> Enemy:
	var e := Enemy.new()
	e.position = pos
	e.target = player
	e.maze = maze
	e.aggro_range = PACK_AGGRO
	e.pack = pack
	e.max_hp = 25.0 * DungeonRun.hp_mult(area_level)
	e.touch_damage *= DungeonRun.damage_mult(area_level)
	e.speed *= DungeonRun.speed_mult(area_level)
	e.set_kind(kind)
	if tier != MonsterAffix.Tier.NORMAL:
		e.make_elite(tier, MonsterAffix.roll_affixes(tier, area_level))
	e.died.connect(func(at: Vector2): _on_monster_died(e, at))
	add_child(e)
	e.add_to_group(pack)
	return e


## A quest boss from the map: a big, tough monster of its kind with its own name (and art).
func _spawn_boss(o: Dictionary) -> void:
	var b := Enemy.new()
	b.position = Vector2(float(o.x), float(o.y))
	b.target = player
	b.maze = maze
	var boss_id := String(o.get("id", ""))
	# A boss with a fight of its own wakes inside its arena: at four fifths of the ring's radius
	b.aggro_range = float(BossDB.def(boss_id).get("arena", 750.0)) * 0.8 if BossDB.has(boss_id) else 600.0
	b.is_boss = true
	b.size_mult = float(o.get("size", 1.5))
	b.max_hp = 25.0 * DungeonRun.hp_mult(area_level)
	b.touch_damage *= DungeonRun.damage_mult(area_level)
	b.speed *= DungeonRun.speed_mult(area_level)
	b.set_kind(String(o.get("kind", "zombie")))
	b.max_hp *= float(o.get("hp", 8.0))
	if BossDB.has(boss_id):
		b.max_hp *= float(BossDB.def(boss_id).get("hp", 1.0))
	b.touch_damage *= 1.4
	b.display_name = String(o.get("name", "Boss"))
	if o.has("skin"):
		b.skin = String(o["skin"])
	b.set_meta("boss_id", boss_id)  # a party's copies know which quest boss it is
	b.died.connect(func(at: Vector2): _on_boss_died(b, boss_id, at))
	add_child(b)
	_setup_boss(b, boss_id)
	BossBrain.attach(b, boss_id)  # (nothing for a boss with no entry in BossDB: it keeps its slam)


## Makes `b` this zone's boss: its health bar, and for one with a fight of its own the ring that seals
## round it. Both the real boss and a party's copy of it come here; only the real one gets a brain.
func _setup_boss(b: Enemy, boss_id: String) -> void:
	_boss = b
	_attach_boss_bar()
	if not BossDB.has(boss_id):
		return
	var home := b.global_position
	for o in MapData.objects_of(maze.data, "boss"):
		if String(o.get("id", "")) == boss_id:
			home = Vector2(float(o.x), float(o.y))  # where it stands asleep, whenever this copy was made
	var arena := BossArena.new()
	arena.boss = b
	arena.player = player
	arena.radius = float(BossDB.def(boss_id).get("arena", 560.0))
	arena.position = home
	add_child(arena)


func _attach_boss_bar() -> void:
	if _boss_bar != null and is_instance_valid(_boss):
		_boss_bar.setup(_boss, String(_boss.get_meta("boss_id", "")))


## One of a boss's adds (BossBrain): a monster of `kind` at this zone's area level, awake at once.
func spawn_add(kind: String, at: Vector2) -> Enemy:
	var e := _spawn_enemy(at, "bossadd", kind if MonsterKinds.KINDS.has(kind) else "zombie", MonsterAffix.Tier.NORMAL)
	e.add_to_group("boss_adds")
	e.wake()
	return e


func _on_boss_died(b: Enemy, boss_id: String, at: Vector2) -> void:
	Quests.notify("kill_boss", boss_id)
	_drop_boss_loot(at, boss_id)
	_flash("%s is slain!" % b.display_name, Color(1.0, 0.6, 0.4))


func _on_monster_died(e: Enemy, at: Vector2) -> void:
	Quests.notify("kill", e.kind)
	var elite := e.tier != MonsterAffix.Tier.NORMAL
	if elite or randf() < ITEM_DROP_CHANCE:
		var r := ItemInstance.Rarity.RARE if elite and randf() < 0.4 else (ItemInstance.Rarity.MAGIC if elite or randf() < 0.45 else ItemInstance.Rarity.NORMAL)
		_drop_item(LootGenerator.roll_item(area_level + 1, r), at)
	if randf() < SHARD_DROP_CHANCE:
		var ids := CraftingDB.ORBS.keys()
		CurrencyPickup.add_to_bundle(self, "Currency", ["shard", ids[randi() % mini(4, ids.size())], 1], at)
	if randf() < (SCROLL_ELITE_CHANCE if elite else SCROLL_DROP_CHANCE):
		spawn_currency("scroll", "town_portal", 1, at)


func _drop_boss_loot(at: Vector2, boss_id := "") -> void:
	var loot: Dictionary = BossDB.def(boss_id).get("loot", {}) if BossDB.has(boss_id) else {}
	if loot.is_empty():
		loot = {"rares": 1, "magics": 1, "orbs": {"alteration": 1, "transmute": 2}, "scrolls": 2}
	var n := 0
	for i in int(loot.get("rares", 1)):
		_drop_item(LootGenerator.roll_item(area_level + 2, ItemInstance.Rarity.RARE), at + Vector2.from_angle(TAU * n / 5.0) * 40.0)
		n += 1
	for i in int(loot.get("magics", 1)):
		_drop_item(LootGenerator.roll_item(area_level + 2, ItemInstance.Rarity.MAGIC), at + Vector2.from_angle(TAU * n / 5.0) * 40.0)
		n += 1
	var orbs: Dictionary = loot.get("orbs", {})
	for orb_id in orbs:
		CurrencyPickup.add_to_bundle(self, "Currency", ["orb", orb_id, int(orbs[orb_id])], at)
	if int(loot.get("scrolls", 0)) > 0:
		spawn_currency("scroll", "town_portal", int(loot.scrolls), at)


func _drop_item(item: ItemInstance, at: Vector2) -> void:
	if item == null:
		return
	item.unidentify()  # Magic and better: a scroll or the Sage reveals it
	var pk := LootPickup.new()
	pk.item = item
	pk.delay = 0.4
	pk.position = at + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 50.0)
	add_child(pk)


func spawn_currency(kind: String, id: String, amount: int, pos: Vector2) -> void:
	var c := CurrencyPickup.new()
	c.kind = kind
	c.id = id
	c.amount = amount
	c.position = pos + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 55.0)
	add_child(c)


# ---------- loot hookup (LootPickup asks the scene) ----------

## Currency on the ground was picked up (its label tapped: CurrencyPickup); it's in the shared stash.
func currency_taken(text: String, col: Color) -> void:
	_flash(text, col)


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
	pk.delay = 1.5
	pk.position = player.global_position + player.facing * 90.0
	add_child(pk)


# ---------- each frame ----------

func _process(_delta: float) -> void:
	if _leaving or player.dead:
		return
	var p := player.global_position
	for e in _exits:
		if p.distance_to(e["node"].global_position) < EXIT_REACH and not get_tree().paused:
			_leave(e["target"], zone_id)
			return
	if _waypoint != null and not (zone_id in GameState.waypoints) and p.distance_to(_waypoint.global_position) < WAYPOINT_REACH:
		GameState.waypoints.append(zone_id)
		Quests.notify("waypoint", zone_id)
		GameState.save()
		_flash("Waypoint activated", Color(0.6, 0.9, 1.0))
	for t in _triggers.duplicate():
		if p.distance_to(Vector2(float(t.x), float(t.y))) < float(t.get("radius", 200)):
			_triggers.erase(t)
			Quests.notify("reach", String(t.get("id", "")))
			if String(t.get("text", "")) != "":
				_flash(String(t["text"]), Color(1.0, 0.88, 0.6))
	for q in _quest_objects:
		if q["node"].visible != Quests.wants("use", q["id"]):
			q["node"].visible = Quests.wants("use", q["id"])
			if q["node"].visible:
				q["node"].add_to_group("interactables")
			else:
				q["node"].remove_from_group("interactables")
	# The nearest thing to talk to or use
	_near = null
	var best := INF
	for i in get_tree().get_nodes_in_group("interactables"):
		var d: float = i.global_position.distance_to(p)
		if d < i.radius and d < best and i.visible:
			best = d
			_near = i
	_talk_btn.visible = _near != null and not get_tree().paused
	if _near != null:
		_talk_btn.text = _near.prompt
	# (a boss with its own health bar, BossBar, needs no plain label)
	var plain := is_instance_valid(_boss) and not BossDB.has(String(_boss.get_meta("boss_id", "")))
	_boss_lbl.visible = plain and not _boss._dead and _boss._aggro
	if _boss_lbl.visible:
		_boss_lbl.text = "%s   %d%%" % [_boss.display_name, int(100.0 * _boss.hp / maxf(_boss.max_hp, 1.0))]


func _unhandled_input(event: InputEvent) -> void:
	if player.dead and coop == null and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		_respawn()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and _near != null:
		_near.action.call()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == TownPortals.SCROLL_KEY:
		TownPortals.read_scroll(self)


## Fell in a party's zone and waited (PartyDeath): back at the waypoint, as when alone.
func get_up() -> void:
	_respawn()


## Died: back at the waypoint (or the entrance). A solo zone is as it was (ZoneInstances), but a boss fight
## begun starts over; a party's zone is made again.
func _respawn() -> void:
	_leave(zone_id, "waypoint" if zone_id in GameState.waypoints else "start")


func _leave(target: String, entry: String) -> void:
	_leaving = true
	ActDB.travel(get_tree(), target, entry, _stay)


## You backed out of "carry on or start over?" at an exit: you are where you were, a step back from it.
func _stay() -> void:
	_leaving = false
	if is_instance_valid(player):
		for e in _exits:
			var away: Vector2 = player.global_position - e["node"].global_position
			if away.length() < EXIT_REACH + 40.0:
				player.global_position = e["node"].global_position + (away.normalized() if away.length() > 1.0 else Vector2.DOWN) * (EXIT_REACH + 90.0)


## Where a town portal read here stands (TownPortals): this zone (the party's copy of it).
func portal_place() -> Dictionary:
	return {"kind": "zone", "zone": zone_id, "inst": _inst}


## Through a town portal (yours or a party member's: TownPortals): to town, and what lies on the
## ground here waits for you.
func portal_to_town() -> void:
	if _leaving:
		return
	if coop != null:  # (a solo zone is kept whole: its loot stays where it lies)
		TownPortals.remember_loot(self, portal_place())
	_leave(ActDB.TOWN, "portal")


# ---------- HUD ----------

func _build_hud() -> void:
	var layer := GameHud.build(self, player)
	_hud_layer = layer
	var info := VBoxContainer.new()
	info.position = Vector2(16, 12)
	info.add_theme_constant_override("separation", 6)
	layer.add_child(info)
	var portrait := HirelingPortrait.new()  # your hireling, top left: tap for its equipment
	portrait.on_open = func(): menu.open("hireling")
	info.add_child(portrait)
	if Net.party_ui != null:
		Net.party_ui.dock(info)  # the party list stands under the portrait
	Minimap.add(layer, self)
	var title := UIKit.label("%s   •   Area level %d" % [ActDB.zone_name(zone_id), area_level], 19, Color(1.0, 0.9, 0.6))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	info.add_child(title)
	var tracker := QuestTracker.new()
	tracker.open_log.connect(func(): quest_log.open())
	info.add_child(tracker)

	TownPortals.add_button(layer, self)

	_talk_btn = UIKit.stone_button("", Vector2(0, 0), 22)
	_talk_btn.visible = false
	_talk_btn.pressed.connect(func():
		if _near != null:
			_near.action.call()
	)
	layer.add_child(_talk_btn)
	_talk_btn.anchor_left = 0.5
	_talk_btn.anchor_right = 0.5
	_talk_btn.anchor_top = 1.0
	_talk_btn.anchor_bottom = 1.0
	_talk_btn.offset_left = -170
	_talk_btn.offset_right = 170
	_talk_btn.offset_top = -216
	_talk_btn.offset_bottom = -160

	_boss_lbl = UIKit.label("", 22, Color(1.0, 0.55, 0.45))
	_boss_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_lbl.add_theme_constant_override("outline_size", 7)
	_boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_lbl.offset_left = -300
	_boss_lbl.offset_right = 300
	_boss_lbl.offset_top = 14
	_boss_lbl.visible = false
	layer.add_child(_boss_lbl)
	_boss_bar = BossBar.new()
	layer.add_child(_boss_bar)
	_attach_boss_bar()  # (a boss made before the HUD was)

	_toast = UIKit.label("", 26, Color.WHITE)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.offset_left = -500
	_toast.offset_right = 500
	_toast.offset_top = -170
	_toast.offset_bottom = -120
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

	_death = UIKit.label("YOU DIED\nTap or press any key to return to the waypoint", 28, Color(1.0, 0.4, 0.35))
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.add_theme_color_override("font_outline_color", Color.BLACK)
	_death.add_theme_constant_override("outline_size", 8)
	_death.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death.visible = false
	layer.add_child(_death)


func _flash(msg: String, col := Color.WHITE) -> void:
	if msg == "":
		return
	_toast.text = msg
	_toast.add_theme_color_override("font_color", col)
	var t := create_tween()
	t.tween_property(_toast, "modulate:a", 1.0, 0.2)
	t.tween_interval(2.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.6)
