class_name InventoryUI
extends CanvasLayer
## Diablo & Path of Exile style inventory & character screen.
## Features:
## - Anatomical paperdoll equipment grid (Helm, Armor, Weapon, Gloves, Boots, Ring, Amulet)
## - 6x4 slotted bag grid with item icons and rarity glow borders
## - PoE style item tooltip with header banners, implicit/explicit stats, and stat comparison deltas
## - Character combat attributes card (Life, Damage, Armor, Attack Speed, Crit Chance, Move Speed)
## - Mobile touch-optimized large buttons

const STAT_LABELS := {
	"max_life": "Max Life",
	"damage": "Damage",
	"attack_speed": "Attack Speed",
	"armor": "Armor",
	"crit_chance": "Critical Strike",
	"move_speed": "Movement Speed",
}

const SLOT_NAMES := {
	"helmet": "Helmet",
	"chest": "Body Armor",
	"weapon": "Main Hand",
	"gloves": "Gloves",
	"boots": "Boots",
	"ring": "Finger Ring",
	"amulet": "Amulet",
}

const SLOT_ICONS := {
	"helmet": "⛑",
	"chest": "🛡",
	"weapon": "⚔",
	"gloves": "🧤",
	"boots": "👢",
	"ring": "💍",
	"amulet": "📿",
}

var player: Player

var _root: Control
var _open_btn: Button
var _gold_label: Label
var _bag_count_label: Label

# Paperdoll & slots
var _slot_buttons := {}

# Bag grid
var _bag_buttons: Array[Button] = []

# Stats sheet
var _stats_labels := {}

# Right column details
var _detail_panel: PanelContainer
var _detail_content: VBoxContainer
var _btn_primary: Button
var _btn_drop: Button

var _selected: ItemInstance = null
var _selected_slot := ""  # "" = from bag, otherwise slot name


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	player.inventory_changed.connect(_refresh)
	GameState.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			if _root.visible:
				close()
			else:
				open()
		elif event.keycode == KEY_ESCAPE and _root.visible:
			close()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if player.dead:
		return
	_selected = null
	_selected_slot = ""
	_root.visible = true
	_open_btn.visible = false
	get_tree().paused = true
	_refresh()


func close() -> void:
	_root.visible = false
	_open_btn.visible = true
	get_tree().paused = false


# ==============================================================================
# UI CONSTRUCTION
# ==============================================================================

func _build_ui() -> void:
	# Persistent toggle button on HUD
	_open_btn = Button.new()
	_open_btn.text = "🎒 BAG"
	_open_btn.custom_minimum_size = Vector2(110, 56)
	_open_btn.add_theme_font_size_override("font_size", 20)
	var ob_sb := _make_stylebox(Color(0.12, 0.10, 0.15, 0.9), Color(0.65, 0.52, 0.30), 2, 6)
	_open_btn.add_theme_stylebox_override("normal", ob_sb)
	_open_btn.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
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

	# Full-screen dark gothic vignette backdrop
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.86)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Main Window Container
	var window_panel := PanelContainer.new()
	_root.add_child(window_panel)
	window_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	var win_bg := _make_stylebox(Color(0.08, 0.07, 0.10, 0.98), Color(0.48, 0.38, 0.22), 3, 10)
	win_bg.set_content_margin_all(12)
	window_panel.add_theme_stylebox_override("panel", win_bg)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	window_panel.add_child(outer)

	# TOP HEADER BANNER
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	outer.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "⚔  INVENTORY & CHARACTER"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	header.add_child(title_lbl)

	var hero_class := Label.new()
	hero_class.text = "|   %s" % (player.class_def.display_name if player.class_def else "Hero")
	hero_class.add_theme_font_size_override("font_size", 18)
	hero_class.add_theme_color_override("font_color", Color(0.70, 0.65, 0.60))
	hero_class.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hero_class)

	# Gold balance badge
	var gold_box := PanelContainer.new()
	var gold_sb := _make_stylebox(Color(0.14, 0.12, 0.08, 0.9), Color(0.85, 0.70, 0.25), 1, 6)
	gold_sb.content_margin_left = 12
	gold_sb.content_margin_right = 12
	gold_sb.content_margin_top = 4
	gold_sb.content_margin_bottom = 4
	gold_box.add_theme_stylebox_override("panel", gold_sb)
	header.add_child(gold_box)

	_gold_label = Label.new()
	_gold_label.text = "🪙 0 Gold"
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	gold_box.add_child(_gold_label)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.custom_minimum_size = Vector2(100, 42)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.18, 0.12, 0.14), Color(0.60, 0.30, 0.30), 2, 6))
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# THREE COLUMN LAYOUT
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)

	# --------------------------------------------------------------------------
	# COLUMN 1: EQUIPMENT PAPERDOLL & COMBAT ATTRIBUTES
	# --------------------------------------------------------------------------
	var col_left := VBoxContainer.new()
	col_left.custom_minimum_size = Vector2(340, 0)
	col_left.add_theme_constant_override("separation", 10)
	columns.add_child(col_left)

	# Paperdoll Card
	var paperdoll_panel := PanelContainer.new()
	var pd_sb := _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8)
	pd_sb.set_content_margin_all(10)
	paperdoll_panel.add_theme_stylebox_override("panel", pd_sb)
	col_left.add_child(paperdoll_panel)

	var pd_box := VBoxContainer.new()
	pd_box.add_theme_constant_override("separation", 8)
	paperdoll_panel.add_child(pd_box)

	var pd_title := Label.new()
	pd_title.text = "EQUIPMENT SLOTS"
	pd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pd_title.add_theme_font_size_override("font_size", 16)
	pd_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	pd_box.add_child(pd_title)

	# Grid arranged like character anatomy
	var pd_grid := GridContainer.new()
	pd_grid.columns = 3
	pd_grid.add_theme_constant_override("h_separation", 10)
	pd_grid.add_theme_constant_override("v_separation", 8)
	pd_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pd_box.add_child(pd_grid)

	# Row 0: Amulet | Helmet | Ring
	_slot_buttons["amulet"] = _create_slot_button("amulet", pd_grid)
	_slot_buttons["helmet"] = _create_slot_button("helmet", pd_grid)
	_slot_buttons["ring"] = _create_slot_button("ring", pd_grid)

	# Row 1: Weapon | Chest | (Spacer)
	_slot_buttons["weapon"] = _create_slot_button("weapon", pd_grid)
	_slot_buttons["chest"] = _create_slot_button("chest", pd_grid)
	pd_grid.add_child(_create_spacer_slot())

	# Row 2: Gloves | Boots | (Spacer)
	_slot_buttons["gloves"] = _create_slot_button("gloves", pd_grid)
	_slot_buttons["boots"] = _create_slot_button("boots", pd_grid)
	pd_grid.add_child(_create_spacer_slot())

	# Attributes Sheet Card (PoE Style)
	var stats_panel := PanelContainer.new()
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats_sb := _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8)
	stats_sb.set_content_margin_all(10)
	stats_panel.add_theme_stylebox_override("panel", stats_sb)
	col_left.add_child(stats_panel)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 6)
	stats_panel.add_child(stats_box)

	var stats_title := Label.new()
	stats_title.text = "CHARACTER ATTRIBUTES"
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_title.add_theme_font_size_override("font_size", 16)
	stats_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	stats_box.add_child(stats_title)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 14)
	stats_grid.add_theme_constant_override("v_separation", 4)
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.add_child(stats_grid)

	for k in STAT_LABELS:
		var name_lbl := Label.new()
		name_lbl.text = STAT_LABELS[k]
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
		stats_grid.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 16)
		val_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
		stats_grid.add_child(val_lbl)
		_stats_labels[k] = val_lbl

	# --------------------------------------------------------------------------
	# COLUMN 2: INVENTORY BAG GRID (Diablo / PoE Slotted Grid)
	# --------------------------------------------------------------------------
	var col_mid := VBoxContainer.new()
	col_mid.custom_minimum_size = Vector2(440, 0)
	col_mid.add_theme_constant_override("separation", 8)
	columns.add_child(col_mid)

	var bag_panel := PanelContainer.new()
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bag_sb := _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8)
	bag_sb.set_content_margin_all(10)
	bag_panel.add_theme_stylebox_override("panel", bag_sb)
	col_mid.add_child(bag_panel)

	var bag_vbox := VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 10)
	bag_panel.add_child(bag_vbox)

	var bag_hdr := HBoxContainer.new()
	bag_vbox.add_child(bag_hdr)

	var bag_title := Label.new()
	bag_title.text = "INVENTORY SLOTS"
	bag_title.add_theme_font_size_override("font_size", 17)
	bag_title.add_theme_color_override("font_color", Color(0.90, 0.80, 0.55))
	bag_hdr.add_child(bag_title)

	_bag_count_label = Label.new()
	_bag_count_label.text = "0 / 24"
	_bag_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bag_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_count_label.add_theme_font_size_override("font_size", 16)
	_bag_count_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.75))
	bag_hdr.add_child(_bag_count_label)

	# 6 Columns x 4 Rows Inventory Grid
	var bag_grid := GridContainer.new()
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 6)
	bag_grid.add_theme_constant_override("v_separation", 6)
	bag_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bag_vbox.add_child(bag_grid)

	for i in Player.BAG_SIZE:
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(66, 66)
		slot_btn.clip_text = true
		slot_btn.expand_icon = true
		slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_btn.add_theme_font_size_override("font_size", 11)
		slot_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot_btn.pressed.connect(_on_bag_pressed.bind(i))
		bag_grid.add_child(slot_btn)
		_bag_buttons.append(slot_btn)

	var hint_lbl := Label.new()
	hint_lbl.text = "💡 Tap any item to inspect, equip, or drop."
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 13)
	hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.50, 0.45))
	bag_vbox.add_child(hint_lbl)

	# --------------------------------------------------------------------------
	# COLUMN 3: DIABLO / POE TOOLTIP & ITEM COMPARISON
	# --------------------------------------------------------------------------
	var col_right := VBoxContainer.new()
	col_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_right.add_theme_constant_override("separation", 10)
	columns.add_child(col_right)

	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var det_sb := _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.38, 0.30, 0.20), 2, 8)
	det_sb.set_content_margin_all(12)
	_detail_panel.add_theme_stylebox_override("panel", det_sb)
	col_right.add_child(_detail_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(scroll)

	_detail_content = VBoxContainer.new()
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_detail_content)

	# Action Buttons Bar
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 12)
	col_right.add_child(act_row)

	_btn_primary = Button.new()
	_btn_primary.text = "⚔ Equip"
	_btn_primary.custom_minimum_size = Vector2(160, 52)
	_btn_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_primary.add_theme_font_size_override("font_size", 20)
	_btn_primary.add_theme_stylebox_override("normal", _make_stylebox(Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), 2, 6))
	_btn_primary.pressed.connect(_on_primary)
	act_row.add_child(_btn_primary)

	_btn_drop = Button.new()
	_btn_drop.text = "🗑 Drop"
	_btn_drop.custom_minimum_size = Vector2(110, 52)
	_btn_drop.add_theme_font_size_override("font_size", 18)
	_btn_drop.add_theme_stylebox_override("normal", _make_stylebox(Color(0.20, 0.08, 0.08), Color(0.70, 0.25, 0.25), 2, 6))
	_btn_drop.pressed.connect(_on_drop)
	act_row.add_child(_btn_drop)


func _create_slot_button(slot: String, parent: Node) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(72, 72)
	b.clip_text = true
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(_on_equip_slot_pressed.bind(slot))
	parent.add_child(b)
	return b


func _create_spacer_slot() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(72, 72)
	return c


func _make_stylebox(bg: Color, border: Color, width := 2, corner := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	return sb


# ==============================================================================
# REFRESH & DATA BINDING
# ==============================================================================

func _refresh() -> void:
	if _root == null:
		return

	# Gold & Stash
	_gold_label.text = "🪙 %d Gold" % GameState.gold
	_bag_count_label.text = "%d / %d" % [player.inventory.size(), Player.BAG_SIZE]

	# Combat Stats
	for k in STAT_LABELS:
		var v = player.stats.get_stat(k)
		var txt := ""
		match k:
			"crit_chance":
				txt = "%d%%" % int(round(v * 100.0))
			"attack_speed":
				txt = "%.2f /s" % v
			"move_speed":
				txt = "%d%%" % int(round(v * 100.0))
			_:
				txt = "%d" % int(round(v))
		if _stats_labels.has(k):
			_stats_labels[k].text = txt

	# Paperdoll equipment slots
	for slot in Player.SLOTS:
		if not _slot_buttons.has(slot):
			continue
		var b: Button = _slot_buttons[slot]
		var item: ItemInstance = player.equipment.get(slot)
		var is_sel: bool = item != null and item == _selected and _selected_slot == slot
		_style_equipment_button(b, slot, item, is_sel)

	# Inventory Bag Grid (24 slots)
	for i in Player.BAG_SIZE:
		var b: Button = _bag_buttons[i]
		var item: ItemInstance = player.inventory[i] if i < player.inventory.size() else null
		var is_sel: bool = item != null and item == _selected and _selected_slot == ""
		_style_bag_button(b, item, is_sel)

	# Details Tooltip
	_refresh_detail()


func _style_equipment_button(b: Button, slot: String, item: ItemInstance, selected: bool) -> void:
	b.icon = null
	b.text = ""
	var bg: Color
	var border: Color

	if item == null:
		# Empty equipment socket
		bg = Color(0.10, 0.09, 0.13)
		border = Color(0.24, 0.22, 0.28)
		b.text = "%s\n%s" % [SLOT_ICONS.get(slot, "▪"), SLOT_NAMES.get(slot, slot).to_upper()]
		b.add_theme_color_override("font_color", Color(0.45, 0.42, 0.48))
	else:
		# Equipped item
		var rar_col: Color = ItemInstance.RARITY_COLORS[item.rarity]
		border = rar_col
		bg = item.base.color.darkened(0.70)
		if item.base.icon != null:
			b.icon = item.base.icon
		else:
			b.text = item.display_name
			b.add_theme_color_override("font_color", rar_col)

	if selected:
		border = Color.WHITE

	var sb := _make_stylebox(bg, border, 3 if selected else (2 if item != null else 1), 6)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, sb)


func _style_bag_button(b: Button, item: ItemInstance, selected: bool) -> void:
	b.icon = null
	b.text = ""
	var bg: Color
	var border: Color

	if item == null:
		# Empty inventory slot
		bg = Color(0.09, 0.08, 0.12)
		border = Color(0.20, 0.18, 0.24)
	else:
		# Item present in slot
		var rar_col: Color = ItemInstance.RARITY_COLORS[item.rarity]
		border = rar_col
		bg = item.base.color.darkened(0.72)
		if item.base.icon != null:
			b.icon = item.base.icon
		else:
			b.text = item.display_name
			b.add_theme_color_override("font_color", rar_col)

	if selected:
		border = Color(1.0, 0.95, 0.80)

	var sb := _make_stylebox(bg, border, 3 if selected else (2 if item != null else 1), 6)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, sb)


# ==============================================================================
# DIABLO / PATH OF EXILE TOOLTIP CARD
# ==============================================================================

func _refresh_detail() -> void:
	for c in _detail_content.get_children():
		c.queue_free()

	_btn_primary.visible = _selected != null
	_btn_drop.visible = _selected != null and _selected_slot == ""

	if _selected == null:
		var empty_lbl := RichTextLabel.new()
		empty_lbl.bbcode_enabled = true
		empty_lbl.fit_content = true
		empty_lbl.scroll_active = false
		empty_lbl.text = "[center][color=#665c4f]\n\n◈ NO ITEM SELECTED ◈\n\nTap any item in your bag or equipment to inspect affixes and compare combat stats.[/color][/center]"
		_detail_content.add_child(empty_lbl)
		return

	# Build PoE Item Card
	_build_item_card(_detail_content, _selected)

	# Comparison & Actions
	if _selected_slot == "":
		_btn_primary.text = "⚔ Equip"
		_btn_primary.disabled = false

		# Stat Delta section
		var comp_box := PanelContainer.new()
		var comp_sb := _make_stylebox(Color(0.10, 0.09, 0.13), Color(0.28, 0.25, 0.32), 1, 6)
		comp_sb.set_content_margin_all(8)
		comp_box.add_theme_stylebox_override("panel", comp_sb)
		_detail_content.add_child(comp_box)

		var comp_vbox := VBoxContainer.new()
		comp_vbox.add_theme_constant_override("separation", 4)
		comp_box.add_child(comp_vbox)

		var delta_hdr := Label.new()
		delta_hdr.text = "EQUIPPING THIS ITEM:"
		delta_hdr.add_theme_font_size_override("font_size", 14)
		delta_hdr.add_theme_color_override("font_color", Color(0.95, 0.85, 0.60))
		comp_vbox.add_child(delta_hdr)

		var delta_lbl := RichTextLabel.new()
		delta_lbl.bbcode_enabled = true
		delta_lbl.fit_content = true
		delta_lbl.scroll_active = false
		delta_lbl.add_theme_font_size_override("normal_font_size", 15)
		delta_lbl.text = _delta_bbcode(_selected)
		comp_vbox.add_child(delta_lbl)

		# Compare with currently worn item in that slot
		var cur = player.equipment.get(_selected.base.slot)
		if cur != null:
			var sep := Label.new()
			sep.text = "──────── CURRENTLY WORN ────────"
			sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sep.add_theme_font_size_override("font_size", 12)
			sep.add_theme_color_override("font_color", Color(0.45, 0.40, 0.35))
			_detail_content.add_child(sep)
			_build_item_card(_detail_content, cur, true)

	else:
		_btn_primary.text = "⬇ Unequip"
		_btn_primary.disabled = player.inventory.size() >= Player.BAG_SIZE
		if _btn_primary.disabled:
			var warn := Label.new()
			warn.text = "⚠️ Inventory full! Free a bag slot to unequip."
			warn.add_theme_font_size_override("font_size", 14)
			warn.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40))
			_detail_content.add_child(warn)


func _build_item_card(parent: Node, item: ItemInstance, compact := false) -> void:
	var rar_col: Color = ItemInstance.RARITY_COLORS[item.rarity]
	var col_hex: String = rar_col.to_html(false)

	# Header Box with Rarity Color Banner
	var card_hdr := PanelContainer.new()
	var hdr_sb := _make_stylebox(rar_col.darkened(0.75), rar_col, 1, 6)
	hdr_sb.set_content_margin_all(8)
	card_hdr.add_theme_stylebox_override("panel", hdr_sb)
	parent.add_child(card_hdr)

	var hdr_vbox := VBoxContainer.new()
	hdr_vbox.add_theme_constant_override("separation", 2)
	card_hdr.add_child(hdr_vbox)

	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 19 if not compact else 16)
	name_lbl.add_theme_color_override("font_color", rar_col)
	hdr_vbox.add_child(name_lbl)

	var base_lbl := Label.new()
	base_lbl.text = "%s  •  Item Level %d" % [SLOT_NAMES.get(item.base.slot, item.base.slot.capitalize()), item.ilvl]
	base_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base_lbl.add_theme_font_size_override("font_size", 13)
	base_lbl.add_theme_color_override("font_color", Color(0.75, 0.70, 0.65))
	hdr_vbox.add_child(base_lbl)

	# Stats body
	var body_lbl := RichTextLabel.new()
	body_lbl.bbcode_enabled = true
	body_lbl.fit_content = true
	body_lbl.scroll_active = false
	body_lbl.add_theme_font_size_override("normal_font_size", 15)

	var txt := ""
	# Implicits
	if item.base.implicit_stat != "":
		txt += "[color=#ffffff]+%d %s[/color] [color=#777777](implicit)[/color]\n" % [
			int(item.base.implicit_value), item.base.implicit_stat.replace("_", " ").capitalize()]
		txt += "[color=#3d3545]────────────────────────────[/color]\n"

	# Explicit affixes
	for a in item.affixes:
		txt += "[color=#7ba6ff]• %s[/color]\n" % a.text

	if item.affixes.is_empty() and item.base.implicit_stat == "":
		txt += "[color=#555555]No magical properties[/color]\n"

	body_lbl.text = txt
	parent.add_child(body_lbl)


func _delta_bbcode(item: ItemInstance) -> String:
	var cmp := player.preview_equip(item)
	var t := ""
	for k in STAT_LABELS:
		var d: float = cmp["after"][k] - cmp["before"][k]
		var txt := ""
		match k:
			"crit_chance":
				var pct := int(round(d * 100.0))
				if pct == 0:
					continue
				txt = "%+d%%" % pct
			"attack_speed":
				if absf(d) < 0.005:
					continue
				txt = "%+.2f /s" % d
			"move_speed":
				var pct := int(round(d * 100.0))
				if pct == 0:
					continue
				txt = "%+d%%" % pct
			_:
				var whole := int(round(d))
				if whole == 0:
					continue
				txt = "%+d" % whole
		var col := "4ade80" if d > 0.0 else "f87171"
		t += "[color=#%s]  %s %s[/color]\n" % [col, txt, STAT_LABELS[k]]
	if t == "":
		t = "[color=#777777]  No changes to core combat stats[/color]\n"
	return t


# ==============================================================================
# INPUT HANDLERS
# ==============================================================================

func _on_bag_pressed(i: int) -> void:
	_selected_slot = ""
	_selected = player.inventory[i] if i < player.inventory.size() else null
	_refresh()


func _on_equip_slot_pressed(slot: String) -> void:
	var it = player.equipment.get(slot)
	_selected = it
	_selected_slot = slot if it != null else ""
	_refresh()


func _on_primary() -> void:
	if _selected == null:
		return
	if _selected_slot == "":
		player.equip_from_bag(_selected)
	else:
		player.unequip(_selected_slot)
	_selected = null
	_selected_slot = ""
	_refresh()


func _on_drop() -> void:
	if _selected == null or _selected_slot != "":
		return
	player.drop_item(_selected)
	_selected = null
	_selected_slot = ""
	_refresh()
