class_name DungeonRun
extends Node
## One rift run at GameState.rift_level: kill KILL_TARGET monsters to summon the boss, kill the
## boss to finish. Only the boss drops loot: its own rewards plus everything the horde you killed
## would have dropped (see horde_loot). Higher levels make monsters tougher and rewards richer. Finishing under
## TIME_LIMIT gives bonus loot and, at your highest level, unlocks the next rift level.
## All tuning numbers are here.

signal boss_summoned(pos: Vector2)
signal finished(on_time: bool)

enum State { FIGHTING, BOSS, COMPLETE, FAILED }

const KILL_TARGET := 30
const TIME_LIMIT := 240.0       # seconds; beat it for the bonus rewards
const BOSS_HP := 700.0
const BOSS_SPEED := 85.0
const BOSS_DAMAGE := 22.0
var boss_kind := MonsterKinds.random_boss()  # this rift's boss (MonsterKinds.BOSSES)
var boss_name: String:
	get: return String(MonsterKinds.BOSSES[boss_kind]["name"])

# Rewards. Standard: 2 Magic items, plus a chance at a Rare.
# Under the time limit: 1 guaranteed Rare, 2 more items that are each Rare or Magic, and higher item level.
const STD_MAGIC := 2
const STD_RARE_CHANCE := 0.25
const FAST_RARE_GUARANTEED := 1
const FAST_EXTRA_ITEMS := 2
const FAST_RARE_CHANCE := 0.5
const FAST_ILVL_BONUS := 3
const BOSS_LEGENDARY_CHANCE := 0.12  # +3% per rift level above 1, +10% for a fast clear
const BOSS_SET_CHANCE := 0.08        # +2% per rift level above 1, +8% for a fast clear
const PLAN_CHANCE := 0.25            # Legendary / Set plan: +3% per rift level above 1, +10% fast

# The horde's share of the boss loot, rolled once per monster killed
const HORDE_ITEM_CHANCE := 0.15   # chance per kill of an extra item from the boss
const HORDE_RUNE_CHANCE := 0.06
const HORDE_GEM_CHANCE := 0.08
## Runes (SocketRune) for runewords: per monster killed, and one from every boss, rolled
## BOSS_SOCKET_RUNE_BOOST ranks higher (within what the rift level can drop).
const HORDE_SOCKET_RUNE_CHANCE := 0.05
const BOSS_SOCKET_RUNE_BOOST := 3

# Rift level scaling (level 1 = base game). See the static helpers below.
const HP_GROWTH := 1.18        # monster & boss life x this per level
const DAMAGE_GROWTH := 1.12    # monster & boss damage x this per level
const SPEED_PER_LEVEL := 0.02  # +2% move speed per level (capped at +40%)
const ILVL_PER_LEVEL := 2      # item level bonus per level
const REWARD_PER_LEVEL := 0.25 # +25% shards / orbs per level
const EXTRA_ITEM_EVERY := 3    # one more boss item every N levels

var level := 1
var forced_level := 0  ## a party rift's level (the opener's pick), instead of yours
## A party rift followed from the host's game (Coop): its kills, time and stage come from the host
## (apply_net_state), and its boss arrives as a copy (boss_arrived).
var remote := false
var unlocked_next := false
var state := State.FIGHTING
var kills := 0
var elapsed := 0.0
var player: Player
var main: Node2D
var boss: Enemy = null
var on_time := false
var rewards: Array[ItemInstance] = []
var extra_drops := {}
var recipe_drop := ""
var plan_drop := ""  # Legendary / Set plan dropped by the boss, "" if none
var rune_drop := ""
var bonus_runes: Array[String] = []
var bonus_gems: Array[String] = []
var skill_gem_drop := ""

var _layer: CanvasLayer
var _kill_label: Label
var _kill_bar: ProgressBar
var _time_label: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _banner: Label


func _ready() -> void:
	level = forced_level if forced_level > 0 else clampi(GameState.rift_level, 1, GameState.rift_unlocked)
	_build_hud()
	player.died.connect(_on_player_died)
	_update_hud()


func _process(delta: float) -> void:
	if state == State.FIGHTING or state == State.BOSS:
		elapsed += delta  # stops while the inventory is open (the tree is paused)
	_update_hud()


func spawning_allowed() -> bool:
	return state == State.FIGHTING


## weight: how much the kill counts towards the boss (Elites and Legendaries count for more).
func on_enemy_killed(weight := 1) -> void:
	if state != State.FIGHTING or remote:
		return
	kills = mini(kills + weight, KILL_TARGET)
	if kills >= KILL_TARGET:
		_summon_boss()


# ---------- boss ----------

func _summon_boss() -> void:
	state = State.BOSS
	if remote:
		return  # the host's boss arrives as a copy (boss_arrived)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.call("_die")  # the summoning wipes the trash so the boss fight is clean
	var b := Enemy.new()
	b.is_boss = true
	b.size_mult = 2.0
	b.display_name = boss_name
	b.skin = String(MonsterKinds.BOSSES[boss_kind]["skin"])
	b.max_hp = BOSS_HP * hp_mult(level) * Coop.hp_scale()
	b.speed = BOSS_SPEED * speed_mult(level)
	b.touch_damage = BOSS_DAMAGE * damage_mult(level)
	b.target = player
	if main.maze != null:
		b.maze = main.maze
		b.position = main.maze.random_floor_near(player.global_position, 300.0, 520.0)
	else:
		b.position = player.global_position + Vector2.from_angle(randf() * TAU) * 450.0
	main.add_child(b)
	boss_arrived(b)


## The boss is here: yours, or in a party rift a copy of the host's.
func boss_arrived(b: Enemy) -> void:
	state = State.BOSS
	b.died.connect(_on_boss_died)
	b.hp_changed.connect(func(h, m): _boss_bar.value = maxf(h, 0.0) / m * 100.0)
	boss = b
	_boss_name.text = boss_name
	_boss_bar.value = 100.0
	_boss_box.visible = true
	_show_banner("%s awakens!" % boss_name, Color(0.85, 0.6, 1.0))
	boss_summoned.emit(b.position)


func _on_boss_died(pos: Vector2) -> void:
	if state != State.BOSS:
		return
	state = State.COMPLETE
	on_time = elapsed <= TIME_LIMIT
	_boss_box.visible = false
	rewards = roll_rewards(on_time, item_level(level, kills), level)
	# The boss always leaves a flask (Magic or better when beaten in time)
	rewards.append(LootGenerator.roll_item(item_level(level, kills),
		ItemInstance.Rarity.MAGIC if on_time else -1, "flask"))
	for i in kills:
		if randf() < HORDE_ITEM_CHANCE:
			rewards.append(LootGenerator.roll_item(item_level(level, i)))
	# Beating your highest rift in time opens the next one. In a party's rift above your highest it
	# opens only your next one: being carried goes up a level at a time.
	if on_time and level >= GameState.rift_unlocked:
		GameState.rift_unlocked += 1
		GameState.rift_level = GameState.rift_unlocked
		unlocked_next = true
		Net.update_looks()  # the party sees your new highest
	for i in rewards.size():
		var pk := LootPickup.new()
		pk.item = rewards[i]
		pk.item.unidentify()  # Magic and better: a scroll or the Sage reveals it
		pk.delay = 0.8
		pk.position = pos + Vector2.from_angle(TAU * i / rewards.size() + 0.5) * (70.0 + 12.0 * (i % 3))
		main.add_child(pk)
	# Everything else drops on the ground round the boss too, labelled like the gear: orbs and shards,
	# runes, gems, a skill gem (tap a label and it goes into the shared stash)
	extra_drops = scale_drops(CraftingDB.boss_drops(on_time), level)
	horde_loot(extra_drops)
	GameState.runs_cleared += 1
	rune_drop = RuneDef.DB.random_drop(level, true)
	bonus_runes.append(rune_drop)
	# A skill gem the player is (or will soon be) able to use
	var gems := SkillTree.active_skills().filter(func(s): return SkillTree.gem_level_req(s.id) <= GameState.level + 3)
	if not gems.is_empty():
		skill_gem_drop = gems.pick_random().id
	bonus_gems.append(GemDef.random_drop(mini(GemDef.MAX_TIER, 2 + int(level / 3.0) + (1 if on_time else 0))))
	bonus_gems.append(SocketRune.random_drop(level, BOSS_SOCKET_RUNE_BOOST))
	var piles := {}  # [kind, id] -> how many
	for key in ["orbs", "shards"]:
		for k in extra_drops[key]:
			if int(extra_drops[key][k]) > 0:
				piles[["orb" if key == "orbs" else "shard", k]] = int(extra_drops[key][k])
	for rid in bonus_runes:
		piles[["rune", rid]] = int(piles.get(["rune", rid], 0)) + 1
	for gid in bonus_gems:
		piles[["gem", gid]] = int(piles.get(["gem", gid], 0)) + 1
	if skill_gem_drop != "":
		piles[["skill_gem", skill_gem_drop]] = 1
	var keys := piles.keys()
	for i in keys.size():
		var at: Vector2 = pos + Vector2.from_angle(TAU * i / keys.size()) * (140.0 + 30.0 * (i % 2))
		main.spawn_currency(keys[i][0], keys[i][1], piles[keys[i]], at)
	recipe_drop = GameState.random_unknown_recipe("drop")
	if recipe_drop == "":
		recipe_drop = GameState.random_unknown_recipe("vendor")
	if recipe_drop != "":
		main.spawn_currency("recipe", recipe_drop, 1, pos + Vector2(0, 80))
	# Legendary / Set plans: farm bosses to collect them all (better odds in harder / faster rifts)
	if randf() < minf(PLAN_CHANCE + 0.03 * (level - 1) + (0.10 if on_time else 0.0), 0.7):
		plan_drop = GameState.random_unknown_recipe("plan")
		if plan_drop != "":
			main.spawn_currency("recipe", plan_drop, 1, pos + Vector2(60, 90))
	_cleared(pos)
	finished.emit(on_time)


# ---------- party rifts ----------

## What the followers' runs need: stage, kills, time and which boss.
func net_state() -> Dictionary:
	return {"s": int(state), "k": kills, "e": elapsed, "b": boss_kind}


func apply_net_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	kills = int(d.get("k", kills))
	elapsed = float(d.get("e", elapsed))
	boss_kind = String(d.get("b", boss_kind))
	if int(d.get("s", state)) == State.BOSS and state == State.FIGHTING:
		state = State.BOSS  # its boss arrives as a copy
	elif int(d.get("s", state)) == State.FAILED:
		party_wiped()  # everyone in it is down


# ---------- rift level scaling ----------

static func hp_mult(lvl: int) -> float:
	return pow(HP_GROWTH, lvl - 1)


static func damage_mult(lvl: int) -> float:
	return pow(DAMAGE_GROWTH, lvl - 1)


static func speed_mult(lvl: int) -> float:
	return 1.0 + minf(SPEED_PER_LEVEL * (lvl - 1), 0.4)


static func reward_mult(lvl: int) -> float:
	return 1.0 + REWARD_PER_LEVEL * (lvl - 1)


## Item level for drops: grows with kills during the run and with the rift level.
static func item_level(lvl: int, kill_count: int) -> int:
	return 1 + int(kill_count / 8.0) + ILVL_PER_LEVEL * (lvl - 1)


## Multiplies the shard and orb amounts of a drop table by the level's reward bonus.
static func scale_drops(d: Dictionary, lvl: int) -> Dictionary:
	var m := reward_mult(lvl)
	for key in ["shards", "orbs"]:
		var sub: Dictionary = d.get(key, {})
		for k in sub:
			sub[k] = int(round(int(sub[k]) * m))
	return d


## Adds what the monsters you killed would have dropped: their shards and orbs into `drops`, and
## runes and gems into bonus_runes / bonus_gems (all dropped round the boss: _on_boss_died).
func horde_loot(drops: Dictionary) -> void:
	for i in kills:
		var d := scale_drops(CraftingDB.monster_drops(item_level(level, i)), level)
		for key in ["shards", "orbs"]:
			var into: Dictionary = drops[key]
			for k in d[key]:
				into[k] = int(into.get(k, 0)) + int(d[key][k])
		if randf() < HORDE_RUNE_CHANCE:
			bonus_runes.append(RuneDef.DB.random_drop(level))
		if randf() < HORDE_GEM_CHANCE:
			bonus_gems.append(GemDef.random_drop(1 + int(i / 25.0) + int(level / 3.0)))
		if randf() < HORDE_SOCKET_RUNE_CHANCE:
			bonus_gems.append(SocketRune.random_drop(level))


static func roll_rewards(fast: bool, ilvl: int, rift_lvl: int = 1) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var M := ItemInstance.Rarity.MAGIC
	var R := ItemInstance.Rarity.RARE
	var rare_bonus := 0.04 * (rift_lvl - 1)
	for i in int((rift_lvl - 1) / float(EXTRA_ITEM_EVERY)):
		out.append(LootGenerator.roll_item(ilvl, R if randf() < 0.4 + rare_bonus else M))
	if fast:
		var lvl := ilvl + FAST_ILVL_BONUS
		for i in FAST_RARE_GUARANTEED:
			out.append(LootGenerator.roll_item(lvl, R))
		for i in FAST_EXTRA_ITEMS:
			out.append(LootGenerator.roll_item(lvl, R if randf() < FAST_RARE_CHANCE + rare_bonus else M))
	else:
		for i in STD_MAGIC:
			out.append(LootGenerator.roll_item(ilvl, M))
		if randf() < STD_RARE_CHANCE + rare_bonus:
			out.append(LootGenerator.roll_item(ilvl, R))
	# Bosses are where Legendary and Set items mostly come from; better odds in harder / faster rifts
	var lvl_bonus := float(rift_lvl - 1)
	if randf() < minf(BOSS_LEGENDARY_CHANCE + 0.03 * lvl_bonus + (0.10 if fast else 0.0), 0.75):
		_append_unique(out, ilvl, false)
	if randf() < minf(BOSS_SET_CHANCE + 0.02 * lvl_bonus + (0.08 if fast else 0.0), 0.6):
		_append_unique(out, ilvl, true)
	return out


static func _append_unique(out: Array[ItemInstance], ilvl: int, set_item: bool) -> void:
	var u := UniqueItems.roll(ilvl, set_item, LootGenerator.smart_class)
	if u != null:
		out.append(u)


func _on_player_died() -> void:
	if main.get("coop") != null:
		return  # a party's rift fails only when everyone is down (PartyDeath)
	party_wiped()


## The run has failed: you died, or in a party's rift everyone is down.
func party_wiped() -> void:
	if state == State.FIGHTING or state == State.BOSS:
		state = State.FAILED
		_boss_box.visible = false


# ---------- HUD ----------

static func fmt_time(t: float) -> String:
	var s := int(ceil(maxf(t, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)

	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.custom_minimum_size = Vector2(420, 0)
	top.add_theme_constant_override("separation", 4)
	_layer.add_child(top)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -210
	top.offset_right = 210
	top.offset_top = 10

	_kill_label = _label(22)
	top.add_child(_kill_label)
	_kill_bar = ProgressBar.new()
	_kill_bar.max_value = KILL_TARGET
	_kill_bar.show_percentage = false
	_kill_bar.custom_minimum_size = Vector2(0, 14)
	_kill_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_kill_bar)
	_time_label = _label(20)
	top.add_child(_time_label)

	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_boss_box)
	_boss_name = _label(22)
	_boss_name.modulate = Color(0.85, 0.6, 1.0)
	_boss_box.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(0, 20)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.7, 0.15, 0.2)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	_boss_box.add_child(_boss_bar)

	_banner = _label(40)
	_banner.visible = false
	_layer.add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 0)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.offset_left = 0
	_banner.offset_right = 0
	_banner.offset_top = 200


func _label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_hud() -> void:
	match state:
		State.FIGHTING:
			_kill_label.text = "Rift %d  —  Slay the horde  %d / %d" % [level, kills, KILL_TARGET]
		State.BOSS:
			_kill_label.text = "Rift %d  —  Defeat %s" % [level, boss_name]
		State.COMPLETE:
			_kill_label.text = "Rift %d cleared" % level
		State.FAILED:
			_kill_label.text = "You have fallen"
	_kill_bar.value = kills
	_kill_bar.visible = state == State.FIGHTING
	var left := TIME_LIMIT - elapsed
	if state == State.COMPLETE:
		_time_label.text = "Cleared in %s" % fmt_time(elapsed)
		_time_label.modulate = Color(0.5, 1.0, 0.5) if on_time else Color(0.8, 0.8, 0.8)
	elif left > 0.0:
		_time_label.text = "Bonus loot if cleared in %s" % fmt_time(left)
		_time_label.modulate = Color(1, 0.85, 0.3) if left > 30.0 else Color(1, 0.4, 0.3)
	else:
		_time_label.text = "Bonus time over  (%s)" % fmt_time(elapsed)
		_time_label.modulate = Color(0.7, 0.7, 0.7)


## Big centre-screen message (maze names, boss awakening...).
func announce(text: String, col: Color) -> void:
	_show_banner(text, col)


func _show_banner(text: String, col: Color, secs := 2.0) -> void:
	_banner.text = text
	_banner.modulate = col
	_banner.visible = true
	var t := create_tween()
	t.tween_interval(secs)
	t.tween_property(_banner, "modulate:a", 0.0, 0.8)
	t.tween_callback(func(): _banner.visible = false)


## Cleared: "Rift N cleared" and the time in the middle of the screen a while, and a town portal
## near where the boss fell (tap its label to go home). What dropped lies on the ground to see.
func _cleared(boss_at: Vector2) -> void:
	var text := "Rift %d cleared\n%s" % [level, fmt_time(elapsed)]
	if unlocked_next:
		text += "\nRift %d unlocked!" % GameState.rift_unlocked
	_show_banner(text, Color(1.0, 0.86, 0.45) if on_time else Color(0.92, 0.90, 0.84), 4.5)
	var tp := TownPortal.new()
	var maze: MazeMap = main.get("maze")
	tp.position = maze.random_floor_near(boss_at, 230.0, 320.0) if maze != null else boss_at + Vector2(0, 240)
	main.add_child(tp)
