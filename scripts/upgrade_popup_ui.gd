class_name UpgradePopupUI
extends CanvasLayer
## Diablo / Path of Exile style "Better in Slot" Upgrade Popup.
## Appears as a sleek, non-intrusive compact card when an item drops or is collected
## that is superior to current gear. Does NOT pause gameplay or block controls.
## Says how to equip it (drag it onto its slot: the only way to equip anything) and
## auto-dismisses smoothly.

signal upgrade_resolved(action: String, item: ItemInstance)

const DISPLAY_DURATION: float = 6.0

var player: Player

var _root: Control
var _window: PanelContainer
var _title_lbl: RichTextLabel
var _delta_lbl: RichTextLabel
var _replaces_lbl: Label
var _timer_bar: ProgressBar

var _hint_lbl: Label
var _btn_dismiss: Button

var _current_item: ItemInstance = null
var _current_pickup: LootPickup = null
var _timer: float = 0.0


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _process(delta: float) -> void:
	if _root != null and _root.visible:
		_timer -= delta
		if _timer_bar != null:
			_timer_bar.value = maxf(0.0, _timer)
		if _timer <= 0.0:
			close()


func is_open() -> bool:
	return _root != null and _root.visible


func prompt_upgrade(item: ItemInstance, ground_pickup: LootPickup = null) -> void:
	if item == null or player == null or player.dead:
		return

	_current_item = item
	_current_pickup = ground_pickup

	_populate_ui(item)
	_timer = DISPLAY_DURATION
	if _timer_bar != null:
		_timer_bar.max_value = DISPLAY_DURATION
		_timer_bar.value = DISPLAY_DURATION

	_root.visible = true
	# NOTE: Intentionally do NOT pause gameplay! Player can keep fighting and moving.


func close() -> void:
	if _current_pickup != null and is_instance_valid(_current_pickup):
		_current_pickup.set_meta("upgrade_dismissed", true)
		var tree := get_tree()
		if tree != null:
			tree.create_timer(4.0, true, false, true).timeout.connect(func():
				if is_instance_valid(_current_pickup):
					_current_pickup.remove_meta("upgrade_dismissed")
			)

	_current_item = null
	_current_pickup = null
	_timer = 0.0
	if _root != null:
		_root.visible = false


# ==============================================================================
# UI CONSTRUCTION
# ==============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.visible = false
	# MOUSE_FILTER_IGNORE ensures touches outside this small card pass right through
	# to virtual joystick, movement, skills, and combat without interference!
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Compact non-intrusive floating card in the upper-right quadrant
	_window = PanelContainer.new()
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.custom_minimum_size = Vector2(370, 142)
	_root.add_child(_window)

	# Anchored to top-right, cleanly beneath the persistent BAG button (Y: 16-72)
	_window.anchor_left = 1.0
	_window.anchor_top = 0.0
	_window.anchor_right = 1.0
	_window.anchor_bottom = 0.0
	_window.offset_left = -388
	_window.offset_right = -16
	_window.offset_top = 82
	_window.offset_bottom = 228

	var win_sb := _make_stylebox(Color(0.07, 0.06, 0.09, 0.94), Color(0.28, 0.85, 0.42), 2, 8)
	win_sb.set_content_margin_all(10)
	_window.add_theme_stylebox_override("panel", win_sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	_window.add_child(outer)

	# 1. HEADER ROW: Upgrade Badge + Item Name + Close Button
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	outer.add_child(header)

	_title_lbl = RichTextLabel.new()
	_title_lbl.bbcode_enabled = true
	_title_lbl.fit_content = true
	_title_lbl.scroll_active = false
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("normal_font_size", 14)
	_title_lbl.add_theme_font_size_override("bold_font_size", 14)
	header.add_child(_title_lbl)

	_btn_dismiss = Button.new()
	_btn_dismiss.text = "✕"
	_btn_dismiss.custom_minimum_size = Vector2(26, 26)
	_btn_dismiss.add_theme_font_size_override("font_size", 13)
	var dis_sb := _make_stylebox(Color(0.18, 0.12, 0.12, 0.8), Color(0.55, 0.25, 0.25), 1, 4)
	_btn_dismiss.add_theme_stylebox_override("normal", dis_sb)
	_btn_dismiss.pressed.connect(close)
	header.add_child(_btn_dismiss)

	# 2. STAT DELTA ROW: Green inline stat improvements
	_delta_lbl = RichTextLabel.new()
	_delta_lbl.bbcode_enabled = true
	_delta_lbl.fit_content = true
	_delta_lbl.scroll_active = false
	_delta_lbl.add_theme_font_size_override("normal_font_size", 13)
	outer.add_child(_delta_lbl)

	# 3. REPLACES ROW: Muted gear name being replaced
	_replaces_lbl = Label.new()
	_replaces_lbl.text = "Replaces: None"
	_replaces_lbl.add_theme_font_size_override("font_size", 11)
	_replaces_lbl.add_theme_color_override("font_color", Color(0.65, 0.60, 0.55))
	outer.add_child(_replaces_lbl)

	# 4. HOW TO EQUIP: equipping is only ever by dragging the item onto its slot
	_hint_lbl = Label.new()
	_hint_lbl.text = "Open your 🎒 Bag and drag it onto its slot to equip it."
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	outer.add_child(_hint_lbl)


	# 5. TIMER PROGRESS BAR: Visual countdown before auto-dismiss
	_timer_bar = ProgressBar.new()
	_timer_bar.custom_minimum_size = Vector2(0, 3)
	_timer_bar.show_percentage = false
	var tb_bg := StyleBoxFlat.new()
	tb_bg.bg_color = Color(0.12, 0.10, 0.15, 0.6)
	var tb_fill := StyleBoxFlat.new()
	tb_fill.bg_color = Color(0.30, 0.85, 0.45, 0.8)
	_timer_bar.add_theme_stylebox_override("background", tb_bg)
	_timer_bar.add_theme_stylebox_override("fill", tb_fill)
	outer.add_child(_timer_bar)


func _populate_ui(item: ItemInstance) -> void:
	var slot: String = item.base.slot
	var slot_name: String = UIKit.SLOT_NAMES.get(slot, slot.capitalize())
	var rar_col: Color = ItemInstance.RARITY_COLORS[item.rarity]
	var hex_col: String = rar_col.to_html(false)

	_title_lbl.text = "[b][color=#35ff8c]▲ UPGRADE:[/color] [color=#%s]%s[/color] [color=#888888](%s)[/color][/b]" % [
		hex_col, item.display_name, slot_name
	]

	_delta_lbl.text = player.get_compact_upgrade_summary(item)

	var old_name := player.get_replaced_gear_name(item)
	_replaces_lbl.text = "Replaces: %s" % old_name



func _make_stylebox(bg: Color, border: Color, width := 1, corner := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	return sb
