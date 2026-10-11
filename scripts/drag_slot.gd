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

var _icon: TextureRect
var _count: Label
var _caption: Label
var _bg := Color(0.09, 0.08, 0.12)
var _border := Color(0.22, 0.20, 0.27)
var _style: StyleBoxFlat
var _icon_tex: Texture2D = null


func _init(slot_size := Vector2(60, 60)) -> void:
	custom_minimum_size = slot_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(6)
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

	_apply_style(_border)


## icon may be null (empty cell). count > 1 shows a stack number. caption is shown only when
## there is no icon (text fallback).
func setup(icon: Texture2D, border: Color, bg: Color = Color(0.09, 0.08, 0.12),
		count := 0, caption := "", tip := "") -> void:
	_icon_tex = icon
	_icon.texture = icon
	_icon.visible = icon != null
	_bg = bg
	_border = border
	_caption.text = caption
	_caption.visible = icon == null and caption != ""
	_count.text = str(count)
	_count.visible = count > 1
	tooltip_text = tip
	_apply_style(border)


func _apply_style(border: Color) -> void:
	_style.bg_color = _bg
	_style.border_color = border
	_style.set_border_width_all(2 if _icon_tex != null else 1)


# ---------- drag and drop ----------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if payload.is_empty() or _icon_tex == null:
		return null
	var preview := Control.new()
	var pic := TextureRect.new()
	pic.texture = _icon_tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(56, 56)
	pic.size = Vector2(56, 56)
	pic.position = Vector2(-28, -28)
	pic.modulate = Color(1, 1, 1, 0.85)
	preview.add_child(pic)
	set_drag_preview(preview)
	modulate = Color(1, 1, 1, 0.45)
	return payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok := data is Dictionary and can_accept.is_valid() and bool(can_accept.call(data))
	_apply_style(Color(0.35, 1.0, 0.45) if ok else Color(1.0, 0.35, 0.35))
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_apply_style(_border)
	if on_drop.is_valid():
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
