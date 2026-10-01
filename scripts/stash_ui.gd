class_name StashUI
extends CanvasLayer
## Shared storage. Tap an item to select it, then move it between your bag and the stash.
## The stash belongs to the account, so every character you make will see the same items.

var player: Player

var _root: Control
var _bag_grid: GridContainer
var _stash_grid: GridContainer
var _bag_label: Label
var _stash_label: Label
var _detail: RichTextLabel
var _move_btn: Button
var _selected: ItemInstance = null


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


func open() -> void:
	if player.dead:
		return
	_selected = null
	_root.visible = true
	get_tree().paused = true
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


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
	outer.add_child(header)
	var title := Label.new()
	title.text = "Shared Stash"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 52)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	var bag_col := _column("Your bag")
	body.add_child(bag_col[0])
	_bag_label = bag_col[1]
	_bag_grid = bag_col[2]

	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(290, 0)
	mid.add_theme_constant_override("separation", 10)
	body.add_child(mid)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.add_theme_font_size_override("normal_font_size", 19)
	_detail.add_theme_font_size_override("bold_font_size", 21)
	mid.add_child(_detail)
	_move_btn = Button.new()
	_move_btn.custom_minimum_size = Vector2(0, 64)
	_move_btn.add_theme_font_size_override("font_size", 20)
	_move_btn.pressed.connect(_move)
	mid.add_child(_move_btn)

	var st_col := _column("Stash")
	body.add_child(st_col[0])
	_stash_label = st_col[1]
	_stash_grid = st_col[2]


## Returns [container, title label, grid].
func _column(title: String) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = title
	col.add_child(lbl)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	sc.add_child(grid)
	return [col, lbl, grid]


func _refresh() -> void:
	if _root == null or not _root.visible:
		return
	_bag_label.text = "Your bag   %d / %d" % [player.inventory.size(), Player.BAG_SIZE]
	_stash_label.text = "Stash   %d / %d" % [GameState.stash.size(), GameState.STASH_SIZE]
	if _selected != null and not player.inventory.has(_selected) and not GameState.stash.has(_selected):
		_selected = null
	_fill(_bag_grid, player.inventory)
	_fill(_stash_grid, GameState.stash)
	if _selected == null:
		_detail.text = "[color=#888888]Tap an item to select it, then move it across.[/color]"
		_move_btn.visible = false
		return
	var col: String = ItemInstance.RARITY_COLORS[_selected.rarity].to_html(false)
	var t := "[b][color=#%s]%s[/color][/b]\n" % [col, _selected.display_name]
	t += "[color=#888888]%s | ilvl %d | %s[/color]\n" % [
		ItemInstance.Rarity.keys()[_selected.rarity].capitalize(), _selected.ilvl, _selected.base.slot.capitalize()]
	if _selected.base.implicit_stat != "":
		t += "[color=#bbbbbb]+%d %s[/color]\n" % [int(_selected.base.implicit_value), _selected.base.implicit_stat.replace("_", " ")]
	for a in _selected.affixes:
		t += "[color=#8fb0ff]%s[/color]\n" % a.text
	_detail.text = t
	_move_btn.visible = true
	var in_bag := player.inventory.has(_selected)
	_move_btn.text = "Store in stash  >>" if in_bag else "<<  Take into bag"
	_move_btn.disabled = (GameState.stash.size() >= GameState.STASH_SIZE) if in_bag else (player.inventory.size() >= Player.BAG_SIZE)


func _fill(grid: GridContainer, items: Array) -> void:
	for c in grid.get_children():
		c.queue_free()
	for it in items:
		var b := Button.new()
		b.text = it.display_name
		b.custom_minimum_size = Vector2(96, 60)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 12)
		var col: Color = ItemInstance.RARITY_COLORS[it.rarity]
		var sb := StyleBoxFlat.new()
		sb.bg_color = it.base.color.darkened(0.65)
		sb.border_color = Color.WHITE if it == _selected else col
		sb.set_border_width_all(4 if it == _selected else 2)
		sb.set_corner_radius_all(6)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, sb)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(fc, col)
		b.pressed.connect(_select.bind(it))
		grid.add_child(b)


func _select(it: ItemInstance) -> void:
	_selected = it
	_refresh()


func _move() -> void:
	if _selected == null:
		return
	if player.inventory.has(_selected):
		GameState.stash_item(_selected)
	else:
		GameState.take_from_stash(_selected)
	_selected = null
	_refresh()
