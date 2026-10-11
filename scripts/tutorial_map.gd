class_name TutorialMap
extends Node2D
## First steps for a new character (MazeLibrary "Tutorial"): a short strip of rooms leading to the
## hub. Each stage shows a hint at the top of the screen and an arrow to where to go next:
##   ALTAR  - walk to the altar and pick a first skill gem
##   SOCKET - (skipped: the altar sockets it into the main attack slot, since gems are changed
##            at the stash in town and the tutorial has none)
##   FIGHT  - a training monster appears: kill it with the new skill
##   EQUIP  - it dropped an item: pick it up and equip it
##   PORTAL - step into the portal to reach Ashfall Outpost (the town)
## Progress is saved (GameState.tutorial_stage), so quitting midway resumes at the same stage.

const SCENE := "res://scenes/tutorial.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"
enum Stage { ALTAR, SOCKET, FIGHT, EQUIP, PORTAL }
## The first skill gems on offer at the altar (all usable at level 1).
const STARTER_GEMS := ["cleave", "frenzy", "sundering_strike"]
const PORTAL_REACH := 70.0

const HINTS := {
	Stage.ALTAR: "[b]Welcome to Tainted![/b]\nMove with the [color=#ffd54a]left joystick[/color] (or WASD / arrow keys). " +
		"Walk to the glowing [color=#7dd3fc]altar[/color] and take your first skill gem.",
	Stage.SOCKET: "[b]Socket your skill gem.[/b]\nTap [color=#ffd54a]🎒 BAG[/color] (top right), open the " +
		"[color=#ffd54a]Skill Gems[/color] tab, and drag your gem onto the [color=#ffd54a]⚔ main attack[/color] slot in the Skills panel. Then close the bag.",
	Stage.FIGHT: "[b]A Husk blocks the way![/b]\nYour gem is in your [color=#ffd54a]⚔ main attack[/color] slot. Walk up to it and tap the big " +
		"[color=#ffd54a]attack button[/color] (bottom right; Space or click on a computer). Hits build [color=#fb923c]Adrenaline[/color] for stronger skills later. " +
		"(You change skill gems at the [color=#ffd54a]stash[/color] in town.)",
	Stage.EQUIP: "[b]It dropped a Magic weapon![/b]\nTap its name on the ground to pick it up, then equip it in place of your Rusty Sword: " +
		"tap [color=#4ade80]Equip[/color] on the popup, or open your [color=#ffd54a]🎒 BAG[/color] and drag it onto the Main Hand slot.",
	Stage.PORTAL: "[b]You're ready.[/b]\nStep into the [color=#c084fc]portal[/color] to reach Ashfall Outpost, your home base. " +
		"Its traders, crafters and the Rift Gate await.",
}

var player: Player
var maze: MazeMap
var menu: GameMenu
var skill_tree_ui: SkillTreeUI
var upgrade_popup_ui: CanvasLayer
var portal: RiftPortal
var _altar: Interactable
var _monster: Enemy
var _arrow: PortalArrow
var _hint: RichTextLabel
var _step_lbl: Label
var _talk_btn: Button
var _choice: Control
var _toast: Label
var _fade: ColorRect
var _finishing := false
var _drop_spot := Vector2.ZERO

const UpgradePopupUIScript = preload("res://scripts/upgrade_popup_ui.gd")


func _ready() -> void:
	y_sort_enabled = true
	get_tree().paused = false
	maze = MazeMap.new()
	maze.setup("tutorial")
	add_child(maze)
	_drop_spot = maze.markers["x"][0]

	player = Player.new()
	player.class_def = ClassLibrary.get_class_def(GameState.char_class)
	player.position = maze.start_pos
	add_child(player)
	var cam := Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(maze.cols * MazeMap.CELL)
	cam.limit_bottom = int(maze.rows * MazeMap.CELL)
	player.add_child(cam)
	player.died.connect(_on_player_died)

	_add_altar(maze.markers["A"][0])
	portal = RiftPortal.new()
	portal.position = maze.portal_pos
	add_child(portal)

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

	# A plain starting sword, so the Husk's better drop has to be equipped by hand
	if _stage() == Stage.ALTAR and player.equipment.is_empty():
		var sword := ItemInstance.from_dict({"base": "rusty_sword", "rarity": 0, "ilvl": 1, "sockets": 0})
		if sword != null and player.can_equip(sword):
			player.equip_to(sword, "weapon", true)
	_enter_stage(clampi(GameState.tutorial_stage, Stage.ALTAR, Stage.PORTAL), true)


func _stage() -> int:
	return GameState.tutorial_stage


## Set up the world for a stage. `resuming` = loaded at this stage (re-create what it needs).
func _enter_stage(s: int, resuming := false) -> void:
	GameState.tutorial_stage = s
	GameState.save()
	_hint.text = HINTS[s]
	_step_lbl.text = "TUTORIAL  •  STEP %d / %d" % [s + 1, Stage.size()]
	portal.active = s == Stage.PORTAL
	match s:
		Stage.ALTAR: _point_at(_altar, "Altar", Color(0.49, 0.83, 0.99))
		Stage.SOCKET: _point_at(null)
		Stage.FIGHT:
			_spawn_monster()
			_point_at(_monster, "Husk", Color(1.0, 0.45, 0.4))
		Stage.EQUIP:
			if resuming:  # quit before picking it up: drop it again
				_drop_reward(_drop_spot)
			_point_at(null)
		Stage.PORTAL: _point_at(portal, "Portal", Color(0.80, 0.55, 1.0))
	if not resuming:
		_flash("Step %d complete!" % s if s > 0 else "")


func _process(_delta: float) -> void:
	if _finishing:
		return
	var busy := get_tree().paused
	_talk_btn.visible = _stage() == Stage.ALTAR and not busy and _choice == null \
		and player.global_position.distance_to(_altar.global_position) < _altar.radius
	match _stage():
		Stage.SOCKET:
			# Only a save made at this step lands here now: socket the gem taken at the altar for them
			if GameState.slot_skill(0) == "":
				for id in STARTER_GEMS:
					if GameState.set_slot_skill(0, id):
						break
			for i in GameState.SKILL_SLOTS:
				if GameState.slot_skill(i) != "":
					_enter_stage(Stage.FIGHT)
					break
		Stage.EQUIP:
			if player.equipment.values().any(func(it): return it.rarity >= ItemInstance.Rarity.MAGIC):
				_enter_stage(Stage.PORTAL)
		Stage.PORTAL:
			if not busy and player.global_position.distance_to(portal.global_position) < PORTAL_REACH:
				_finish()


## Tap an item's name plate to take it (LootPickup). Unlike a rift, it always goes into the bag
## (never straight into an empty slot) so equipping it is part of the lesson; upgrades offer a
## quick-equip popup. False when there's no room.
func take_loot(p: LootPickup) -> bool:
	if not player.add_to_bag(p.item):
		return false
	var it: ItemInstance = p.item
	p.queue_free()
	if player.is_better_in_slot(it):
		upgrade_popup_ui.prompt_upgrade(it, null)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and _talk_btn.visible:
		_open_choice()


# ---------- stages ----------

func _add_altar(pos: Vector2) -> void:
	_altar = Interactable.new()
	_altar.position = pos
	_altar.prompt = "Take a skill gem"
	_altar.radius = 140.0
	_altar.action = _open_choice
	_altar.z_index = -1
	add_child(_altar)
	_altar.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var glow := 0.5 + 0.5 * sin(t * 2.5)
		_altar.draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
		_altar.draw_circle(Vector2.ZERO, 70.0, Color(0.30, 0.70, 1.0, 0.18 + 0.12 * glow))
		_altar.draw_set_transform(Vector2.ZERO)
		_altar.draw_rect(Rect2(-30, -46, 60, 50), Color(0.32, 0.30, 0.36))
		_altar.draw_rect(Rect2(-30, -46, 60, 50), Color(0.15, 0.14, 0.18), false, 3.0)
		_altar.draw_rect(Rect2(-38, -54, 76, 12), Color(0.42, 0.40, 0.46))
		if _stage() == Stage.ALTAR:
			var bob := sin(t * 3.0) * 5.0
			var c := Vector2(0, -80 + bob)
			_altar.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -16), c + Vector2(13, 0), c + Vector2(0, 16), c + Vector2(-13, 0)]),
				Color(0.5, 0.85, 1.0, 0.9))
			_altar.draw_circle(c, 22.0, Color(0.5, 0.85, 1.0, 0.15 + 0.15 * glow))
	)
	var tick := Timer.new()
	tick.wait_time = 0.05
	tick.autostart = true
	tick.timeout.connect(_altar.queue_redraw)
	_altar.add_child(tick)
	var l := UIKit.label("Altar of First Steps", 16, Color(0.6, 0.85, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.custom_minimum_size = Vector2(200, 0)
	l.position = Vector2(-100, -150)
	_altar.add_child(l)


func _spawn_monster() -> void:
	if is_instance_valid(_monster):
		return
	var e := Enemy.new()
	e.position = _drop_spot
	e.target = player
	e.maze = maze
	e.aggro_range = 380.0
	e.max_hp = 45.0
	e.touch_damage = 4.0
	e.speed = 85.0
	e.display_name = "Husk"
	e.died.connect(func(pos: Vector2):
		_drop_reward(pos)
		_enter_stage(Stage.EQUIP)
	)
	add_child(e)
	_monster = e


## The Husk's drop: a Magic one-handed weapon this class can use, better than the starting sword.
func _drop_reward(pos: Vector2) -> void:
	var item: ItemInstance = null
	for i in 40:
		item = LootGenerator.roll_item(3, ItemInstance.Rarity.MAGIC, "weapon")
		if player.can_equip(item) and not item.base.two_handed and player.is_better_in_slot(item):
			break
	var pk := LootPickup.new()
	pk.item = item
	pk.delay = 0.6
	pk.position = pos + Vector2(40, 10)
	add_child(pk)
	_arrow.target = pk
	_arrow.label_text = "Item"
	_arrow.color = ItemInstance.RARITY_COLORS[item.rarity]


func _point_at(target: Node2D, label := "", col := Color.WHITE) -> void:
	_arrow.target = target
	_arrow.label_text = label
	_arrow.color = col


func _on_player_died() -> void:
	_flash("You fell! Try again...")
	get_tree().create_timer(1.6).timeout.connect(func(): get_tree().reload_current_scene())


## Into the portal: the tutorial is done, on to the town (which shows its welcome).
func _finish() -> void:
	_finishing = true
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.show_hub_intro = true
	GameState.save()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.5)
	t.tween_callback(func(): get_tree().change_scene_to_file(TOWN_SCENE))


## Skip: the usual starting skills, straight to town.
func _skip() -> void:
	GameState.give_starter_skills()
	_finish()


# ---------- the skill gem choice ----------

func _open_choice() -> void:
	if _choice != null or _stage() != Stage.ALTAR:
		return
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_choice = Control.new()
	_choice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_choice)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice.add_child(center)
	var panel := PanelContainer.new()
	var sb := UIKit.box(Color(0.07, 0.06, 0.09, 0.98), Color(0.45, 0.70, 0.95), 2, 12)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := UIKit.label("CHOOSE YOUR FIRST SKILL GEM", 24, Color(0.6, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UIKit.label("Skill gems are your attacks. Socket one into a skill slot to use it - you'll find and buy more later.", 15, UIKit.TEXT_DIM, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(820, 0)
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	for id in STARTER_GEMS:
		row.add_child(_gem_card(String(id)))


func _gem_card(id: String) -> Control:
	var sk := SkillTree.get_skill(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 0)
	var sb := UIKit.box(Color(0.10, 0.09, 0.13), sk.color, 2, 10)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var icon := TextureRect.new()
	icon.texture = IconFactory.gem_icon("skill:" + id, sk.color, 3)
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(icon)
	var n := UIKit.label("%s %s" % [sk.icon, sk.display_name], 20, sk.color.lightened(0.2))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var d := UIKit.label(sk.description, 14, Color(0.88, 0.86, 0.80), true)
	d.custom_minimum_size = Vector2(236, 0)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	var b := UIKit.button("Take %s" % sk.display_name, sk.color.darkened(0.75), sk.color, Vector2(0, 52), 17)
	b.pressed.connect(func():
		GameState.add_skill_gem(id, 1)
		GameState.set_slot_skill(0, id)  # straight into the main attack: gems change at the stash
		_choice.get_parent().queue_free()
		_choice = null
		get_tree().paused = false
		_enter_stage(Stage.FIGHT)
	)
	v.add_child(b)
	return card


# ---------- HUD ----------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var joy := VirtualJoystick.new()
	layer.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.joystick = joy

	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var button_pos := {0: Vector2(-155, -155), 1: Vector2(-280, -115), 2: Vector2(-245, -245),
		3: Vector2(-115, -280), 4: Vector2(-385, -268), 5: Vector2(-250, -372)}
	for i in button_pos:
		var b := SkillButton.new()
		b.player = player
		b.index = i
		b.position = button_pos[i]
		pad.add_child(b)
	# Flask buttons, one per slot the belt opens, growing left from this corner
	var flasks := FlaskBar.new()
	flasks.player = player
	flasks.position = Vector2(-292, -22)
	pad.add_child(flasks)

	var bars := HudBars.new()
	bars.player = player
	layer.add_child(bars)

	_arrow = PortalArrow.new()
	_arrow.player = player
	layer.add_child(_arrow)

	# The hint box, top centre
	var top := CenterContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 12
	top.offset_bottom = 12
	layer.add_child(top)
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.box(Color(0.05, 0.05, 0.08, 0.88), Color(0.95, 0.80, 0.40), 2, 10)
	sb.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", sb)
	top.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	_step_lbl = UIKit.label("", 12, Color(0.95, 0.80, 0.40))
	v.add_child(_step_lbl)
	_hint = UIKit.rich("", 16)
	_hint.custom_minimum_size = Vector2(620, 0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hint)

	_toast = UIKit.label("", 26, Color(0.45, 1.0, 0.6))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = -120
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

	_talk_btn = UIKit.button("💎 Take a skill gem", Color(0.10, 0.20, 0.30), Color(0.5, 0.85, 1.0), Vector2(380, 80), 26)
	_talk_btn.visible = false
	_talk_btn.pressed.connect(_open_choice)
	layer.add_child(_talk_btn)
	_talk_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_talk_btn.offset_left = -190
	_talk_btn.offset_right = 190
	_talk_btn.offset_top = -150
	_talk_btn.offset_bottom = -70

	var skip := UIKit.button("Skip tutorial ⏭", Color(0.10, 0.09, 0.12, 0.85), Color(0.45, 0.40, 0.35), Vector2(150, 40), 14)
	skip.pressed.connect(_skip)
	layer.add_child(skip)
	skip.position = Vector2(16, 120)

	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.0, 0.05, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func _flash(msg: String) -> void:
	if msg == "":
		return
	_toast.text = msg
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.6)
