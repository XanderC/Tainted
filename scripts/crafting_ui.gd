class_name CraftingUI
extends CanvasLayer
## Diablo & Path of Exile style Workshop & Merchant UI.
## Opened by the Blacksmith ("smith": Orbs, Salvage, Recipes)
## and the Merchant ("merchant": Buy, Sell) in Ashfall Outpost.

enum Tab { ORBS, SALVAGE, RECIPES, TRADER, SELL }
const TAB_NAMES := {
	Tab.ORBS: "🔮 Orb Crafting",
	Tab.SALVAGE: "🔨 Salvage Forge",
	Tab.RECIPES: "📜 Recipes",
	Tab.TRADER: "🛒 Buy Wares",
	Tab.SELL: "💰 Sell Inventory",
}

const MODES := {
	"smith": [Tab.ORBS, Tab.SALVAGE, Tab.RECIPES],
	"merchant": [Tab.TRADER, Tab.SELL],
}

const ORB_ORDER := ["transmute", "alteration", "augment", "regal", "alchemy", "chaos", "exalt", "divine", "scour"]

var player: Player

var _mode := "smith"
var _root: Control
var _tab := Tab.ORBS

# Header elements
var _npc_title_label: Label
var _gold_label: Label
var _mats_label: RichTextLabel
var _tab_buttons := {}

# Split columns
var _col_left: VBoxContainer
var _col_right: VBoxContainer

# Dynamic UI references
var _bag_buttons: Array[Button] = []
var _selected: ItemInstance = null
var _selected_shop_item := {}
var _message := ""
var _message_ok := true


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	player.inventory_changed.connect(_refresh)
	GameState.changed.connect(_refresh)


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _root.visible:
		close()


func is_open() -> bool:
	return _root.visible


func open(mode: String = "smith") -> void:
	if player.dead:
		return
	_mode = mode
	_tab = MODES[mode][0]
	_selected = null
	_selected_shop_item = {}
	_message = ""
	_root.visible = true
	get_tree().paused = true
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


# ==============================================================================
# UI CONSTRUCTION
# ==============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dark vignette backdrop
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.88)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Main Window Panel
	var window_panel := PanelContainer.new()
	_root.add_child(window_panel)
	window_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	var win_sb := _make_stylebox(Color(0.08, 0.07, 0.10, 0.98), Color(0.48, 0.38, 0.22), 3, 10)
	win_sb.set_content_margin_all(12)
	window_panel.add_theme_stylebox_override("panel", win_sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	window_panel.add_child(outer)

	# TOP HEADER BANNER
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	outer.add_child(header)

	_npc_title_label = Label.new()
	_npc_title_label.text = "GARRICK'S PROVISIONS"
	_npc_title_label.add_theme_font_size_override("font_size", 22)
	_npc_title_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	header.add_child(_npc_title_label)

	# Currency & materials bar
	var mats_panel := PanelContainer.new()
	var mats_sb := _make_stylebox(Color(0.12, 0.10, 0.14, 0.9), Color(0.35, 0.28, 0.20), 1, 6)
	mats_sb.set_content_margin_all(6)
	mats_panel.add_theme_stylebox_override("panel", mats_sb)
	mats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(mats_panel)

	var mats_hbox := HBoxContainer.new()
	mats_hbox.add_theme_constant_override("separation", 14)
	mats_panel.add_child(mats_hbox)

	_gold_label = Label.new()
	_gold_label.text = "🪙 0 Gold"
	_gold_label.add_theme_font_size_override("font_size", 17)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	mats_hbox.add_child(_gold_label)

	_mats_label = RichTextLabel.new()
	_mats_label.bbcode_enabled = true
	_mats_label.fit_content = true
	_mats_label.scroll_active = false
	_mats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mats_label.add_theme_font_size_override("normal_font_size", 14)
	mats_hbox.add_child(_mats_label)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.custom_minimum_size = Vector2(96, 40)
	close_btn.add_theme_font_size_override("font_size", 17)
	close_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.18, 0.12, 0.14), Color(0.60, 0.30, 0.30), 2, 6))
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# NAVIGATION TABS
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	outer.add_child(tabs_row)

	for t in [Tab.TRADER, Tab.SELL, Tab.ORBS, Tab.SALVAGE, Tab.RECIPES]:
		var b := Button.new()
		b.text = TAB_NAMES[t]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 44)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_set_tab.bind(t))
		tabs_row.add_child(b)
		_tab_buttons[t] = b

	# MAIN TWO-COLUMN SPLIT
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	_col_left = VBoxContainer.new()
	_col_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col_left.add_theme_constant_override("separation", 8)
	body.add_child(_col_left)

	_col_right = VBoxContainer.new()
	_col_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col_right.add_theme_constant_override("separation", 8)
	body.add_child(_col_right)


func _set_tab(t: int) -> void:
	_tab = t as Tab
	_message = ""
	_refresh()


func _make_stylebox(bg: Color, border: Color, width := 2, corner := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	return sb


# ==============================================================================
# REFRESH & DISPATCH
# ==============================================================================

func _refresh() -> void:
	if _root == null or not _root.visible:
		return

	# Header title
	if _mode == "merchant":
		_npc_title_label.text = "🪙  GARRICK'S WARES & PROVISIONS"
	else:
		_npc_title_label.text = "🔨  THE ASHEN ANVIL (BLACKSMITH)"

	# Balances
	_gold_label.text = "🪙 %d Gold" % GameState.gold
	var mats_txt := ""
	for k in CraftingDB.MATERIALS:
		var c: String = CraftingDB.MATERIALS[k].color.to_html(false)
		mats_txt += "[color=#%s]%s: %d[/color]   " % [c, CraftingDB.MATERIALS[k].name, GameState.material_count(k)]
	_mats_label.text = mats_txt

	# Tab visibility
	for t in _tab_buttons:
		var b: Button = _tab_buttons[t]
		var allowed: bool = MODES[_mode].has(t)
		b.visible = allowed
		b.button_pressed = t == _tab
		if t == _tab:
			b.add_theme_stylebox_override("normal", _make_stylebox(Color(0.24, 0.18, 0.10), Color(0.95, 0.82, 0.40), 2, 6))
			b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.70))
		else:
			b.add_theme_stylebox_override("normal", _make_stylebox(Color(0.12, 0.10, 0.14), Color(0.35, 0.28, 0.20), 1, 6))
			b.add_theme_color_override("font_color", Color(0.70, 0.65, 0.60))

	# Clear columns
	for c in _col_left.get_children():
		c.queue_free()
	for c in _col_right.get_children():
		c.queue_free()

	# Dispatch by tab
	match _tab:
		Tab.TRADER:
			_build_trader_tab()
		Tab.SELL:
			_build_sell_tab()
		Tab.ORBS:
			_build_orbs_tab()
		Tab.SALVAGE:
			_build_salvage_tab()
		Tab.RECIPES:
			_build_recipes_tab()


# ==============================================================================
# TAB 1: MERCHANT BUY WARES (Diablo / PoE Shop Grid)
# ==============================================================================

func _build_trader_tab() -> void:
	# LEFT: Shopkeeper Wares Showcase
	var shop_panel := PanelContainer.new()
	shop_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8))
	_col_left.add_child(shop_panel)

	var shop_vbox := VBoxContainer.new()
	shop_vbox.add_theme_constant_override("separation", 8)
	shop_panel.add_child(shop_vbox)

	var sh_lbl := Label.new()
	sh_lbl.text = "MERCHANT'S STOCK OF GOODS"
	sh_lbl.add_theme_font_size_override("font_size", 16)
	sh_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	shop_vbox.add_child(sh_lbl)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_vbox.add_child(sc)

	var wares_box := VBoxContainer.new()
	wares_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wares_box.add_theme_constant_override("separation", 8)
	sc.add_child(wares_box)

	# 1. Recipes for sale
	var recipes_for_sale := []
	for id in CraftingDB.RECIPES:
		var r: Dictionary = CraftingDB.RECIPES[id]
		if r.source == "vendor" and not GameState.knows_recipe(id):
			recipes_for_sale.append(id)

	if not recipes_for_sale.is_empty():
		var rec_hdr := Label.new()
		rec_hdr.text = "📜 RECIPE SCROLLS"
		rec_hdr.add_theme_font_size_override("font_size", 15)
		rec_hdr.add_theme_color_override("font_color", Color(0.85, 0.75, 0.50))
		wares_box.add_child(rec_hdr)

		for id in recipes_for_sale:
			var r: Dictionary = CraftingDB.RECIPES[id]
			_add_shop_card(wares_box, "recipe", id, r.name, r.desc, int(r.price), Color(0.95, 0.85, 0.45), null)

	# 2. Crafting Orbs (PoE Currencies)
	var orb_hdr := Label.new()
	orb_hdr.text = "🔮 CRAFTING ORBS"
	orb_hdr.add_theme_font_size_override("font_size", 15)
	orb_hdr.add_theme_color_override("font_color", Color(0.85, 0.75, 0.50))
	wares_box.add_child(orb_hdr)

	var orb_grid := GridContainer.new()
	orb_grid.columns = 3
	orb_grid.add_theme_constant_override("h_separation", 6)
	orb_grid.add_theme_constant_override("v_separation", 6)
	wares_box.add_child(orb_grid)

	for id in ORB_ORDER:
		var o: Dictionary = CraftingDB.ORBS[id]
		var icon_path := "res://assets/icons/orbs/%s.png" % id
		var tex: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null
		_add_orb_shop_button(orb_grid, id, o.short, int(o.price), o.color, tex)

	# 3. Materials
	var mat_hdr := Label.new()
	mat_hdr.text = "⚒ SALVAGE MATERIALS"
	mat_hdr.add_theme_font_size_override("font_size", 15)
	mat_hdr.add_theme_color_override("font_color", Color(0.85, 0.75, 0.50))
	wares_box.add_child(mat_hdr)

	for id in CraftingDB.MATERIALS:
		var m: Dictionary = CraftingDB.MATERIALS[id]
		if int(m.price) > 0:
			_add_shop_card(wares_box, "material", id, m.name, "Salvage crafting component", int(m.price), m.color, null)

	# RIGHT: Player's Inventory Grid + Item Purchase Details
	_build_right_player_bag_and_action("BUY")


func _add_shop_card(parent: Node, type: String, id: String, title: String, desc: String, price: int, col: Color, icon: Texture2D) -> void:
	var row := PanelContainer.new()
	var can_afford := GameState.gold >= price
	var is_sel: bool = String(_selected_shop_item.get("id", "")) == id
	var border_c := Color.WHITE if is_sel else (Color(0.75, 0.60, 0.25) if can_afford else Color(0.28, 0.25, 0.30))
	row.add_theme_stylebox_override("panel", _make_stylebox(Color(0.11, 0.10, 0.14), border_c, 2 if is_sel else 1, 6))
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = "[color=#%s][b]%s[/b][/color]\n[color=#888888]%s[/color]" % [col.to_html(false), title, desc]
	hbox.add_child(info)

	var btn := Button.new()
	btn.text = "🪙 %dg" % price
	btn.custom_minimum_size = Vector2(90, 44)
	btn.disabled = not can_afford
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(func():
		_selected_shop_item = {"type": type, "id": id, "name": title, "price": price, "desc": desc, "color": col}
		_execute_buy()
	)
	hbox.add_child(btn)


func _add_orb_shop_button(parent: Node, id: String, short_name: String, price: int, col: Color, icon: Texture2D) -> void:
	var can_afford := GameState.gold >= price
	var is_sel: bool = String(_selected_shop_item.get("id", "")) == id
	var b := Button.new()
	b.custom_minimum_size = Vector2(100, 72)
	b.clip_text = true
	b.expand_icon = true
	b.icon = icon
	b.text = "\n\n%s\n🪙%dg" % [short_name, price]
	b.add_theme_font_size_override("font_size", 11)
	var sb := _make_stylebox(Color(0.12, 0.10, 0.15), Color.WHITE if is_sel else (col if can_afford else Color(0.3, 0.3, 0.3)), 2 if is_sel else 1, 6)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", col if can_afford else Color(0.5, 0.5, 0.5))
	b.pressed.connect(func():
		var o: Dictionary = CraftingDB.ORBS[id]
		_selected_shop_item = {"type": "orb", "id": id, "name": o.name, "price": price, "desc": o.desc, "color": col}
		_refresh()
	)
	parent.add_child(b)


func _execute_buy() -> void:
	if _selected_shop_item.is_empty():
		return
	var type: String = _selected_shop_item.get("type", "")
	var id: String = _selected_shop_item.get("id", "")
	match type:
		"recipe":
			var ok := GameState.buy_recipe(id)
			_message = "Learned %s!" % _selected_shop_item.get("name", "") if ok else "Not enough gold!"
			_message_ok = ok
		"orb":
			var ok := GameState.buy_orb(id)
			_message = "Purchased %s!" % _selected_shop_item.get("name", "") if ok else "Not enough gold!"
			_message_ok = ok
		"material":
			var ok := GameState.buy_material(id)
			_message = "Purchased %s!" % _selected_shop_item.get("name", "") if ok else "Not enough gold!"
			_message_ok = ok
	_refresh()


# ==============================================================================
# TAB 2: MERCHANT SELL INVENTORY (Diablo / PoE Vendor Screen)
# ==============================================================================

func _build_sell_tab() -> void:
	# LEFT: Player's Inventory Bag Grid
	var bag_panel := PanelContainer.new()
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8))
	_col_left.add_child(bag_panel)

	var bag_vbox := VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 10)
	bag_panel.add_child(bag_vbox)

	var hdr := Label.new()
	hdr.text = "SELECT ITEM TO SELL"
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	bag_vbox.add_child(hdr)

	# 6x4 Bag Grid
	var bag_grid := GridContainer.new()
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 6)
	bag_grid.add_theme_constant_override("v_separation", 6)
	bag_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bag_vbox.add_child(bag_grid)

	_bag_buttons.clear()
	for i in Player.BAG_SIZE:
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(66, 66)
		slot_btn.clip_text = true
		slot_btn.expand_icon = true
		slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_btn.add_theme_font_size_override("font_size", 11)
		slot_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var item: ItemInstance = player.inventory[i] if i < player.inventory.size() else null
		_style_bag_button(slot_btn, item, item != null and item == _selected)
		slot_btn.pressed.connect(func():
			_selected = item
			_refresh()
		)
		bag_grid.add_child(slot_btn)
		_bag_buttons.append(slot_btn)

	# Bulk vendor cleanup buttons
	var bulk_box := HBoxContainer.new()
	bulk_box.add_theme_constant_override("separation", 10)
	bag_vbox.add_child(bulk_box)

	var has_norm := player.inventory.any(func(i): return i.rarity == ItemInstance.Rarity.NORMAL)
	var btn_norm := Button.new()
	btn_norm.text = "🧹 Sell All Normal"
	btn_norm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_norm.custom_minimum_size = Vector2(0, 44)
	btn_norm.disabled = not has_norm
	btn_norm.pressed.connect(_sell_all_rarity.bind(ItemInstance.Rarity.NORMAL))
	bulk_box.add_child(btn_norm)

	var has_magic := player.inventory.any(func(i): return i.rarity == ItemInstance.Rarity.MAGIC)
	var btn_magic := Button.new()
	btn_magic.text = "🧹 Sell All Magic"
	btn_magic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_magic.custom_minimum_size = Vector2(0, 44)
	btn_magic.disabled = not has_magic
	btn_magic.pressed.connect(_sell_all_rarity.bind(ItemInstance.Rarity.MAGIC))
	bulk_box.add_child(btn_magic)

	# RIGHT: Selected Item Vendor Receipt & Tooltip
	var right_panel := PanelContainer.new()
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.38, 0.30, 0.20), 2, 8))
	_col_right.add_child(right_panel)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(r_vbox)

	_show_status_message(r_vbox)

	if _selected == null:
		var empty_lbl := RichTextLabel.new()
		empty_lbl.bbcode_enabled = true
		empty_lbl.fit_content = true
		empty_lbl.text = "[center][color=#665c4f]\n\n◈ NO ITEM SELECTED ◈\n\nTap any item in your bag to inspect and sell it for gold.[/color][/center]"
		r_vbox.add_child(empty_lbl)
	else:
		_build_item_card(r_vbox, _selected)

		var price: int = GameState.sell_price(_selected)
		var receipt := PanelContainer.new()
		receipt.add_theme_stylebox_override("panel", _make_stylebox(Color(0.14, 0.12, 0.08), Color(0.85, 0.70, 0.25), 1, 6))
		r_vbox.add_child(receipt)

		var rec_lbl := Label.new()
		rec_lbl.text = "VENDOR OFFER: 🪙 +%d GOLD" % price
		rec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec_lbl.add_theme_font_size_override("font_size", 18)
		rec_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		receipt.add_child(rec_lbl)

		var sell_btn := Button.new()
		sell_btn.text = "💰 Sell Item"
		sell_btn.custom_minimum_size = Vector2(0, 52)
		sell_btn.add_theme_font_size_override("font_size", 20)
		sell_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.22, 0.16, 0.08), Color(0.95, 0.80, 0.30), 2, 6))
		sell_btn.pressed.connect(func():
			var g := GameState.sell_item(_selected)
			_selected = null
			_message = "Sold for %d gold!" % g
			_message_ok = g > 0
			_refresh()
		)
		r_vbox.add_child(sell_btn)


func _sell_all_rarity(rarity: int) -> void:
	var total := 0
	for it in player.inventory.duplicate():
		if it.rarity == rarity:
			total += GameState.sell_item(it)
	_selected = null
	_message = "Sold items for %d gold!" % total
	_message_ok = total > 0
	_refresh()


# ==============================================================================
# TAB 3: ORB CRAFTING BENCH (Blacksmith)
# ==============================================================================

func _build_orbs_tab() -> void:
	# LEFT: Items to modify
	_build_left_items_list()

	# RIGHT: Orb Bench
	var right_panel := PanelContainer.new()
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.38, 0.30, 0.20), 2, 8))
	_col_right.add_child(right_panel)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(r_vbox)

	_show_status_message(r_vbox)

	if _selected == null:
		var empty_lbl := RichTextLabel.new()
		empty_lbl.bbcode_enabled = true
		empty_lbl.fit_content = true
		empty_lbl.text = "[center][color=#665c4f]\n\n◈ SELECT AN ITEM TO MODIFY ◈\n\nChoose an item from the left, then apply crafting orbs to roll or upgrade affixes.[/color][/center]"
		r_vbox.add_child(empty_lbl)
	else:
		_build_item_card(r_vbox, _selected)

		var orb_title := Label.new()
		orb_title.text = "APPLY CRAFTING ORBS:"
		orb_title.add_theme_font_size_override("font_size", 15)
		orb_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		r_vbox.add_child(orb_title)

		var orb_grid := GridContainer.new()
		orb_grid.columns = 3
		orb_grid.add_theme_constant_override("h_separation", 8)
		orb_grid.add_theme_constant_override("v_separation", 8)
		r_vbox.add_child(orb_grid)

		for id in ORB_ORDER:
			var o: Dictionary = CraftingDB.ORBS[id]
			var count: int = GameState.orb_count(id)
			var can_use: bool = count > 0 and Crafting.orb_block_reason(_selected, id) == ""
			var icon_path := "res://assets/icons/orbs/%s.png" % id
			var tex: Texture2D = load(icon_path) if ResourceLoader.exists(icon_path) else null

			var b := Button.new()
			b.custom_minimum_size = Vector2(100, 68)
			b.clip_text = true
			b.expand_icon = true
			b.icon = tex
			b.text = "\n\n%s (x%d)" % [o.short, count]
			b.disabled = not can_use
			b.add_theme_font_size_override("font_size", 11)
			b.add_theme_stylebox_override("normal", _make_stylebox(Color(0.12, 0.10, 0.15), o.color if can_use else Color(0.3, 0.3, 0.3), 2 if can_use else 1, 6))
			b.add_theme_color_override("font_color", o.color if can_use else Color(0.5, 0.5, 0.5))
			b.pressed.connect(func():
				var res := Crafting.apply_orb(player, _selected, id)
				_message = res.msg
				_message_ok = res.ok
				_refresh()
			)
			orb_grid.add_child(b)


# ==============================================================================
# TAB 4: SALVAGE FORGE (Blacksmith)
# ==============================================================================

func _build_salvage_tab() -> void:
	_build_left_items_list()

	var right_panel := PanelContainer.new()
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.38, 0.30, 0.20), 2, 8))
	_col_right.add_child(right_panel)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(r_vbox)

	_show_status_message(r_vbox)

	if _selected == null:
		var empty_lbl := RichTextLabel.new()
		empty_lbl.bbcode_enabled = true
		empty_lbl.fit_content = true
		empty_lbl.text = "[center][color=#665c4f]\n\n◈ SALVAGE FORGE ◈\n\nBreak items down into Iron Scrap, Arcane Dust, and Wraith Essence.[/color][/center]"
		r_vbox.add_child(empty_lbl)
	else:
		_build_item_card(r_vbox, _selected)
		var sal_btn := Button.new()
		sal_btn.text = "🔨 Salvage Selected Item"
		sal_btn.custom_minimum_size = Vector2(0, 50)
		sal_btn.add_theme_font_size_override("font_size", 18)
		sal_btn.pressed.connect(func():
			var g := Crafting.salvage(player, _selected)
			_selected = null
			_message = "Salvaged materials!" if not g.is_empty() else "Failed to salvage"
			_message_ok = not g.is_empty()
			_refresh()
		)
		r_vbox.add_child(sal_btn)

	var bulk_title := Label.new()
	bulk_title.text = "BATCH SALVAGE:"
	bulk_title.add_theme_font_size_override("font_size", 14)
	bulk_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	r_vbox.add_child(bulk_title)

	var b_norm := Button.new()
	b_norm.text = "🔨 Salvage All Normal Items"
	b_norm.custom_minimum_size = Vector2(0, 42)
	b_norm.pressed.connect(func():
		Crafting.salvage_all(player, ItemInstance.Rarity.NORMAL)
		_refresh()
	)
	r_vbox.add_child(b_norm)

	var b_magic := Button.new()
	b_magic.text = "🔨 Salvage All Magic Items"
	b_magic.custom_minimum_size = Vector2(0, 42)
	b_magic.pressed.connect(func():
		Crafting.salvage_all(player, ItemInstance.Rarity.MAGIC)
		_refresh()
	)
	r_vbox.add_child(b_magic)


# ==============================================================================
# TAB 5: RECIPES (Blacksmith)
# ==============================================================================

func _build_recipes_tab() -> void:
	var rec_panel := PanelContainer.new()
	rec_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rec_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8))
	_col_left.add_child(rec_panel)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 8)
	rec_panel.add_child(r_vbox)

	var r_lbl := Label.new()
	r_lbl.text = "FORGE CRAFTING RECIPES"
	r_lbl.add_theme_font_size_override("font_size", 16)
	r_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	r_vbox.add_child(r_lbl)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_vbox.add_child(sc)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)

	for id in CraftingDB.RECIPES:
		if not GameState.knows_recipe(id):
			continue
		var r: Dictionary = CraftingDB.RECIPES[id]
		var can_afford: bool = GameState.can_afford_materials(r.cost)

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.11, 0.10, 0.14), Color(0.6, 0.5, 0.2) if can_afford else Color(0.25, 0.22, 0.28), 1, 6))
		list.add_child(card)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		card.add_child(hbox)

		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "[b]%s[/b] - [color=#999999]%s[/color]\n%s" % [r.name, r.desc, CraftingDB.cost_text(r.cost, GameState.materials)]
		hbox.add_child(info)

		var craft_btn := Button.new()
		craft_btn.text = "Forge"
		craft_btn.custom_minimum_size = Vector2(90, 44)
		craft_btn.disabled = not can_afford
		craft_btn.pressed.connect(func():
			var res := Crafting.craft(player, id)
			_message = res.msg
			_message_ok = res.ok
			_refresh()
		)
		hbox.add_child(craft_btn)

	# Right column shows player bag
	_build_right_player_bag_and_action("RECIPE")


# ==============================================================================
# COMMON HELPERS: BAG GRID & ITEM CARDS
# ==============================================================================

func _build_right_player_bag_and_action(context: String) -> void:
	var bag_panel := PanelContainer.new()
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8))
	_col_right.add_child(bag_panel)

	var bag_vbox := VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 8)
	bag_panel.add_child(bag_vbox)

	var bh := Label.new()
	bh.text = "YOUR INVENTORY  (%d / 24)" % player.inventory.size()
	bh.add_theme_font_size_override("font_size", 16)
	bh.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	bag_vbox.add_child(bh)

	var bag_grid := GridContainer.new()
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 6)
	bag_grid.add_theme_constant_override("v_separation", 6)
	bag_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bag_vbox.add_child(bag_grid)

	_bag_buttons.clear()
	for i in Player.BAG_SIZE:
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(58, 58)
		slot_btn.clip_text = true
		slot_btn.expand_icon = true
		slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_btn.add_theme_font_size_override("font_size", 11)
		slot_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var item: ItemInstance = player.inventory[i] if i < player.inventory.size() else null
		_style_bag_button(slot_btn, item, item != null and item == _selected)
		bag_grid.add_child(slot_btn)
		_bag_buttons.append(slot_btn)

	_show_status_message(bag_vbox)

	if context == "BUY" and not _selected_shop_item.is_empty():
		var buy_card := PanelContainer.new()
		buy_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.12, 0.10, 0.15), Color(0.85, 0.70, 0.25), 1, 6))
		bag_vbox.add_child(buy_card)

		var bc_vbox := VBoxContainer.new()
		bc_vbox.add_theme_constant_override("separation", 6)
		buy_card.add_child(bc_vbox)

		var name_l := Label.new()
		name_l.text = _selected_shop_item.get("name", "")
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.add_theme_color_override("font_color", _selected_shop_item.get("color", Color.WHITE))
		bc_vbox.add_child(name_l)

		var desc_l := Label.new()
		desc_l.text = _selected_shop_item.get("desc", "")
		desc_l.add_theme_font_size_override("font_size", 13)
		desc_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		bc_vbox.add_child(desc_l)

		var buy_btn := Button.new()
		var p: int = _selected_shop_item.get("price", 0)
		buy_btn.text = "🛒 Buy for %d Gold" % p
		buy_btn.custom_minimum_size = Vector2(0, 46)
		buy_btn.disabled = GameState.gold < p
		buy_btn.add_theme_font_size_override("font_size", 17)
		buy_btn.pressed.connect(_execute_buy)
		bc_vbox.add_child(buy_btn)


func _build_left_items_list() -> void:
	var pnl := PanelContainer.new()
	pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pnl.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.05, 0.08, 0.95), Color(0.32, 0.26, 0.18), 1, 8))
	_col_left.add_child(pnl)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	pnl.add_child(vbox)

	var th := Label.new()
	th.text = "YOUR GEAR & BAG ITEMS"
	th.add_theme_font_size_override("font_size", 16)
	th.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	vbox.add_child(th)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(sc)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)

	var all: Array = []
	for slot in Player.SLOTS:
		if player.equipment.has(slot):
			all.append(player.equipment[slot])
	all.append_array(player.inventory)

	for it in all:
		var b := Button.new()
		b.custom_minimum_size = Vector2(66, 66)
		b.clip_text = true
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 10)
		_style_bag_button(b, it, it == _selected)
		b.pressed.connect(func():
			_selected = it
			_refresh()
		)
		grid.add_child(b)


func _style_bag_button(b: Button, item: ItemInstance, selected: bool) -> void:
	b.icon = null
	b.text = ""
	var bg: Color
	var border: Color

	if item == null:
		bg = Color(0.09, 0.08, 0.12)
		border = Color(0.20, 0.18, 0.24)
	else:
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


func _build_item_card(parent: Node, item: ItemInstance) -> void:
	var rar_col: Color = ItemInstance.RARITY_COLORS[item.rarity]

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
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", rar_col)
	hdr_vbox.add_child(name_lbl)

	var base_lbl := Label.new()
	base_lbl.text = "%s  •  Item Level %d" % [item.base.slot.capitalize(), item.ilvl]
	base_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base_lbl.add_theme_font_size_override("font_size", 12)
	base_lbl.add_theme_color_override("font_color", Color(0.75, 0.70, 0.65))
	hdr_vbox.add_child(base_lbl)

	var body_lbl := RichTextLabel.new()
	body_lbl.bbcode_enabled = true
	body_lbl.fit_content = true
	body_lbl.scroll_active = false
	body_lbl.add_theme_font_size_override("normal_font_size", 14)

	var txt := ""
	if item.base.implicit_stat != "":
		txt += "[color=#ffffff]+%d %s[/color] [color=#777777](implicit)[/color]\n" % [
			int(item.base.implicit_value), item.base.implicit_stat.replace("_", " ").capitalize()]
		txt += "[color=#3d3545]────────────────────────────[/color]\n"

	for a in item.affixes:
		txt += "[color=#7ba6ff]• %s[/color]\n" % a.text

	if item.affixes.is_empty() and item.base.implicit_stat == "":
		txt += "[color=#555555]No magical properties[/color]\n"

	body_lbl.text = txt
	parent.add_child(body_lbl)


func _show_status_message(parent: Node) -> void:
	if _message.is_empty():
		return
	var pnl := PanelContainer.new()
	var col := Color(0.20, 0.80, 0.40) if _message_ok else Color(0.95, 0.40, 0.40)
	pnl.add_theme_stylebox_override("panel", _make_stylebox(col.darkened(0.85), col, 1, 6))
	parent.add_child(pnl)

	var l := Label.new()
	l.text = _message
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	pnl.add_child(l)
