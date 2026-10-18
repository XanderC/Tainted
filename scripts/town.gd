extends Node2D
## The hub scene, entered from the character select screen. Walk up to an NPC and tap Talk.
## Blacksmith: recipes and plans (paid in orbs).  Merchant: buy and sell.  Stash keeper: shared storage and currency.
## Jeweler: combine gems into higher tiers and remove socketed gems.
## Sage: identifies every item in your bag and stash, free.
## Rift Gate: pick a rift level, then start a run (scenes/main.tscn).

const DUNGEON_SCENE := "res://scenes/main.tscn"
const SPAWN := Vector2(0, 360)

const UpgradePopupUIScript = preload("res://scripts/upgrade_popup_ui.gd")

var player: Player
var menu: GameMenu  # character screen + inventory / vendor panels
var skill_tree_ui: SkillTreeUI
var rift_ui: RiftSelectUI
var upgrade_popup_ui: CanvasLayer
var _hud: Label
var _talk_btn: Button
var _chars_btn: Button
var _near: Interactable = null
var _gate: Node2D


func _ready() -> void:
	y_sort_enabled = true
	add_child(TownMap.new())

	player = Player.new()
	player.class_def = ClassLibrary.get_class_def(GameState.char_class)
	player.can_fight = false
	player.position = SPAWN
	add_child(player)
	var cam := Camera2D.new()
	cam.limit_left = int(TownMap.CAM_LIMIT.position.x)
	cam.limit_right = int(TownMap.CAM_LIMIT.end.x)
	cam.limit_top = int(TownMap.CAM_LIMIT.position.y)
	cam.limit_bottom = int(TownMap.CAM_LIMIT.end.y)
	player.add_child(cam)

	_add_npc("Blacksmith", "Craft", Vector2(-560, -205), {"weapon": "battle_axe", "chest": "chain_mail", "helmet": "leather_cap"},
		Color(1.0, 0.88, 0.78), "Talk to the Blacksmith", func(): menu.open_vendor("smith"))
	_add_npc("Merchant", "Buy & Sell", Vector2(580, -185), {"chest": "padded_vest", "helmet": "leather_cap"},
		Color(0.82, 0.92, 1.0), "Talk to the Merchant", func(): menu.open_vendor("shop"))
	_add_npc("Stash Keeper", "Shared Storage", Vector2(0, -270), {"helmet": "iron_helm", "weapon": "rusty_sword"},
		Color(0.92, 0.85, 1.0), "Open the Stash", func(): menu.open_vendor("stash"))
	_add_npc("Battlemaster Brom", "Passive Tree", Vector2(-240, -160), {"weapon": "rusty_sword", "chest": "chain_mail", "helmet": "iron_helm"},
		Color(0.95, 0.85, 0.7), "Open the Passive Tree", func(): skill_tree_ui.open())
	_add_npc("Jeweler", "Gems", Vector2(280, -175), {"chest": "padded_vest", "helmet": "leather_cap"},
		Color(0.80, 0.90, 1.0), "Talk to the Jeweler", func(): menu.open_vendor("jeweler"))
	_add_npc("Sage Aldous", "Identify", Vector2(-600, 150), {"chest": "padded_vest"},
		Color(0.93, 0.88, 0.72), "Talk to the Sage", _identify_all)
	_add_gate(Vector2(820, 220))

	var layer := CanvasLayer.new()
	add_child(layer)
	var joy := VirtualJoystick.new()
	layer.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.joystick = joy

	var potion_pad := Control.new()
	potion_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(potion_pad)
	potion_pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# The flask row, between the orbs at the bottom centre
	var flasks := FlaskBar.new()
	flasks.player = player
	layer.add_child(flasks)
	var swap := WeaponSwapButton.new()
	swap.player = player
	swap.position = Vector2(-110, -170)
	potion_pad.add_child(swap)

	var bars := HudBars.new()
	bars.player = player
	layer.add_child(bars)

	_hud = Label.new()
	_hud.position = Vector2(16, 80)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)

	_chars_btn = UIKit.stone_button("👥", Vector2(64, 56), 22)
	_chars_btn.tooltip_text = "Character select"
	_chars_btn.pressed.connect(_to_character_select)
	layer.add_child(_chars_btn)
	_chars_btn.anchor_left = 1.0
	_chars_btn.anchor_right = 1.0
	_chars_btn.offset_left = -336.0
	_chars_btn.offset_right = -272.0
	_chars_btn.offset_top = 16.0
	_chars_btn.offset_bottom = 72.0

	_talk_btn = Button.new()
	_talk_btn.visible = false
	_talk_btn.add_theme_font_size_override("font_size", 26)
	_talk_btn.pressed.connect(_interact)
	layer.add_child(_talk_btn)
	_talk_btn.anchor_left = 0.5
	_talk_btn.anchor_right = 0.5
	_talk_btn.anchor_top = 1.0
	_talk_btn.anchor_bottom = 1.0
	_talk_btn.offset_left = -190
	_talk_btn.offset_right = 190
	_talk_btn.offset_top = -150
	_talk_btn.offset_bottom = -70

	menu = GameMenu.new()
	menu.player = player
	add_child(menu)
	rift_ui = RiftSelectUI.new()
	rift_ui.enter_requested.connect(enter_dungeon)
	add_child(rift_ui)
	skill_tree_ui = SkillTreeUI.new()
	skill_tree_ui.can_respec = true
	skill_tree_ui.player = player
	add_child(skill_tree_ui)
	upgrade_popup_ui = UpgradePopupUIScript.new()
	upgrade_popup_ui.player = player
	add_child(upgrade_popup_ui)
	if GameState.show_hub_intro:
		GameState.show_hub_intro = false
		_show_hub_intro()


## First arrival from the tutorial: who is who in town, and where to go next.
func _show_hub_intro() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	var sb := UIKit.box(Color(0.06, 0.05, 0.08, 0.96), Color(0.95, 0.80, 0.40), 2, 12)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UIKit.label("WELCOME TO ASHFALL OUTPOST", 24, UIKit.GOLD))
	var t := UIKit.rich(
		"This is your home base. Walk up to someone and tap [b]Talk[/b]:\n" +
		"  • [color=#ffd54a]Merchant[/color] - buy skill gems, flasks and orbs, and sell loot for orbs\n" +
		"  • [color=#ffd54a]Blacksmith[/color] - forge recipes and plans\n" +
		"  • [color=#ffd54a]Stash Keeper[/color] - storage shared by all your characters\n" +
		"  • [color=#ffd54a]Jeweler[/color] - combine and remove item gems\n" +
		"  • [color=#ffd54a]Battlemaster Brom[/color] - your passive tree (you get a point every level)\n" +
		"  • [color=#ffd54a]Mystic Seraphine[/color] - reset your passive points for free\n\n" +
		"When you're ready, step into the [color=#c084fc]Rift Gate[/color] (east) to fight through rifts for loot.", 16)
	t.custom_minimum_size = Vector2(700, 0)
	v.add_child(t)
	var ok := UIKit.button("Let's go!", Color(0.14, 0.38, 0.18), Color(0.40, 1.0, 0.55), Vector2(0, 56), 20)
	ok.pressed.connect(layer.queue_free)
	v.add_child(ok)


## An item's name plate was tapped and the player reached it (LootPickup). False when there's no room.
func take_loot(p: LootPickup) -> bool:
	var better := player.is_better_in_slot(p.item)
	if not player.pick_up(p.item):
		return false
	p.queue_free()
	if better:
		upgrade_popup_ui.prompt_upgrade(p.item, null)
	return true


func _process(delta: float) -> void:
	_hud.text = "Ashfall Outpost\nChaos %d   Divine %d     Bag %d/%d cells" % [GameState.orb_count("chaos"), GameState.orb_count("divine"),
		player.bag_cells_used(), Player.BAG_SIZE]
	if _gate:
		_gate.queue_redraw()

	var best: Interactable = null
	var best_d := INF
	for i in get_tree().get_nodes_in_group("interactables"):
		var d: float = i.global_position.distance_to(player.global_position)
		if d < i.radius and d < best_d:
			best = i
			best_d = d
	var any_open: bool = (menu != null and menu.is_open()) or \
		(rift_ui != null and rift_ui.is_open()) or \
\
		(skill_tree_ui != null and skill_tree_ui.is_open())
	_near = best
	_talk_btn.visible = best != null and not any_open
	_chars_btn.visible = not any_open and not get_tree().paused
	if best != null:
		_talk_btn.text = best.prompt


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and _near != null:
		_interact()


func _interact() -> void:
	if _near != null and _near.action.is_valid():
		_near.action.call()


func _to_character_select() -> void:
	GameState.leave_character()
	get_tree().change_scene_to_file(CharacterSelect.SCENE)


func enter_dungeon() -> void:
	GameState.save()
	get_tree().change_scene_to_file(DUNGEON_SCENE)


# ---------- building the town's people ----------

## The Sage: identify everything at once, then show the bag so you can see what you found.
func _identify_all() -> void:
	var n := GameState.identify_all(player)
	menu.open()
	menu.feedback("The Sage identified %d item%s." % [n, "" if n == 1 else "s"] if n > 0
		else "The Sage finds nothing left to identify.")


func _add_npc(title: String, subtitle: String, pos: Vector2, gear: Dictionary, tint: Color, prompt: String, action: Callable) -> void:
	var npc := Interactable.new()
	npc.position = pos
	npc.prompt = prompt
	npc.action = action
	add_child(npc)

	var rig := RigSprite.new()
	rig.base_scale = 0.2
	rig.weapon_from_gear = true
	rig.modulate = tint
	npc.add_child(rig)
	for slot in gear:
		rig.set_gear(slot, gear[slot])
	rig.play_loop("Idle")
	rig.randomize_phase()
	rig.set_facing(-1.0 if pos.x > 0 else 1.0)  # face the plaza

	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 18.0
	cs.shape = c
	cs.position = Vector2(0, -6)
	body.add_child(cs)
	npc.add_child(body)

	var sh := Node2D.new()
	sh.draw.connect(func(): RigSprite.draw_shadow(sh, 24.0))
	npc.add_child(sh)
	npc.move_child(sh, 0)

	var name_l := Label.new()
	name_l.text = "%s\n%s" % [title, subtitle]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	name_l.add_theme_color_override("font_outline_color", Color.BLACK)
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.custom_minimum_size = Vector2(160, 0)
	name_l.position = Vector2(-80, -150)
	name_l.z_index = 5
	npc.add_child(name_l)


func _add_gate(pos: Vector2) -> void:
	var gate := Interactable.new()
	gate.position = pos
	gate.prompt = "Enter the Rift"
	gate.radius = 150.0
	gate.action = func(): rift_ui.open()
	gate.z_index = -1  # flat on the ground
	add_child(gate)
	_gate = gate
	gate.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		gate.draw_circle(Vector2(0, -40), 70, Color(0.25, 0.05, 0.35, 0.55))
		for i in 4:
			var r := 70.0 - i * 14.0 + sin(t * 2.0 + i) * 3.0
			gate.draw_arc(Vector2(0, -40), r, t * (1.0 + i * 0.3), t * (1.0 + i * 0.3) + TAU * 0.78, 40,
				Color(0.75, 0.4, 1.0, 0.85 - i * 0.15), 4.0)
		gate.draw_circle(Vector2(0, -40), 18, Color(0.9, 0.7, 1.0, 0.55 + 0.25 * sin(t * 3.0))))
	var l := Label.new()
	l.text = "Rift Gate"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.custom_minimum_size = Vector2(160, 0)
	l.position = Vector2(-80, -150)
	l.z_index = 5
	gate.add_child(l)
