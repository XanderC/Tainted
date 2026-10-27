class_name DragSlot
extends PanelContainer
## One square cell of an inventory-style grid. Uses Godot's built-in drag and drop, so it works
## the same with mouse and touch. A slot is configured with:
##   payload    - what gets dragged out of it (empty = nothing to drag, e.g. an empty cell)
##   can_accept - Callable(data: Dictionary) -> bool, whether a dragged payload may land here
##   on_drop    - Callable(data: Dictionary), performs the move
## Payload dictionaries are plain data such as {"kind": "item", "from": "bag", "idx": 3}.

signal clicked

var payload: Dictionary = {}
var can_accept: Callable = Callable()
var on_drop: Callable = Callable()
## For cells that care where in them a drop lands (an item spanning several grid cells):
## Callable(data, at_position: Vector2), used instead of can_accept / on_drop when set.
var can_accept_at: Callable = Callable()
var on_drop_at: Callable = Callable()
## A grid item: the size of one grid cell. Dragging it then shows it full size, held at the point
## it was picked up, and adds "grab" (the cell within the item that was grabbed) to the payload,
## so it can be dropped with that same cell under the finger.
var grid_cell := 0.0

var _icon: TextureRect
var _count: Label
var _caption: Label
var _bg := Color(0.09, 0.08, 0.12)
var _border := Color(0.22, 0.20, 0.27)
var _style: StyleBoxTexture
var _rim_style: StyleBoxFlat
var _rim: Panel  # the coloured outline over the icon: rarity, selection, drop feedback
var _icon_tex: Texture2D = null
var _dye := ""
var _dye_tex: Texture2D = null
var _sockets: Control  # the item's sockets drawn along the bottom of its icon (set_sockets)
var _socket_gems: Array = []
var _socket_count := 0


func _init(slot_size := Vector2(60, 60)) -> void:
	custom_minimum_size = slot_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style = StyleBoxTexture.new()
	_style.texture = UIKit.mmo("slot")
	_style.set_texture_margin_all(8.0)
	_style.set_content_margin_all(3)
	add_theme_stylebox_override("panel", _style)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 10)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	add_child(_caption)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 13)
	_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_count.add_theme_constant_override("outline_size", 4)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.visible = false
	add_child(_count)

	_rim_style = StyleBoxFlat.new()
	_rim_style.draw_center = false
	_rim_style.set_corner_radius_all(3)
	_rim = Panel.new()
	_rim.add_theme_stylebox_override("panel", _rim_style)
	_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rim)

	_apply_style(_border)


## Keeps the icon (and the rim round it) clear of the slot's own border: for painted square art, such
## as a skill gem's, that would otherwise fill the whole cell and hide the border.
func inset_icon() -> void:
	var m := clampf(minf(custom_minimum_size.x, custom_minimum_size.y) * 0.12, 3.0, 8.0)
	_style.set_content_margin_all(m)


## An empty slot's picture of what goes in it (an equipment slot's silhouette): shown faintly in
## place of its caption, and not an item (nothing to drag). Call after setup().
func set_placeholder(tex: Texture2D) -> void:
	if tex == null or _icon_tex != null:
		return
	_icon.texture = tex
	_icon.visible = true
	_icon.modulate = Color(1, 1, 1, 0.8)
	_caption.visible = false


## Shows an item's sockets over the middle of its icon, a column of them down a tall one: each gem or rune in its socket, then the
## empty ones as dark rings. `gems` are gem ids (GemDef), `total` how many sockets it has.
func set_sockets(gems: Array, total: int) -> void:
	_socket_gems = gems
	_socket_count = total
	if _sockets == null:
		_sockets = Control.new()
		_sockets.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sockets.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sockets.resized.connect(_layout_sockets)
		add_child(_sockets)
	_layout_sockets()


func _layout_sockets() -> void:
	for c in _sockets.get_children():
		c.queue_free()
	var n := _socket_count
	var w := _sockets.size.x
	if n <= 0 or w <= 0.0:
		return
	# Over the middle of the whole icon, as Diablo III does: down it for a tall item, across for a wide one
	var h := _sockets.size.y
	var column := h >= w * 0.9
	var gap := 3.0
	var d: float
	if column:
		d = clampf(minf(w * 0.55, (h - 8.0 - gap * (n - 1)) / n), 10.0, 34.0)  # one socket's diameter
	else:
		d = clampf(minf(h * 0.55, (w - 8.0 - gap * (n - 1)) / n), 10.0, 34.0)
	var x := (w - d) * 0.5 if column else (w - (d * n + gap * (n - 1))) * 0.5
	var y := (h - (d * n + gap * (n - 1))) * 0.5 if column else (h - d) * 0.5
	for i in n:
		var has := i < _socket_gems.size()
		var id := String(_socket_gems[i]) if has else ""
		var col := Color(GemDef.info(id).get("color", Color.WHITE)).darkened(0.1) if has else Color(0.50, 0.50, 0.58, 0.8)
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.position = Vector2(x, y)
		ring.size = Vector2(d, d)
		ring.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.03, 0.05, 0.85), col, 1, int(d)))
		_sockets.add_child(ring)
		if has:
			var pic := TextureRect.new()
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pic.texture = GemDef.icon(id)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.position = Vector2(d * 0.1, d * 0.1)
			pic.size = Vector2(d * 0.8, d * 0.8)
			ring.add_child(pic)
		if column:
			y += d + gap
		else:
			x += d + gap


## Draw the icon in a dye (DyeDB id): the item's art recoloured, as it looks worn.
func set_dye(dye: String, tex: Texture2D) -> void:
	_icon.material = DyeDB.material(dye, tex)
	_dye = dye
	_dye_tex = tex


## icon may be null (empty cell). count > 1 shows a stack number. caption is shown only when
## there is no icon (text fallback).
func setup(icon: Texture2D, border: Color, bg: Color = Color(0.09, 0.08, 0.12),
		count := 0, caption := "", tip := "") -> void:
	_icon_tex = icon
	_icon.texture = icon
	_icon.visible = icon != null
	_icon.modulate = Color.WHITE
	_bg = bg
	_border = border
	_caption.text = caption
	_caption.visible = icon == null and caption != ""
	_count.text = str(count)
	_count.visible = count > 1
	tooltip_text = tip
	_apply_style(border)


func _apply_style(border: Color) -> void:
	# The slot art is the cell: no outline at rest. Holding something, it is tinted towards its
	# colour (an item's rarity); the outline only marks the picked one (white) and, while
	# something is dragged over it, whether it can land (green / red).
	var picked := _border == Color.WHITE
	_style.modulate_color = Color.WHITE.lerp(_border.lightened(0.25), 0.65) if _icon_tex != null and not picked else Color.WHITE
	_rim.visible = picked or border != _border
	_rim_style.border_color = border
	_rim_style.set_border_width_all(2)


# ---------- drag and drop ----------

func _get_drag_data(at_position: Vector2) -> Variant:
	if payload.is_empty() or _icon_tex == null:
		return null
	var preview := Control.new()
	var pic := TextureRect.new()
	pic.texture = _icon_tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var data := payload
	if grid_cell > 0.0:
		# Full size, offset so the point picked up stays under the finger
		pic.custom_minimum_size = size
		pic.size = size
		pic.position = -at_position
		data = payload.duplicate()
		data["grab"] = Vector2i(int(at_position.x / grid_cell), int(at_position.y / grid_cell))
	else:
		pic.custom_minimum_size = Vector2(56, 56)
		pic.size = Vector2(56, 56)
		pic.position = Vector2(-28, -28)
	pic.modulate = Color(1, 1, 1, 0.85)
	if _dye != "":
		pic.material = DyeDB.material(_dye, _dye_tex)
	preview.add_child(pic)
	set_drag_preview(preview)
	modulate = Color(1, 1, 1, 0.45)
	return data


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var ok := false
	if data is Dictionary:
		if can_accept_at.is_valid():
			ok = bool(can_accept_at.call(data, at_position))
		elif can_accept.is_valid():
			ok = bool(can_accept.call(data))
	_apply_style(Color(0.35, 1.0, 0.45) if ok else Color(1.0, 0.35, 0.35))
	return ok


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_apply_style(_border)
	if on_drop_at.is_valid():
		on_drop_at.call(data, at_position)
	elif on_drop.is_valid():
		on_drop.call(data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate = Color.WHITE
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		if _style != null:
			_apply_style(_border)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		clicked.emit()
