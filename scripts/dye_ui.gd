class_name DyeUI
extends CanvasLayer
## The Dyer in Ashfall: dye a helmet or armour (DyeDB). Pick a piece of gear (worn, in your bag, or
## your hireling's), pick a paint, see the character wearing it, and pay (DyeDB.PRICE) to dye it.
## Taking a dye off is free. A dye is only how the piece looks: it stays through crafting.

const CELL := 76.0
const PAINT := 56.0
const PREVIEW := Vector2(250, 300)

var player: Player
var _root: Control
var _gear_box: GridContainer
var _palette: GridContainer
var _preview: Control
var _rig: RigSprite
var _info: RichTextLabel
var _feedback: Label
var _dye_btn: Button
var _clean_btn: Button
var _item: ItemInstance = null
var _where := ""    # "worn" | "bag" | "hireling": whose it is
var _paint := ""    # the dye picked (DyeDB id), "" for none yet


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _root.visible:
		close()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_feedback.visible = false
	_item = null
	_paint = ""
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
	dim.color = Color(0, 0, 0, 0.72)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.window_box(20, Color.WHITE, true))
	margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	UIKit.window_header(v, "🎨 DYER CALLA  —  DYE YOUR ARMOUR", UIKit.GOLD, close, 22)
	_feedback = UIKit.label("", 15, Color(1.0, 0.85, 0.40), true)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.visible = false
	v.add_child(_feedback)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)

	# Left: the gear that can be dyed
	var gear := UIKit.section(cols, "YOUR GEAR", true)
	gear.get_parent().custom_minimum_size = Vector2(4 * (CELL + 6.0) + 28.0, 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gear.add_child(scroll)
	_gear_box = UIKit.grid(4, 6)
	scroll.add_child(_gear_box)

	# Middle: the character wearing it
	var mid := UIKit.section(cols, "PREVIEW", true)
	mid.get_parent().custom_minimum_size = Vector2(PREVIEW.x + 24.0, 0)
	_preview = Control.new()
	_preview.custom_minimum_size = PREVIEW
	_preview.clip_contents = true
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(_preview)
	_info = UIKit.rich("", 14)
	mid.add_child(_info)

	# Right: the paints
	var right := UIKit.section(cols, "PAINTS", true)
	right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette = UIKit.grid(DyeDB.COLUMNS, 6)
	right.add_child(_palette)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	right.add_child(row)
	_dye_btn = UIKit.button("🎨 Dye", Color(0.20, 0.15, 0.08), Color(0.95, 0.80, 0.40), Vector2(0, 54), 19)
	_dye_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dye_btn.pressed.connect(_apply)
	row.add_child(_dye_btn)
	_clean_btn = UIKit.button("Remove dye", Color(0.14, 0.11, 0.10), Color(0.70, 0.55, 0.35), Vector2(190, 54), 16)
	_clean_btn.pressed.connect(_remove)
	row.add_child(_clean_btn)
	right.add_child(UIKit.label("Tap a piece of gear, then a paint. A dye only changes how the piece looks and stays through crafting. Taking one off is free.",
		12, UIKit.TEXT_DIM, true))


## Gear that can be dyed: worn, then in the bag, then your hireling's. [{item, where, name}]
func _dyeable() -> Array:
	var out: Array = []
	for slot in DyeDB.SLOTS:
		var it: ItemInstance = player.equipment.get(slot)
		if it != null:
			out.append({"item": it, "where": "worn"})
	for it in player.inventory:
		if it.can_dye():
			out.append({"item": it, "where": "bag"})
	# A hireling dressed in its own gear shows it (a Scout, drawn from a character pack, wears none)
	if Hirelings.has() and String(GameState.hireling.get("skin", "")) == "":
		for slot in DyeDB.SLOTS:
			var it: ItemInstance = GameState.hireling_gear.get(slot)
			if it != null:
				out.append({"item": it, "where": "hireling"})
	return out


func _say(msg: String) -> void:
	_feedback.text = msg
	_feedback.visible = true


func _refresh() -> void:
	var entries := _dyeable()
	if _item != null and not entries.any(func(e): return e.item == _item):
		_item = null
	if _item == null and not entries.is_empty():
		_item = entries[0].item
		_where = entries[0].where
		_paint = ""
	elif _item != null:
		for e in entries:
			if e.item == _item:
				_where = e.where

	UIKit.clear(_gear_box)
	if entries.is_empty():
		_gear_box.add_child(UIKit.label("You have no helmets or armour to dye.", 14, UIKit.TEXT_DIM, true))
	for e in entries:
		_gear_box.add_child(_gear_cell(e.item, e.where))

	UIKit.clear(_palette)
	for d in DyeDB.PALETTE:
		_palette.add_child(_paint_cell(String(d[0])))

	_update_preview()
	_update_buttons()


func _gear_cell(it: ItemInstance, where: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	var cell := UIKit.item_cell(it, it == _item, Vector2(CELL, CELL))
	if it == _item and _paint != "":
		cell.set_dye(_paint, it.base.icon)  # what it would look like
	cell.tooltip_text = "%s%s" % [it.display_name, ("\nDyed " + DyeDB.dye_name(it.dye)) if DyeDB.dyed(it) else ""]
	cell.clicked.connect(func():
		_item = it
		_where = where
		_paint = ""
		_refresh())
	col.add_child(cell)
	var cap := UIKit.label({"worn": "worn", "bag": "in bag", "hireling": String(GameState.hireling.get("name", "hireling"))}[where], 11, UIKit.TEXT_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return col


func _paint_cell(id: String) -> DragSlot:
	var cell := DragSlot.new(Vector2(PAINT, PAINT))
	var col := DyeDB.color(id)
	cell.setup(DyeDB.icon(id), Color.WHITE if id == _paint else col.darkened(0.3), col.darkened(0.85), 0, "", DyeDB.dye_name(id))
	if _item != null and _item.dye == id:
		cell.modulate = Color(1, 1, 1, 0.55)  # already on it
	cell.clicked.connect(func():
		_paint = id
		_refresh())
	return cell


func _update_buttons() -> void:
	var can := _item != null
	var picked := can and _paint != "" and _paint != _item.dye
	_dye_btn.disabled = not picked or not GameState.can_afford(DyeDB.PRICE)
	_dye_btn.text = "🎨 Dye" if _paint == "" else "🎨 Dye %s" % DyeDB.dye_name(_paint)
	_clean_btn.disabled = not (can and DyeDB.dyed(_item))
	var line := ""
	if _item != null:
		line = "[b]%s[/b]\n" % _item.display_name
		line += ("[color=#%s]Dyed %s[/color]\n" % [DyeDB.color(_item.dye).lightened(0.25).to_html(false), DyeDB.dye_name(_item.dye)]) if DyeDB.dyed(_item) \
			else "[color=#8a7f6e]Its own colours[/color]\n"
	if _paint != "":
		line += "[color=#bdb6aa]Dye:[/color] [color=#%s]%s[/color]\n" % [DyeDB.color(_paint).lightened(0.25).to_html(false), DyeDB.dye_name(_paint)]
	line += "[color=#9a8f7e]Costs[/color] " + Currency.price_text(DyeDB.PRICE)
	_info.text = line


## The character wearing the picked gear in the picked dye (before you pay).
func _update_preview() -> void:
	if _rig != null:
		_rig.queue_free()
		_rig = null
	if _item == null:
		return
	_rig = RigSprite.new()
	_rig.base_scale = 0.42
	_rig.weapon_from_gear = true
	_preview.add_child(_rig)
	_rig.position = Vector2(PREVIEW.x * 0.5, PREVIEW.y - 22.0)
	var gear: Dictionary
	if _where == "hireling":
		gear = GameState.hireling_gear
		Appearance.apply(_rig, GameState.hireling.get("look", Appearance.default_look()))
	else:
		gear = player.equipment
		Appearance.apply(_rig, GameState.appearance)
	Player.dress_rig(_rig, gear)
	# The picked piece on it (it may be in the bag), in the dye picked or the one it has
	var dye := _paint if _paint != "" else _item.dye
	_rig.set_gear(_item.base.slot, _item.base.id, dye)
	_rig.play_loop("Idle")


func _apply() -> void:
	if _item == null or _paint == "" or not GameState.pay(DyeDB.PRICE):
		return
	_set_dye(_paint)
	_say("%s is dyed %s." % [_item.display_name, DyeDB.dye_name(_paint)])
	_paint = ""
	_refresh()


func _remove() -> void:
	if _item == null or not DyeDB.dyed(_item):
		return
	_set_dye("")
	_say("The dye comes off %s." % _item.display_name)
	_refresh()


## Sets the dye and has everything that shows the piece redrawn.
func _set_dye(id: String) -> void:
	var it := _item
	match _where:
		"worn":
			player.modify_item(it, func(): it.dye = id)  # redresses the character
		"hireling":
			it.dye = id
			if is_instance_valid(Hirelings.node):
				Hirelings.node.refresh()
			GameState.save_soon()
		_:
			it.dye = id
			player.inventory_changed.emit()
