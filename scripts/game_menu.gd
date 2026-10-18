class_name GameMenu
extends CanvasLayer
## Diablo IV style menu: the CharacterPanel (equipment + bag) sits on the right half and the left
## half shows whatever was opened — item details, runes or gems from the inventory, or a vendor
## (stash, merchant, blacksmith, jeweler) opened by an NPC. Items drag between both halves.
## The skill tree is separate and full screen (SkillTreeUI).

## Panels the player can always switch to from the inventory.
const PLAYER_PANELS := ["details", "skills", "gems"]

var player: Player
var selected: ItemInstance = null  ## item picked in the character panel (bag or worn)

var _root: Control
var _open_btn: Button
var _left_frame: PanelContainer
var _left_body: VBoxContainer
var _left_title: Label
var _tabs_row: HBoxContainer
var _panel_host: VBoxContainer
var _feedback: Label
var _stats_popup: PanelContainer
var _stats_text: RichTextLabel
var _char: CharacterPanel

var _panels := {}  # name -> MenuPanel
var _current := "details"
var _vendor := ""  # vendor panel opened by an NPC; "" when opened as the inventory


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	player.inventory_changed.connect(refresh)
	GameState.changed.connect(refresh)
	GameState.skills_changed.connect(refresh)


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false


func _process(_delta: float) -> void:
	# Other full-screen windows (skill tree) pause the game too; keep the HUD button out of their way
	if _open_btn != null:
		_open_btn.visible = not get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_I:
		if is_open():
			close()
		elif not get_tree().paused:
			open()
	elif event.keycode == KEY_ESCAPE and is_open():
		if _stats_popup.visible:
			_stats_popup.visible = false
		else:
			close()


func is_open() -> bool:
	return _root.visible


## Open the inventory (available anywhere) with one of PLAYER_PANELS on the left.
func open(panel: String = "details") -> void:
	_open_with("details" if panel not in PLAYER_PANELS else panel, "")


## Open a vendor ("stash", "shop", "smith", "jeweler") on the left. Only call this from that
## NPC's Talk action in town: vendors are never reachable from the inventory itself.
func open_vendor(vendor: String) -> void:
	_open_with(vendor, vendor)


func _open_with(panel: String, vendor: String) -> void:
	if player.dead:
		return
	_vendor = vendor
	if vendor == "stash":
		(_get_panel("stash") as StashPanel).tab = "items"
	# Gems are socketed and swapped only at the stash or the Jeweler (the shared gems show there)
	GameState.gem_station = vendor in ["stash", "jeweler"]
	selected = null
	_stats_popup.visible = false
	_feedback.visible = false
	layer = 25
	_root.visible = true
	get_tree().paused = true
	show_panel(panel)


func close() -> void:
	GameState.gem_station = false
	_root.visible = false
	_stats_popup.visible = false
	layer = 10
	get_tree().paused = false


func show_panel(panel_name: String) -> void:
	_current = panel_name
	var p := _get_panel(panel_name)
	for n in _panels:
		_panels[n].visible = n == panel_name
	_left_title.text = p.panel_title()
	_build_tabs()
	refresh()


func current_panel() -> MenuPanel:
	return _panels.get(_current)


## True while an NPC's vendor panel (stash, merchant...) is open on the left.
func vendor_open() -> bool:
	return _vendor != ""


## The Skills panel (created if needed); the inventory's gem tabs build their cells with it.
func skills_panel() -> SkillGemsPanel:
	var p := _get_panel("skills") as SkillGemsPanel
	p.visible = _current == "skills"
	return p


func select(item: ItemInstance) -> void:
	selected = item
	# Picking an item from the inventory's other tabs jumps to its details, except where the
	# current panel works on the selected item itself (gems, vendors).
	if _vendor == "" and _current == "runes":
		show_panel("details")
	else:
		refresh()


func refresh() -> void:
	if _root == null or not _root.visible:
		return
	if selected != null and not player.inventory.has(selected) and not player.is_worn(selected) \
			and not GameState.stash.has(selected):
		selected = null
	_build_tabs()  # tab labels carry counts (runes, gems)
	_char.refresh()
	var p := current_panel()
	if p != null:
		p.refresh()
	if _stats_popup.visible:
		_refresh_stats()


func feedback(msg: String) -> void:
	if msg == "":
		return
	_feedback.text = msg
	_feedback.visible = true
	get_tree().create_timer(3.0, true, false, true).timeout.connect(func():
		if _feedback.text == msg:
			_feedback.visible = false
	)


func toggle_stats() -> void:
	_stats_popup.visible = not _stats_popup.visible
	if _stats_popup.visible:
		_refresh_stats()


# ---------- building ----------

func _get_panel(panel_name: String) -> MenuPanel:
	if _panels.has(panel_name):
		return _panels[panel_name]
	var p: MenuPanel
	match panel_name:
		"skills": p = SkillGemsPanel.new()
		"gems": p = GemsPanel.new()
		"jeweler":
			var gp := GemsPanel.new()
			gp.jeweler = true
			p = gp
		"stash": p = StashPanel.new()
		"shop": p = ShopPanel.new()
		"smith": p = SmithPanel.new()
		_: p = DetailsPanel.new()
	p.menu = self
	p.player = player
	_panels[panel_name] = p
	_panel_host.add_child(p)
	return p


## One row of tabs: the vendor's panel then PLAYER_PANELS. At the stash it is Items, Skills,
## Currency, Gems instead (Items and Currency are the two tabs of the StashPanel).
func _build_tabs() -> void:
	UIKit.clear(_tabs_row)
	var tabs: Array = []  # [panel name, stash tab or ""]
	if _vendor == "stash":
		tabs = [["stash", "items"], ["skills", ""], ["stash", "currency"], ["gems", ""]]
	else:
		if _vendor != "":
			tabs.append([_vendor, ""])
		for n in PLAYER_PANELS:
			tabs.append([n, ""])
	var stash := _panels.get("stash") as StashPanel
	for t in tabs:
		var n: String = t[0]
		var stash_tab: String = t[1]
		var p := _get_panel(n)
		p.visible = n == _current
		var active: bool = n == _current and (stash_tab == "" or stash.tab == stash_tab)
		var b := Button.new()
		b.text = p.panel_title()
		if stash_tab != "":
			b.text = "📦 Items" if stash_tab == "items" else "💰 Currency"
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", UIKit.box(
			Color(0.24, 0.18, 0.10) if active else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.82, 0.40) if active else Color(0.35, 0.28, 0.20), 2 if active else 1, 6))
		b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.70) if active else Color(0.70, 0.65, 0.60))
		b.pressed.connect(func():
			if stash_tab != "":
				(_get_panel("stash") as StashPanel).tab = stash_tab
			show_panel(n)
		)
		_tabs_row.add_child(b)


func _build() -> void:
	_open_btn = UIKit.stone_button("🎒 BAG", Vector2(110, 56), 20)
	_open_btn.pressed.connect(open)
	add_child(_open_btn)
	_open_btn.anchor_left = 1.0
	_open_btn.anchor_right = 1.0
	_open_btn.offset_left = -126.0
	_open_btn.offset_right = -16.0
	_open_btn.offset_top = 16.0
	_open_btn.offset_bottom = 72.0

	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.80)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	_root.add_child(cols)
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)

	# LEFT: context panel (with the stats popup layered on top of it)
	_left_frame = PanelContainer.new()
	_left_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_frame.size_flags_stretch_ratio = 1.0
	_left_frame.clip_contents = true
	var lsb := UIKit.box(Color(0.07, 0.06, 0.09, 0.97), Color(0.42, 0.33, 0.20), 2, 10)
	lsb.set_content_margin_all(10)
	_left_frame.add_theme_stylebox_override("panel", lsb)
	cols.add_child(_left_frame)

	_left_body = VBoxContainer.new()
	_left_body.add_theme_constant_override("separation", 8)
	_left_frame.add_child(_left_body)
	_left_title = UIKit.label("", 22, UIKit.GOLD)
	_left_title.visible = false  # the active tab already names the panel
	_left_body.add_child(_left_title)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 6)
	_left_body.add_child(_tabs_row)
	_feedback = UIKit.label("", 15, Color(1.0, 0.85, 0.40), true)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.visible = false
	_left_body.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_body.add_child(scroll)
	_panel_host = VBoxContainer.new()
	_panel_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel_host)

	_stats_popup = PanelContainer.new()
	_stats_popup.visible = false
	var psb := UIKit.box(Color(0.06, 0.05, 0.08, 0.99), Color(0.55, 0.42, 0.25), 2, 8)
	psb.set_content_margin_all(12)
	_stats_popup.add_theme_stylebox_override("panel", psb)
	_left_frame.add_child(_stats_popup)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	_stats_popup.add_child(pv)
	var ph := HBoxContainer.new()
	pv.add_child(ph)
	var pt := UIKit.label("CHARACTER STATS", 20, UIKit.GOLD)
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pt)
	var pclose := UIKit.button("✕ Close", Color(0.20, 0.10, 0.10), Color(0.70, 0.30, 0.30), Vector2(120, 48), 18)
	pclose.pressed.connect(func(): _stats_popup.visible = false)
	ph.add_child(pclose)
	var pscroll := ScrollContainer.new()
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(pscroll)
	_stats_text = UIKit.rich("", 17)
	_stats_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pscroll.add_child(_stats_text)

	# RIGHT: character, equipment and bag
	_char = CharacterPanel.new()
	_char.menu = self
	_char.player = player
	_char.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_char)


func _refresh_stats() -> void:
	var s := player.stats
	var cd := player.class_def
	var rows := [
		["OFFENSIVE", ""],
		["Damage", "%.1f" % s.get_stat("damage")],
		["Attack Speed", "%.2f / s" % s.get_stat("attack_speed")],
		["Critical Strike Chance", "%.1f%%" % (s.get_stat("crit_chance") * 100.0)],
		["Critical Strike Damage", "100%"],
		["DEFENSIVE", ""],
		["Maximum Life", "%d" % int(s.get_stat("max_life"))],
		["Life Regeneration", "%.1f / s" % s.get_stat("life_regen")],
		["Armor", "%d" % int(s.get_stat("armor"))],
		["Damage Reduction from Armor", "%.1f%%" % (100.0 - 10000.0 / (100.0 + s.get_stat("armor")))],
		["UTILITY", ""],
		["Movement Speed", "%d" % int(s.get_stat("move_speed"))],
		["Maximum %s" % cd.power_name, "%d" % int(player.max_resource())],
		["%s Decay" % cd.power_name, "%.1f / s" % cd.power_decay],
		["%s When Hit" % cd.power_name, "+%d, +%d per 10%% life lost" % [int(cd.power_on_hit), int(cd.power_per_life_lost * 0.1)]],
		["PROGRESS", ""],
		["Level", "%d" % GameState.level],
		["Experience", "%d / %d" % [int(GameState.xp), int(GameState.xp_to_next(GameState.level))]],
		["Unspent Passive Points", "%d" % GameState.skill_points],
		["Support Links per Skill", "%d / %d" % [GameState.links_unlocked(), GameState.MAX_LINKS]],
	]
	var t := "[table=2]"
	for r in rows:
		if r[1] == "":
			t += "[cell][color=#c9a55c][b]\n%s[/b][/color][/cell][cell] [/cell]" % r[0]
		else:
			t += "[cell][color=#bdb6aa]%s[/color]   [/cell][cell][right][color=#f3e6c4]%s[/color][/right][/cell]" % [r[0], r[1]]
	t += "[/table]"
	_stats_text.text = t
