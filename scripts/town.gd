extends Node2D
## The hub scene, entered from the character select screen. Walk up to an NPC and tap Talk.
## Blacksmith: recipes and plans (paid in orbs).  Merchant: buy and sell.  Stash keeper: shared storage and currency.
## Jeweler: combine gems into higher tiers and remove socketed gems.
## Sage: identifies every item in your bag and stash, free.
## Rift Gate: pick a rift level, then start a run (scenes/main.tscn).
## The story: NPCs with quest business talk first (DialogueUI), the west road leads to the Dune
## Wastes (Zone), a waypoint travels to zones you've found, and a town portal opened out there
## brings you back to where you were.

const DUNGEON_SCENE := "res://scenes/main.tscn"
const SPAWN := Vector2(0, 360)
const WEST_EXIT := Vector2(-940, 620)  # the road out to the Dune Wastes
const WEST_EXIT_ZONE := "dune_wastes"
const WAYPOINT := Vector2(260, 300)
const PORTAL := Vector2(-80, 470)  # where an open town portal stands
const DYER := Vector2(-410, 40)  # the Dyer, between the Blacksmith's and the Sage's
const CAPTAIN := Vector2(560, 120)  # the Mercenary Captain, by the road east to the Rift Gate
const EXIT_REACH := 70.0

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
var dialogue: DialogueUI
var quest_log: QuestLogUI
var waypoint_ui: WaypointUI
var hire_ui: HireUI
var dye_ui: DyeUI
var _exits: Array = []  # [{"node", "target", "entry"}]
var _leaving := false


func _ready() -> void:
	y_sort_enabled = true
	add_child(TownMap.new())
	add_child(NetPresence.new())  # online: everyone else in town (Net.TOWN)

	player = Player.new()
	player.class_def = ClassLibrary.get_class_def(GameState.char_class)
	player.can_fight = false
	player.position = _arrival()
	add_child(player)
	player.item_dropped.connect(_on_item_dropped)
	var cam := Camera2D.new()
	cam.limit_left = int(TownMap.CAM_LIMIT.position.x)
	cam.limit_right = int(TownMap.CAM_LIMIT.end.x)
	cam.limit_top = int(TownMap.CAM_LIMIT.position.y)
	cam.limit_bottom = int(TownMap.CAM_LIMIT.end.y)
	player.add_child(cam)

	_add_npc("Blacksmith", "Craft", Vector2(-560, -205), "blacksmith", "Talk to the Blacksmith", func(): menu.open_vendor("smith"))
	_add_npc("Merchant", "Buy & Sell", Vector2(580, -185), "merchant", "Talk to the Merchant", func(): menu.open_vendor("shop"))
	_add_npc("Stash Keeper", "Shared Storage", Vector2(0, -270), "stash_keeper", "Open the Stash", func(): menu.open_vendor("stash"))
	_add_npc("Battlemaster Brom", "Passive Tree", Vector2(-240, -160), "battlemaster", "Open the Passive Tree", func(): skill_tree_ui.open())
	_add_npc("Jeweler", "Gems", Vector2(280, -175), "jeweler", "Talk to the Jeweler", func(): menu.open_vendor("jeweler"))
	_add_npc("Sage Aldous", "Identify", Vector2(-600, 150), "sage", "Talk to the Sage", _identify_all)
	_add_npc("Caravan Master Hesk", "Caravans", Vector2(-330, 250), "caravan_master", "Talk to Hesk",
		func(): dialogue.open("hesk"), "hesk")
	_add_npc("Captain Rourke", "Hirelings", CAPTAIN, "", "Talk to the Captain", func(): hire_ui.open(), "captain",
		{"weapon": "war_sword", "helmet": "iron_helm", "chest": "chain_mail", "offhand": "kite_shield"})
	var dyer_look := Appearance.default_look("female")
	dyer_look["hair_color"] = "ginger"
	_add_npc("Dyer Calla", "Dye Armour", DYER, "", "Talk to the Dyer", func(): dye_ui.open(), "dyer",
		{"helmet": ["leather_cap", "teal"], "chest": ["padded_vest", "rose"]}, dyer_look)
	_add_gate(Vector2(820, 220))
	_add_exit(WEST_EXIT, WEST_EXIT_ZONE, "town", "→ " + ActDB.zone_name(WEST_EXIT_ZONE))
	if GameState.town_portal.get("zone", "") != "":
		_add_exit(PORTAL, String(GameState.town_portal["zone"]), "portal",
			"🌀 Portal to " + ActDB.zone_name(String(GameState.town_portal["zone"])))
	_add_waypoint(WAYPOINT)

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

	var info := VBoxContainer.new()
	info.position = Vector2(16, 12)
	info.add_theme_constant_override("separation", 6)
	layer.add_child(info)
	var portrait := HirelingPortrait.new()  # your hireling, top left: tap for its equipment
	portrait.on_open = func(): menu.open("hireling")
	info.add_child(portrait)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	info.add_child(_hud)
	var tracker := QuestTracker.new()
	tracker.open_log.connect(func(): quest_log.open())
	info.add_child(tracker)

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

	_talk_btn = UIKit.stone_button("", Vector2(0, 0), 22)
	_talk_btn.visible = false
	_talk_btn.pressed.connect(_interact)
	layer.add_child(_talk_btn)
	_talk_btn.anchor_left = 0.5
	_talk_btn.anchor_right = 0.5
	_talk_btn.anchor_top = 1.0
	_talk_btn.anchor_bottom = 1.0
	_talk_btn.offset_left = -170  # above the XP bar and flask row
	_talk_btn.offset_right = 170
	_talk_btn.offset_top = -216
	_talk_btn.offset_bottom = -160

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
	dialogue = DialogueUI.new()
	dialogue.player = player
	add_child(dialogue)
	quest_log = QuestLogUI.new()
	add_child(quest_log)
	waypoint_ui = WaypointUI.new()
	waypoint_ui.here = ActDB.TOWN
	add_child(waypoint_ui)
	hire_ui = HireUI.new()
	hire_ui.player = player
	add_child(hire_ui)
	dye_ui = DyeUI.new()
	dye_ui.player = player
	add_child(dye_ui)
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
	panel.add_theme_stylebox_override("panel", UIKit.window_box(22, Color.WHITE, true))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	UIKit.window_header(v, "WELCOME TO ASHFALL OUTPOST", UIKit.GOLD, layer.queue_free, 22)
	var t := UIKit.rich(
		"This is your home base. Walk up to someone and tap [b]Talk[/b]:\n" +
		"  • [color=#ffd54a]Merchant[/color] - buy skill gems, flasks and orbs, and sell loot for orbs\n" +
		"  • [color=#ffd54a]Blacksmith[/color] - forge recipes and plans\n" +
		"  • [color=#ffd54a]Stash Keeper[/color] - storage shared by all your characters\n" +
		"  • [color=#ffd54a]Jeweler[/color] - combine and remove item gems\n" +
		"  • [color=#ffd54a]Battlemaster Brom[/color] - your passive tree (you get a point every level)\n" +
		"  • [color=#ffd54a]Captain Rourke[/color] - hire a fighter to follow you and fight at your side\n" +
		"  • [color=#ffd54a]Dyer Calla[/color] - dye your helmet and armour any colour\n" +
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
	if not _leaving and not get_tree().paused:
		for e in _exits:
			if player.global_position.distance_to(e["node"].global_position) < EXIT_REACH:
				_leaving = true
				if e["entry"] == "portal":
					GameState.town_portal = {}  # a portal closes once you go back through it
				ActDB.travel(get_tree(), e["target"], e["entry"])
				return

	var best: Interactable = null
	var best_d := INF
	for i in get_tree().get_nodes_in_group("interactables"):
		var d: float = i.global_position.distance_to(player.global_position)
		if d < i.radius and d < best_d:
			best = i
			best_d = d
	var any_open: bool = (menu != null and menu.is_open()) or \
		(rift_ui != null and rift_ui.is_open()) or \
		(dialogue != null and dialogue.is_open()) or \
		(quest_log != null and quest_log.is_open()) or \
		(waypoint_ui != null and waypoint_ui.is_open()) or \
		(hire_ui != null and hire_ui.is_open()) or 		(dye_ui != null and dye_ui.is_open()) or \
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


## An NPC drawn as `skin`, a character from the packs (assets/skins), or with no skin a figure
## (with `look`, default a plain man) wearing `gear` (slot -> base id, or [base id, dye id]). `npc_id` (QuestDB, default: the skin) is who they are in the
## story: with quest business they talk first, their own action (the vendor, say) one of the
## choices; a gold ! or ? over their head says so.
func _add_npc(title: String, subtitle: String, pos: Vector2, skin: String, prompt: String, action: Callable,
		npc_id := "", gear := {}, look := {}) -> void:
	if npc_id == "":
		npc_id = skin
	var npc := Interactable.new()
	npc.position = pos
	npc.prompt = prompt
	npc.action = func():
		if Quests.npc_options(npc_id).is_empty() or npc_id == "hesk":
			action.call()
		else:
			dialogue.open(npc_id, [{"label": prompt, "action": action}])
	add_child(npc)
	var mk := QuestMarker.new()
	mk.npc_id = npc_id
	mk.position = Vector2(0, -150)
	npc.add_child(mk)

	var rig := RigSprite.new()
	rig.base_scale = 0.2
	rig.skin = skin
	if skin == "":
		rig.weapon_from_gear = true
	npc.add_child(rig)
	if skin == "":
		Appearance.apply(rig, look if not look.is_empty() else Appearance.default_look())
		for slot in gear:
			# a base id, or [base id, dye id]
			var g = gear[slot]
			var gid := String(g[0]) if g is Array else String(g)
			if slot == "offhand":
				rig.set_offhand(gid, gid.ends_with("shield"))
			else:
				rig.set_gear(slot, gid, String(g[1]) if g is Array else "")
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


## Where you appear: at the waypoint, the town portal, the road back from a zone, or the usual spot.
func _arrival() -> Vector2:
	match GameState.zone_entry:
		"waypoint": return WAYPOINT + Vector2(0, 90)
		"portal": return PORTAL + Vector2(0, -110)
		WEST_EXIT_ZONE: return WEST_EXIT + Vector2(150, 0)
	return SPAWN


## A way out of town: walk into it (target zone, and where to arrive there).
func _add_exit(pos: Vector2, target: String, entry: String, text: String) -> void:
	var p := RiftPortal.new()
	p.position = pos
	add_child(p)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.size = Vector2(300, 24)
	l.position = Vector2(-150, -110)
	p.add_child(l)
	_exits.append({"node": p, "target": target, "entry": entry})


## The town's waypoint stone: travel to any zone whose waypoint you've touched.
func _add_waypoint(pos: Vector2) -> void:
	var w := Interactable.new()
	w.position = pos
	w.prompt = "Waypoint"
	w.radius = 140.0
	w.action = func(): waypoint_ui.open()
	w.z_index = -1
	add_child(w)
	w.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		w.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		w.draw_circle(Vector2.ZERO, 70, Color(0.15, 0.18, 0.22, 0.85))
		w.draw_arc(Vector2.ZERO, 70, 0, TAU, 48, Color(0.55, 0.85, 1.0, 0.9), 5.0)
		w.draw_set_transform(Vector2.ZERO)
		var glow := Color(0.5, 0.85, 1.0, 0.45 + 0.25 * sin(t * 2.5))
		w.draw_rect(Rect2(-14, -95, 28, 95), Color(0.22, 0.20, 0.24))
		w.draw_rect(Rect2(-14, -95, 28, 95), glow, false, 3.0)
		w.draw_circle(Vector2(0, -105), 14, glow)
	)
	var redraw := Timer.new()
	redraw.wait_time = 0.05
	redraw.autostart = true
	redraw.timeout.connect(w.queue_redraw)
	w.add_child(redraw)


## Dropped from the bag (the Drop box) or a quest reward with no room: it lands at your feet.
func _on_item_dropped(item: ItemInstance) -> void:
	var pk := LootPickup.new()
	pk.item = item
	pk.delay = 1.5
	pk.position = player.global_position + player.facing * 90.0
	add_child(pk)


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
