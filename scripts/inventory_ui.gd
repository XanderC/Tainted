class_name InventoryUI
extends CanvasLayer
## Full-screen inventory: equipment slots, bag grid, item details with a stat comparison.
## Pauses the game while open. Toggle with the Bag button (top right) or the I key.

const STAT_LABELS := {
	"max_life": "Life",
	"damage": "Damage",
	"attack_speed": "Attack speed",
	"armor": "Armor",
	"crit_chance": "Crit chance",
	"move_speed": "Move speed",
}
const STYLE_STATES := ["normal", "hover", "pressed", "focus", "disabled"]
const FONT_STATES := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]

var player: Player

var _root: Control
var _open_btn: Button
var _bag_label: Label
var _bag_buttons: Array[Button] = []
var _slot_buttons := {}
var _detail: RichTextLabel
var _btn_primary: Button
var _btn_drop: Button
var _selected: ItemInstance = null
var _selected_slot := ""  # "" = selected from the bag, otherwise the equipment slot name


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep working while the game is paused
	_build_ui()
	player.inventory_changed.connect(_refresh)
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


# ---------- layout ----------

func _build_ui() -> void:
	_open_btn = Button.new()
	_open_btn.text = "Bag"
	_open_btn.custom_minimum_size = Vector2(110, 70)
	_open_btn.add_theme_font_size_override("font_size", 24)
	_open_btn.pressed.connect(open)
	add_child(_open_btn)
	_open_btn.anchor_left = 1.0
	_open_btn.anchor_right = 1.0
	_open_btn.offset_left = -126.0
	_open_btn.offset_right = -16.0
	_open_btn.offset_top = 16.0
	_open_btn.offset_bottom = 86.0

	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.11, 0.97)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", bg)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	# header
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "Inventory  -  %s" % (player.class_def.display_name if player.class_def else "Hero")
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 56)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# left: equipment
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	var eq_title := Label.new()
	eq_title.text = "Equipment"
	left.add_child(eq_title)
	for slot in Player.SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 70)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on_equip_slot_pressed.bind(slot))
		left.add_child(b)
		_slot_buttons[slot] = b

	# middle: bag
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	body.add_child(mid)
	_bag_label = Label.new()
	mid.add_child(_bag_label)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	mid.add_child(grid)
	for i in Player.BAG_SIZE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(84, 84)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_bag_pressed.bind(i))
		grid.add_child(b)
		_bag_buttons.append(b)

	# right: details + actions
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 20)
	_detail.add_theme_font_size_override("bold_font_size", 22)
	scroll.add_child(_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	right.add_child(row)
	_btn_primary = _action_button("Equip", _on_primary)
	_btn_drop = _action_button("Drop", _on_drop)
	row.add_child(_btn_primary)
	row.add_child(_btn_drop)


func _action_button(label: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(150, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(callback)
	return b


# ---------- refresh ----------

func _refresh() -> void:
	if _root == null:
		return
	_bag_label.text = "Bag   %d / %d" % [player.inventory.size(), Player.BAG_SIZE]

	for i in Player.BAG_SIZE:
		var b := _bag_buttons[i]
		var item: ItemInstance = player.inventory[i] if i < player.inventory.size() else null
		var sel := item != null and item == _selected and _selected_slot == ""
		_style_button(b, item, sel)
		b.icon = null
		b.text = ""
		if item != null:
			if item.base.icon != null:
				b.icon = item.base.icon
			else:
				b.text = item.base.display_name

	for slot in Player.SLOTS:
		var b: Button = _slot_buttons[slot]
		var it = player.equipment.get(slot)
		var sel: bool = it != null and it == _selected and _selected_slot == slot
		_style_button(b, it, sel)
		b.text = "%s\n%s" % [String(slot).capitalize(), it.display_name if it != null else "- empty -"]

	_refresh_detail()


func _style_button(b: Button, item, selected: bool) -> void:
	var bg := Color(0.12, 0.12, 0.15)
	var border := Color(0.28, 0.28, 0.33)
	var fg := Color(0.55, 0.55, 0.6)
	if item != null:
		border = ItemInstance.RARITY_COLORS[item.rarity]
		bg = item.base.color.darkened(0.6)
		fg = border
	if selected:
		border = Color.WHITE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(4 if selected else 2)
	sb.set_corner_radius_all(6)
	for state in STYLE_STATES:
		b.add_theme_stylebox_override(state, sb)
	for state in FONT_STATES:
		b.add_theme_color_override(state, fg)


func _refresh_detail() -> void:
	_btn_primary.visible = _selected != null
	_btn_drop.visible = _selected != null and _selected_slot == ""
	if _selected == null:
		_detail.text = "[color=#888888]Tap an item to inspect it.\n\nEquip swaps it with what you are wearing. The old item goes back into the same bag slot.[/color]"
		return

	var t := _item_bbcode(_selected)
	if _selected_slot == "":
		_btn_primary.text = "Equip"
		_btn_primary.disabled = false
		t += "\n[b]If you equip this:[/b]\n" + _delta_bbcode(_selected)
		var cur = player.equipment.get(_selected.base.slot)
		if cur != null:
			t += "\n[color=#888888]Currently equipped:[/color]\n" + _item_bbcode(cur)
	else:
		_btn_primary.text = "Unequip"
		_btn_primary.disabled = player.inventory.size() >= Player.BAG_SIZE
		if _btn_primary.disabled:
			t += "\n[color=#ee5555]Bag is full. Drop something first.[/color]"
	_detail.text = t


func _item_bbcode(item: ItemInstance) -> String:
	var col: String = ItemInstance.RARITY_COLORS[item.rarity].to_html(false)
	var t := "[b][color=#%s]%s[/color][/b]\n" % [col, item.display_name]
	t += "[color=#888888]%s | ilvl %d | %s[/color]\n" % [
		ItemInstance.Rarity.keys()[item.rarity].capitalize(), item.ilvl, item.base.slot.capitalize()]
	if item.base.implicit_stat != "":
		t += "[color=#bbbbbb]+%d %s[/color]\n" % [int(item.base.implicit_value), item.base.implicit_stat.replace("_", " ")]
	for a in item.affixes:
		t += "[color=#8fb0ff]%s[/color]\n" % a.text
	return t


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
				txt = "%+.2f" % d
			_:
				var whole := int(round(d))
				if whole == 0:
					continue
				txt = "%+d" % whole
		var col := "66dd66" if d > 0.0 else "ee5555"
		t += "[color=#%s]%s %s[/color]\n" % [col, txt, STAT_LABELS[k]]
	if t == "":
		t = "[color=#888888]No change to core stats[/color]\n"
	return t


# ---------- input handlers ----------

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
