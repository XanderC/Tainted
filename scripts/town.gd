extends Node2D
## The hub scene and the game's start scene. Walk up to an NPC and tap Talk.
## Blacksmith: orbs, salvage, recipes.  Merchant: buy and sell.  Stash keeper: shared storage.
## Dungeon Gate: starts a dungeon instance (scenes/main.tscn).

const DUNGEON_SCENE := "res://scenes/main.tscn"
const SPAWN := Vector2(0, 360)

var player: Player
var inventory_ui: InventoryUI
var crafting_ui: CraftingUI
var stash_ui: StashUI
var _hud: Label
var _talk_btn: Button
var _near: Interactable = null
var _gate: Node2D


func _ready() -> void:
	y_sort_enabled = true
	add_child(TownMap.new())

	player = Player.new()
	player.class_def = ClassLibrary.warrior()
	player.can_fight = false
	player.position = SPAWN
	add_child(player)
	var cam := Camera2D.new()
	cam.limit_left = int(TownMap.CAM_LIMIT.position.x)
	cam.limit_right = int(TownMap.CAM_LIMIT.end.x)
	cam.limit_top = int(TownMap.CAM_LIMIT.position.y)
	cam.limit_bottom = int(TownMap.CAM_LIMIT.end.y)
	player.add_child(cam)

	_add_npc("Blacksmith", "Craft & Salvage", Vector2(-560, -205), {"weapon": "battle_axe", "chest": "chain_mail", "helmet": "leather_cap"},
		Color(1.0, 0.88, 0.78), "Talk to the Blacksmith", func(): crafting_ui.open("smith"))
	_add_npc("Merchant", "Buy & Sell", Vector2(580, -185), {"chest": "padded_vest", "helmet": "leather_cap"},
		Color(0.82, 0.92, 1.0), "Talk to the Merchant", func(): crafting_ui.open("merchant"))
	_add_npc("Stash Keeper", "Shared Storage", Vector2(0, -270), {"helmet": "iron_helm", "weapon": "rusty_sword"},
		Color(0.92, 0.85, 1.0), "Open the Stash", func(): stash_ui.open())
	_add_gate(Vector2(820, 220))

	var layer := CanvasLayer.new()
	add_child(layer)
	var joy := VirtualJoystick.new()
	layer.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.joystick = joy

	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)

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

	inventory_ui = InventoryUI.new()
	inventory_ui.player = player
	add_child(inventory_ui)
	crafting_ui = CraftingUI.new()
	crafting_ui.player = player
	add_child(crafting_ui)
	stash_ui = StashUI.new()
	stash_ui.player = player
	add_child(stash_ui)


func _process(delta: float) -> void:
	_hud.text = "Ashfall Outpost\nGold %d     Bag %d/%d" % [GameState.gold, player.inventory.size(), Player.BAG_SIZE]
	if _gate:
		_gate.queue_redraw()
	var best: Interactable = null
	var best_d := INF
	for i in get_tree().get_nodes_in_group("interactables"):
		var d: float = i.global_position.distance_to(player.global_position)
		if d < i.radius and d < best_d:
			best = i
			best_d = d
	var any_open := inventory_ui.is_open() or crafting_ui.is_open() or stash_ui.is_open()
	_near = best
	_talk_btn.visible = best != null and not any_open
	if best != null:
		_talk_btn.text = best.prompt


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and _near != null:
		_interact()


func _interact() -> void:
	if _near != null and _near.action.is_valid():
		_near.action.call()


func enter_dungeon() -> void:
	GameState.save()
	get_tree().change_scene_to_file(DUNGEON_SCENE)


# ---------- building the town's people ----------

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
	gate.prompt = "Enter the Dungeon"
	gate.radius = 150.0
	gate.action = enter_dungeon
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
	l.text = "Dungeon Gate"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.custom_minimum_size = Vector2(160, 0)
	l.position = Vector2(-80, -150)
	l.z_index = 5
	gate.add_child(l)
