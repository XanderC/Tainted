class_name OptionsUI
extends CanvasLayer
## The Options window, opened by the OPTIONS button the GameMenu puts under BAG. It sits to one side
## so the world stays in view while you change something, and the game is paused while it is open.
## How far the camera is zoomed out (GameCamera), which changes the view as the slider moves, and which
## pet the character has (PetDB). The zoom is kept on the device (Options), the pet with the character.

var _slider: HSlider
var _value: Label
var _less: Button
var _more: Button
var _pet: Label
var _was_paused := false


## Opens the window on `parent` (the scene's GameMenu).
static func open(parent: Node) -> OptionsUI:
	var ui := OptionsUI.new()
	parent.add_child(ui)
	return ui


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_build()
	_sync()


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = _was_paused


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	GameCamera.save()
	queue_free()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the world beside the window stays in view
	add_child(root)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.window_box(20, Color.WHITE, true))
	panel.custom_minimum_size = Vector2(440, 0)
	root.add_child(panel)
	# To the right of the middle: the left of the screen shows what the zoom does
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -456.0
	panel.offset_right = -16.0

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	UIKit.window_header(box, "⚙ Options", UIKit.GOLD, _close)

	box.add_child(UIKit.label("View distance", 20, UIKit.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_less = UIKit.stone_button("−", Vector2(56, 56), 28)
	_less.pressed.connect(func(): _nudge(-GameCamera.STEP))
	row.add_child(_less)
	_slider = HSlider.new()
	_slider.min_value = GameCamera.MIN_ZOOM
	_slider.max_value = GameCamera.MAX_ZOOM
	_slider.step = GameCamera.STEP
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(0, 44)
	_style_slider(_slider)
	_slider.value_changed.connect(func(v: float): GameCamera.apply_zoom(v); _sync(false))
	_slider.drag_ended.connect(func(_changed: bool): GameCamera.save())
	row.add_child(_slider)
	_more = UIKit.stone_button("+", Vector2(56, 56), 28)
	_more.pressed.connect(func(): _nudge(GameCamera.STEP))
	row.add_child(_more)

	var ends := HBoxContainer.new()
	box.add_child(ends)
	var far := UIKit.label("Far: see more", 14, UIKit.TEXT_DIM)
	far.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(far)
	var near := UIKit.label("Close: bigger", 14, UIKit.TEXT_DIM)
	near.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ends.add_child(near)

	_value = UIKit.label("", 17, Color(1.0, 0.85, 0.40))
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_value)
	box.add_child(UIKit.label("Name plates and labels already on screen catch up in the next area.", 13, UIKit.TEXT_DIM, true))

	# This character's pet: it trots beside you and fetches the currency you leave lying (it can't fight)
	box.add_child(UIKit.label("Pet", 20, UIKit.GOLD))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	box.add_child(prow)
	var prev := UIKit.stone_button("◀", Vector2(56, 48), 20)
	prev.pressed.connect(func(): _pick_pet(-1))
	prow.add_child(prev)
	_pet = UIKit.label("", 19, Color(1.0, 0.85, 0.40))
	_pet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_pet)
	var next := UIKit.stone_button("▶", Vector2(56, 48), 20)
	next.pressed.connect(func(): _pick_pet(1))
	prow.add_child(next)
	box.add_child(UIKit.label("A pet follows you and picks up the currency lying about. It doesn't fight.", 13, UIKit.TEXT_DIM, true))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var reset := UIKit.button("Reset", Color(0.16, 0.12, 0.08), Color(0.7, 0.6, 0.45), Vector2(0, 46), 16)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		GameCamera.set_zoom(GameCamera.DEFAULT_ZOOM)
		_sync())
	buttons.add_child(reset)
	var done := UIKit.button("Done", Color(0.16, 0.12, 0.08), Color(0.95, 0.80, 0.30), Vector2(0, 46), 16)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(_close)
	buttons.add_child(done)


func _pick_pet(by: int) -> void:
	GameState.set_pet(PetDB.step(GameState.pet, by))
	_sync()


func _nudge(by: float) -> void:
	GameCamera.set_zoom(GameCamera.zoom() + by)
	_sync()


## Shows the zoom in use: the slider (`move`: unless it is what moved), the text and the step buttons.
func _sync(move := true) -> void:
	var z := GameCamera.zoom()
	if move:
		_slider.set_value_no_signal(z)
	_value.text = "Zoom %d%%%s" % [int(round(z * 100.0)), "   (default)" if is_equal_approx(z, GameCamera.DEFAULT_ZOOM) else ""]
	_less.disabled = z <= GameCamera.MIN_ZOOM + 0.001
	_more.disabled = z >= GameCamera.MAX_ZOOM - 0.001
	_pet.text = PetDB.name_of(GameState.pet)


## A thin gold track and a round knob a thumb can hold (the engine's slider is a hair line).
static func _style_slider(s: HSlider) -> void:
	var track := UIKit.box(Color(0.10, 0.08, 0.06), Color(0.45, 0.38, 0.25), 1, 4)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	var fill := UIKit.box(Color(0.80, 0.62, 0.22), Color(0.95, 0.80, 0.40), 1, 4)
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob()
	for k in ["grabber", "grabber_highlight", "grabber_disabled"]:
		s.add_theme_icon_override(k, knob)


static func _knob() -> ImageTexture:
	var n := 34
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5 - Vector2(0.5, 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			if d <= 16.0:
				img.set_pixel(x, y, Color(0.45, 0.30, 0.08) if d > 13.0 else Color(0.97, 0.84, 0.45).lerp(Color(0.85, 0.65, 0.22), d / 13.0))
	return ImageTexture.create_from_image(img)
