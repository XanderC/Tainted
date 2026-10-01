class_name DungeonRun
extends Node
## One dungeon instance: kill KILL_TARGET monsters to summon the boss, kill the boss to
## finish. Finish under TIME_LIMIT for better rewards. All tuning numbers are here.

signal boss_summoned(pos: Vector2)
signal finished(on_time: bool)

enum State { FIGHTING, BOSS, COMPLETE, FAILED }

const KILL_TARGET := 30
const TIME_LIMIT := 240.0       # seconds; beat it for the bonus rewards
const BOSS_HP := 700.0
const BOSS_SPEED := 85.0
const BOSS_DAMAGE := 22.0
const BOSS_NAME := "The Grave Warden"

# Rewards. Standard: 2 Magic items, plus a chance at a Rare.
# Under the time limit: 1 guaranteed Rare, 2 more items that are each Rare or Magic, and higher item level.
const STD_MAGIC := 2
const STD_RARE_CHANCE := 0.25
const FAST_RARE_GUARANTEED := 1
const FAST_EXTRA_ITEMS := 2
const FAST_RARE_CHANCE := 0.5
const FAST_ILVL_BONUS := 3

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

var _layer: CanvasLayer
var _kill_label: Label
var _kill_bar: ProgressBar
var _time_label: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _banner: Label
var _result: PanelContainer
var _result_text: RichTextLabel


func _ready() -> void:
	_build_hud()
	player.died.connect(_on_player_died)
	_update_hud()


func _process(delta: float) -> void:
	if state == State.FIGHTING or state == State.BOSS:
		elapsed += delta  # stops while the inventory is open (the tree is paused)
	_update_hud()


func spawning_allowed() -> bool:
	return state == State.FIGHTING


func on_enemy_killed() -> void:
	if state != State.FIGHTING:
		return
	kills += 1
	if kills >= KILL_TARGET:
		_summon_boss()


# ---------- boss ----------

func _summon_boss() -> void:
	state = State.BOSS
	for e in get_tree().get_nodes_in_group("enemies"):
		e.call("_die")  # the summoning wipes the trash so the boss fight is clean
	var b := Enemy.new()
	b.is_boss = true
	b.size_mult = 2.0
	b.display_name = BOSS_NAME
	b.max_hp = BOSS_HP
	b.speed = BOSS_SPEED
	b.touch_damage = BOSS_DAMAGE
	b.target = player
	b.position = player.global_position + Vector2.from_angle(randf() * TAU) * 450.0
	b.died.connect(_on_boss_died)
	b.hp_changed.connect(func(h, m): _boss_bar.value = maxf(h, 0.0) / m * 100.0)
	main.add_child(b)
	boss = b
	_boss_name.text = BOSS_NAME
	_boss_bar.value = 100.0
	_boss_box.visible = true
	_show_banner("%s awakens!" % BOSS_NAME, Color(0.85, 0.6, 1.0))
	boss_summoned.emit(b.position)


func _on_boss_died(pos: Vector2) -> void:
	if state != State.BOSS:
		return
	state = State.COMPLETE
	on_time = elapsed <= TIME_LIMIT
	_boss_box.visible = false
	rewards = roll_rewards(on_time, 1 + int(kills / 8.0))
	for i in rewards.size():
		var pk := LootPickup.new()
		pk.item = rewards[i]
		pk.delay = 0.8
		pk.position = pos + Vector2.from_angle(TAU * i / rewards.size() + 0.5) * 70.0
		main.add_child(pk)
	# Materials, orbs and gold go straight to your stash; a recipe page drops on the ground.
	extra_drops = CraftingDB.boss_drops(on_time)
	GameState.grant(extra_drops)
	GameState.runs_cleared += 1
	recipe_drop = GameState.random_unknown_recipe("drop")
	if recipe_drop == "":
		recipe_drop = GameState.random_unknown_recipe("vendor")
	if recipe_drop != "":
		main.spawn_currency("recipe", recipe_drop, 1, pos + Vector2(0, 80))
	_show_result()
	finished.emit(on_time)


static func roll_rewards(fast: bool, ilvl: int) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var M := ItemInstance.Rarity.MAGIC
	var R := ItemInstance.Rarity.RARE
	if fast:
		var lvl := ilvl + FAST_ILVL_BONUS
		for i in FAST_RARE_GUARANTEED:
			out.append(LootGenerator.roll_item(lvl, R))
		for i in FAST_EXTRA_ITEMS:
			out.append(LootGenerator.roll_item(lvl, R if randf() < FAST_RARE_CHANCE else M))
	else:
		for i in STD_MAGIC:
			out.append(LootGenerator.roll_item(ilvl, M))
		if randf() < STD_RARE_CHANCE:
			out.append(LootGenerator.roll_item(ilvl, R))
	return out


func _on_player_died() -> void:
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

	_result = PanelContainer.new()
	_result.visible = false
	_layer.add_child(_result)
	_result.anchor_left = 0.0
	_result.anchor_right = 0.0
	_result.anchor_top = 0.0
	_result.offset_left = 16  # left side, so the loot in the middle and the buttons stay clear
	_result.offset_right = 376
	_result.offset_top = 200
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_result.add_child(vb)
	_result_text = RichTextLabel.new()
	_result_text.bbcode_enabled = true
	_result_text.fit_content = true
	_result_text.scroll_active = false
	_result_text.add_theme_font_size_override("normal_font_size", 19)
	_result_text.add_theme_font_size_override("bold_font_size", 24)
	vb.add_child(_result_text)
	var btn := Button.new()
	btn.text = "Return to town"
	btn.custom_minimum_size = Vector2(0, 56)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func(): main.return_to_town())
	vb.add_child(btn)


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
			_kill_label.text = "Slay the horde  %d / %d" % [kills, KILL_TARGET]
		State.BOSS:
			_kill_label.text = "Defeat %s" % BOSS_NAME
		State.COMPLETE:
			_kill_label.text = "Dungeon cleared"
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


func _show_banner(text: String, col: Color) -> void:
	_banner.text = text
	_banner.modulate = col
	_banner.visible = true
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(_banner, "modulate:a", 0.0, 0.8)
	t.tween_callback(func(): _banner.visible = false)


func _show_result() -> void:
	var t := "[center][b][color=#f0c040]DUNGEON CLEARED[/color][/b][/center]\n"
	t += "Time  %s    Kills  %d\n" % [fmt_time(elapsed), kills]
	if on_time:
		t += "[color=#66dd66]Under the time limit. Bonus loot![/color]\n"
	else:
		t += "[color=#aaaaaa]Over the %s limit. Standard loot.[/color]\n" % fmt_time(TIME_LIMIT)
	t += "\n[b]Rewards on the ground:[/b]\n"
	for it in rewards:
		var col: String = ItemInstance.RARITY_COLORS[it.rarity].to_html(false)
		t += "  [color=#%s]%s[/color]\n" % [col, it.display_name]
	t += "\n[b]Added to your stash:[/b]\n"
	t += "  %d Gold\n" % int(extra_drops.gold)
	for k in extra_drops.materials:
		t += "  %d %s\n" % [extra_drops.materials[k], CraftingDB.MATERIALS[k].name]
	for k in extra_drops.orbs:
		t += "  %d %s\n" % [extra_drops.orbs[k], CraftingDB.ORBS[k].name]
	if recipe_drop != "":
		t += "[color=#e6bf80]A recipe page dropped: %s[/color]\n" % CraftingDB.RECIPES[recipe_drop].name
	t += "[color=#888888]Walk over the items to collect,\nthen return to town.[/color]"
	_result_text.text = t
	_result.visible = true
	_banner.visible = false
