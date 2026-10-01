class_name CraftingUI
extends CanvasLayer
## Workshop screen: Orbs (modify items), Salvage (items to materials),
## Recipes (craft from materials) and Trader (spend gold). Pauses the game while open.
## Opened by the Blacksmith ("smith") and the Merchant ("merchant") in town.

enum Tab { ORBS, SALVAGE, RECIPES, TRADER, SELL }
const TAB_NAMES := ["Orbs", "Salvage", "Recipes", "Buy", "Sell"]
## Which tabs each NPC offers.
const MODES := {
	"smith": [Tab.ORBS, Tab.SALVAGE, Tab.RECIPES],
	"merchant": [Tab.TRADER, Tab.SELL],
}
const ORB_ORDER := ["transmute", "alteration", "augment", "regal", "alchemy", "chaos", "exalt", "divine", "scour"]

var player: Player

var _mode := "smith"
var _root: Control
var _tab := Tab.ORBS
var _tab_buttons: Array[Button] = []
var _stash_label: RichTextLabel
var _left: VBoxContainer
var _item_grid: GridContainer
var _right: VBoxContainer
var _selected: ItemInstance = null
var _message := ""
var _message_ok := true


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
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


## mode: "smith" or "merchant"
func open(mode: String = "smith") -> void:
	if player.dead:
		return
	_mode = mode
	_tab = MODES[mode][0]
	_selected = null
	_message = ""
	_root.visible = true
	get_tree().paused = true
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


# ---------- skeleton ----------

func _build() -> void:
	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.11, 0.97)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", bg)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(112, 52)
		b.add_theme_font_size_override("font_size", 21)
		b.pressed.connect(_set_tab.bind(i))
		header.add_child(b)
		_tab_buttons.append(b)
	_stash_label = RichTextLabel.new()
	_stash_label.bbcode_enabled = true
	_stash_label.fit_content = true
	_stash_label.scroll_active = false
	_stash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stash_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stash_label.add_theme_font_size_override("normal_font_size", 15)
	header.add_child(_stash_label)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 52)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(400, 0)
	body.add_child(_left)
	var lt := Label.new()
	lt.text = "Your items  ([E] = worn)"
	_left.add_child(lt)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left.add_child(sc)
	_item_grid = GridContainer.new()
	_item_grid.columns = 3
	_item_grid.add_theme_constant_override("h_separation", 6)
	_item_grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(_item_grid)

	var rsc := ScrollContainer.new()
	rsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(rsc)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 8)
	rsc.add_child(_right)


func _set_tab(i: int) -> void:
	_tab = i as Tab
	_message = ""
	_refresh()


# ---------- refresh ----------

func _refresh() -> void:
	if _root == null or not _root.visible:
		return
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == _tab
		_tab_buttons[i].visible = MODES[_mode].has(i)
	_stash_label.text = _stash_bbcode()
	_left.visible = _tab == Tab.ORBS or _tab == Tab.SALVAGE or _tab == Tab.SELL
	_rebuild_items()
	for c in _right.get_children():
		c.queue_free()
	match _tab:
		Tab.ORBS: _build_orbs()
		Tab.SALVAGE: _build_salvage()
		Tab.RECIPES: _build_recipes()
		Tab.TRADER: _build_trader()
		Tab.SELL: _build_sell()


func _stash_bbcode() -> String:
	var t := "[color=#ffd933]Gold %d[/color]" % GameState.gold
	for k in CraftingDB.MATERIALS:
		var c: String = CraftingDB.MATERIALS[k].color.to_html(false)
		t += "   [color=#%s]%s %d[/color]" % [c, CraftingDB.MATERIALS[k].name, GameState.material_count(k)]
	return t


func _all_items() -> Array:
	var out: Array = []
	for slot in Player.SLOTS:
		if player.equipment.has(slot):
			out.append(player.equipment[slot])
	out.append_array(player.inventory)
	return out


func _rebuild_items() -> void:
	for c in _item_grid.get_children():
		c.queue_free()
	var items := _all_items()
	if _selected != null and not items.has(_selected):
		_selected = null
	for it in items:
		var b := Button.new()
		var worn: bool = player.equipment.get(it.base.slot) == it
		b.text = ("[E] " if worn else "") + it.display_name
		b.custom_minimum_size = Vector2(122, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		_style(b, it, it == _selected)
		b.pressed.connect(_select.bind(it))
		_item_grid.add_child(b)


func _style(b: Button, item: ItemInstance, selected: bool) -> void:
	var col: Color = ItemInstance.RARITY_COLORS[item.rarity]
	var sb := StyleBoxFlat.new()
	sb.bg_color = item.base.color.darkened(0.65)
	sb.border_color = Color.WHITE if selected else col
	sb.set_border_width_all(4 if selected else 2)
	sb.set_corner_radius_all(6)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(fc, col)


func _select(it: ItemInstance) -> void:
	_selected = it
	_message = ""
	_refresh()


func _item_bbcode(item: ItemInstance) -> String:
	var col: String = ItemInstance.RARITY_COLORS[item.rarity].to_html(false)
	var t := "[b][color=#%s]%s[/color][/b]\n" % [col, item.display_name]
	t += "[color=#888888]%s | ilvl %d | %s[/color]\n" % [
		ItemInstance.Rarity.keys()[item.rarity].capitalize(), item.ilvl, item.base.slot.capitalize()]
	if item.base.implicit_stat != "":
		t += "[color=#bbbbbb]+%d %s[/color]\n" % [int(item.base.implicit_value), item.base.implicit_stat.replace("_", " ")]
	for a in item.affixes:
		t += "[color=#8fb0ff]%s[/color]\n" % a.text
	if item.affixes.is_empty():
		t += "[color=#666666](no affixes)[/color]\n"
	return t


func _rich(text: String, size := 19) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size + 3)
	l.text = text
	return l


func _msg_label() -> void:
	if _message != "":
		var col := "66dd66" if _message_ok else "ee6655"
		_right.add_child(_rich("[color=#%s]%s[/color]" % [col, _message], 20))


func _button(text: String, cb: Callable, min_h := 60, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", 18)
	b.disabled = disabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


# ---------- Orbs tab ----------

func _build_orbs() -> void:
	if _selected == null:
		_right.add_child(_rich("[color=#888888]Pick an item on the left, then tap an orb to use it on that item.\nWorn items can be crafted on too.[/color]"))
	else:
		_right.add_child(_rich(_item_bbcode(_selected), 20))
	_msg_label()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(grid)
	for id in ORB_ORDER:
		var o: Dictionary = CraftingDB.ORBS[id]
		var n := GameState.orb_count(id)
		var why := Crafting.orb_block_reason(_selected, id)
		var sub: String = o.desc if why == "" else why
		var b := _button("%s   x%d\n%s" % [o.short, n, sub], _use_orb.bind(id), 64, n <= 0 or why != "")
		b.add_theme_color_override("font_color", o.color)
		b.add_theme_color_override("font_disabled_color", o.color.darkened(0.45))
		b.add_theme_font_size_override("font_size", 16)
		var osb := StyleBoxFlat.new()
		osb.bg_color = Color(0.13, 0.12, 0.16)
		osb.border_color = o.color if not b.disabled else o.color.darkened(0.6)
		osb.set_border_width_all(2)
		osb.set_corner_radius_all(6)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, osb)
		grid.add_child(b)


func _use_orb(id: String) -> void:
	var res := Crafting.apply_orb(player, _selected, id)
	_message = res.msg
	_message_ok = res.ok
	_refresh()


# ---------- Salvage tab ----------

func _build_salvage() -> void:
	var inbag := _selected != null and player.inventory.has(_selected)
	if _selected == null:
		_right.add_child(_rich("[color=#888888]Pick an item from your bag to break it down into materials.\nWorn items can't be salvaged. Unequip them first.[/color]"))
	else:
		_right.add_child(_rich(_item_bbcode(_selected), 20))
		if inbag:
			_right.add_child(_rich("Yields: [color=#b0e0b0]%s[/color]" % CraftingDB.salvage_preview(_selected)))
		else:
			_right.add_child(_rich("[color=#ee6655]This item is worn.[/color]"))
	_msg_label()
	_right.add_child(_button("Salvage selected item", _salvage_selected, 64, not inbag))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_right.add_child(row)
	var has_n := player.inventory.any(func(i): return i.rarity == ItemInstance.Rarity.NORMAL)
	var has_m := player.inventory.any(func(i): return i.rarity == ItemInstance.Rarity.MAGIC)
	row.add_child(_button("Salvage all Normal", _salvage_all.bind(ItemInstance.Rarity.NORMAL), 56, not has_n))
	row.add_child(_button("Salvage all Magic", _salvage_all.bind(ItemInstance.Rarity.MAGIC), 56, not has_m))
	_right.add_child(_rich("[color=#888888]Rare items are only salvaged one at a time, so you don't break a good one by accident.[/color]", 16))


func _gain_text(g: Dictionary) -> String:
	var parts: Array[String] = []
	for k in g:
		parts.append("%d %s" % [g[k], CraftingDB.MATERIALS[k].name])
	return ", ".join(PackedStringArray(parts))


func _salvage_selected() -> void:
	var g := Crafting.salvage(player, _selected)
	_selected = null
	_message = "Salvaged: " + _gain_text(g) if not g.is_empty() else "Nothing to salvage"
	_message_ok = not g.is_empty()
	_refresh()


func _salvage_all(rarity: int) -> void:
	var g := Crafting.salvage_all(player, rarity)
	_message = "Salvaged: " + _gain_text(g) if not g.is_empty() else "Nothing to salvage"
	_message_ok = not g.is_empty()
	_refresh()


# ---------- Recipes tab ----------

func _build_recipes() -> void:
	_right.add_child(_rich("[b]Recipes[/b]  [color=#888888]Found on monsters and bosses, or bought from the Trader.[/color]", 19))
	_msg_label()
	var unknown := 0
	for id in CraftingDB.RECIPES:
		if not GameState.knows_recipe(id):
			unknown += 1
			continue
		var r: Dictionary = CraftingDB.RECIPES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_right.add_child(row)
		var info := _rich("[b]%s[/b]  [color=#999999]%s[/color]\n%s" % [
			r.name, r.desc, CraftingDB.cost_text(r.cost, GameState.materials)], 17)
		row.add_child(info)
		var b := _button("Craft", _craft.bind(id), 60, not GameState.can_afford_materials(r.cost))
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.custom_minimum_size = Vector2(120, 60)
		row.add_child(b)
	if unknown > 0:
		_right.add_child(_rich("[color=#777777]%d recipe%s still undiscovered.[/color]" % [unknown, "" if unknown == 1 else "s"], 16))


func _craft(id: String) -> void:
	var res := Crafting.craft(player, id)
	_message = res.msg
	_message_ok = res.ok
	_refresh()


# ---------- Trader tab ----------

func _build_trader() -> void:
	_right.add_child(_rich("[b]Merchant[/b]  [color=#888888]Spend gold. Gold drops from monsters and bosses.[/color]", 19))
	_msg_label()
	var any_recipe := false
	for id in CraftingDB.RECIPES:
		var r: Dictionary = CraftingDB.RECIPES[id]
		if r.source != "vendor" or GameState.knows_recipe(id):
			continue
		if not any_recipe:
			_right.add_child(_rich("[color=#e6bf80][b]Recipes[/b][/color]", 18))
			any_recipe = true
		_trade_row("[b]%s[/b]  [color=#999999]%s[/color]\n%s" % [r.name, r.desc, CraftingDB.cost_text(r.cost, GameState.materials)],
			int(r.price), _buy_recipe.bind(id))
	_right.add_child(_rich("[color=#e6bf80][b]Orbs[/b][/color]", 18))
	for id in ORB_ORDER:
		var o: Dictionary = CraftingDB.ORBS[id]
		_trade_row("[color=#%s][b]%s[/b][/color]  [color=#999999]%s[/color]" % [o.color.to_html(false), o.name, o.desc],
			int(o.price), _buy_orb.bind(id))
	_right.add_child(_rich("[color=#e6bf80][b]Materials[/b][/color]", 18))
	for id in CraftingDB.MATERIALS:
		var m: Dictionary = CraftingDB.MATERIALS[id]
		if int(m.price) > 0:
			_trade_row("[color=#%s][b]%s[/b][/color]" % [m.color.to_html(false), m.name], int(m.price), _buy_material.bind(id))


func _trade_row(text: String, price: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(row)
	row.add_child(_rich(text, 17))
	var b := _button("Buy  %dg" % price, cb, 52, GameState.gold < price)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size = Vector2(130, 52)
	row.add_child(b)


func _buy_recipe(id: String) -> void:
	_message = "Learned %s" % CraftingDB.RECIPES[id].name if GameState.buy_recipe(id) else "Can't buy that"
	_message_ok = GameState.knows_recipe(id)
	_refresh()


func _buy_orb(id: String) -> void:
	var ok := GameState.buy_orb(id)
	_message = "Bought %s" % CraftingDB.ORBS[id].short if ok else "Not enough gold"
	_message_ok = ok
	_refresh()


func _buy_material(id: String) -> void:
	var ok := GameState.buy_material(id)
	_message = "Bought %s" % CraftingDB.MATERIALS[id].name if ok else "Not enough gold"
	_message_ok = ok
	_refresh()


# ---------- Sell tab ----------

func _build_sell() -> void:
	var inbag := _selected != null and player.inventory.has(_selected)
	if _selected == null:
		_right.add_child(_rich("[color=#888888]Pick an item from your bag to sell it. Worn items can't be sold.[/color]"))
	else:
		_right.add_child(_rich(_item_bbcode(_selected), 20))
		if inbag:
			_right.add_child(_rich("Sells for [color=#ffd933]%d gold[/color]" % GameState.sell_price(_selected)))
		else:
			_right.add_child(_rich("[color=#ee6655]This item is worn.[/color]"))
	_msg_label()
	_right.add_child(_button("Sell selected item", _sell_selected, 64, not inbag))
	var has_n := player.inventory.any(func(i): return i.rarity == ItemInstance.Rarity.NORMAL)
	_right.add_child(_button("Sell all Normal items in bag", _sell_normals, 56, not has_n))


func _sell_selected() -> void:
	var g := GameState.sell_item(_selected)
	_selected = null
	_message = "Sold for %d gold" % g
	_message_ok = g > 0
	_refresh()


func _sell_normals() -> void:
	var total := 0
	for it in player.inventory.duplicate():
		if it.rarity == ItemInstance.Rarity.NORMAL:
			total += GameState.sell_item(it)
	_message = "Sold for %d gold" % total
	_message_ok = total > 0
	_refresh()
