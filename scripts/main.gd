extends Node2D
## Prototype arena: enemies spawn around you, drop loot, loot auto-equips.
## Move: left-thumb joystick (or arrow keys / WASD-mapped ui_* on desktop).
## Attack: automatic against the nearest enemy in range.

const MAX_ENEMIES := 14

var player: Player
var hud: Label
var drop_label: Label
var death_label: Label
var kills := 0
var inventory_ui: InventoryUI
var run: DungeonRun
var _spawn_timer := 0.0
var _bag_msg_cd := 0.0


func _ready() -> void:
	add_child(DesertMap.new())
	y_sort_enabled = true  # characters and loot overlap correctly: lower on screen draws in front
	player = Player.new()
	player.class_def = ClassLibrary.warrior()
	add_child(player)
	player.add_child(Camera2D.new())

	var layer := CanvasLayer.new()
	add_child(layer)

	var joy := VirtualJoystick.new()
	layer.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.joystick = joy

	# Right-thumb skill buttons, arranged in an arc from the bottom-right corner.
	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var button_pos := {1: Vector2(-260, -130), 2: Vector2(-190, -260), 3: Vector2(-120, -130)}
	for i in button_pos:
		var b := SkillButton.new()
		b.player = player
		b.index = i
		b.position = button_pos[i]
		pad.add_child(b)

	hud = Label.new()
	hud.position = Vector2(16, 12)
	layer.add_child(hud)

	drop_label = Label.new()
	drop_label.position = Vector2(16, 120)
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

	run = DungeonRun.new()
	run.player = player
	run.main = self
	add_child(run)

	inventory_ui = InventoryUI.new()
	inventory_ui.player = player
	add_child(inventory_ui)



func _process(delta: float) -> void:
	if not player.dead and run.spawning_allowed():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and get_tree().get_nodes_in_group("enemies").size() < MAX_ENEMIES:
			_spawn_enemy()
			_spawn_timer = 1.2

	_bag_msg_cd -= delta
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.delay > 0.0:
			continue
		if p.global_position.distance_to(player.global_position) < 48.0:
			if player.pick_up(p.item):
				p.queue_free()
			elif _bag_msg_cd <= 0.0:
				drop_label.text = "Bag full!"
				drop_label.modulate = Color(1.0, 0.4, 0.4)
				_bag_msg_cd = 2.0

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


func _spawn_enemy() -> void:
	var e := Enemy.new()
	e.position = player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(500.0, 700.0)
	e.target = player
	e.max_hp = 25.0 + kills * 1.5
	e.died.connect(_on_enemy_died)
	add_child(e)


func _on_enemy_died(pos: Vector2) -> void:
	kills += 1
	run.on_enemy_killed()
	if run.state == DungeonRun.State.FIGHTING:
		_drop_currency(pos)
	if run.state == DungeonRun.State.FIGHTING and randf() < 0.45:
		var pk := LootPickup.new()
		pk.item = LootGenerator.roll_item(1 + int(kills / 8.0))
		pk.position = pos
		add_child(pk)


func _drop_currency(pos: Vector2) -> void:
	var d := CraftingDB.monster_drops(1 + int(kills / 8.0))
	if d.gold > 0:
		spawn_currency("gold", "", d.gold, pos)
	for k in d.materials:
		spawn_currency("material", k, d.materials[k], pos)
	for k in d.orbs:
		spawn_currency("orb", k, d.orbs[k], pos)
	if randf() < 0.02:
		var r := GameState.random_unknown_recipe(["drop", "vendor"].pick_random())
		if r != "":
			spawn_currency("recipe", r, 1, pos)


func spawn_currency(kind: String, id: String, amount: int, pos: Vector2) -> void:
	var c := CurrencyPickup.new()
	c.kind = kind
	c.id = id
	c.amount = amount
	c.position = pos + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 55.0)
	add_child(c)


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
	hud.text = "%s   HP %d / %d\nDMG %.1f   Atk/s %.2f   Crit %d%%\nArmor %d   Move %d\nGear: %d slots filled   Bag: %d/%d   Gold %d" % [
		player.class_def.display_name, int(player.hp), int(s.get_stat("max_life")),
		s.get_stat("damage"), s.get_stat("attack_speed"), int(round(s.get_stat("crit_chance") * 100.0)),
		int(s.get_stat("armor")), int(s.get_stat("move_speed")),
		player.equipment.size(), player.inventory.size(), Player.BAG_SIZE, GameState.gold,
	]
