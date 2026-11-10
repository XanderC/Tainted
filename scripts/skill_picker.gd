class_name SkillPicker
extends CanvasLayer
## The dropdown that opens over a skill hotkey when you tap it in town (the skill buttons are greyed out there, so
## the tap is free for this). It lists the skills you can put on that hotkey: the skill gems in your pouch and the
## ones already on other hotkeys. Tap one to put it there. A skill that is on another hotkey MOVES: it comes off
## that one and goes on this one (GameState.move_skill_to_slot), and the gem that was here goes back to the pouch.
## Skills you don't have the level or attributes for show greyed out with what they need. Tap anywhere else (or
## Escape) to close it. The Jeweler's Skills tab still works as it did; this is the quick way in town.

const W := 340.0  ## the dropdown's width
const ROW_H := 52.0
const MAX_LIST_H := 340.0  ## the list scrolls past this
const GAP := 10.0  ## between the dropdown and the hotkey it belongs to

var _root: Control
var _panel: PanelContainer
var _slot := -1


func _ready() -> void:
	layer = 20  # over the HUD, under the inventory (25) and the passive tree (28)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # a tap anywhere outside the dropdown closes it
	_root.visible = false
	_root.gui_input.connect(_on_backdrop_input)
	add_child(_root)


func is_open() -> bool:
	return _root != null and _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		close()


func close() -> void:
	if _root != null:
		_root.visible = false
	_slot = -1


## Opens the dropdown for hotkey `slot` above `anchor` (the hotkey's rectangle on screen).
func open(slot: int, anchor: Rect2) -> void:
	_slot = slot
	if _panel != null:
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _frame())
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.custom_minimum_size.x = W
	_panel.add_child(body)
	_fill(body)
	_root.visible = true
	_panel.reset_size()
	_panel.size = _panel.get_combined_minimum_size()
	# Above the hotkey (they sit at the bottom right), kept on the screen
	var screen := get_viewport().get_visible_rect().size
	var x := clampf(anchor.get_center().x - _panel.size.x * 0.5, 8.0, maxf(screen.x - _panel.size.x - 8.0, 8.0))
	var y := clampf(anchor.position.y - _panel.size.y - GAP, 8.0, maxf(screen.y - _panel.size.y - 8.0, 8.0))
	_panel.position = Vector2(x, y)


func _frame() -> StyleBoxFlat:
	var sb := UIKit.box(Color(0.07, 0.06, 0.09, 0.97), Color(0.60, 0.50, 0.30), 2, 8)
	sb.set_content_margin_all(10)
	return sb


func _fill(body: VBoxContainer) -> void:
	var here := GameState.slot_skill(_slot)
	body.add_child(UIKit.label("MAIN ATTACK" if _slot == 0 else "SKILL %d" % _slot, 16, UIKit.GOLD))

	if here != "":
		var sk := SkillTree.get_skill(here)
		var cur := UIKit.label("Now: %s" % (sk.display_name if sk != null else here), 13, UIKit.TEXT_DIM)
		body.add_child(cur)
		var out := UIKit.button("✖ Take it off this hotkey", Color(0.20, 0.10, 0.10), Color(0.90, 0.45, 0.40), Vector2(0, 40), 14)
		out.pressed.connect(func():
			GameState.clear_slot_skill(_slot)
			close())
		body.add_child(out)

	var rows: Array = []
	for sk in SkillTree.active_skills():
		var other := GameState.slot_of(sk.id)
		if sk.id == here or (other < 0 and not GameState.is_skill_unlocked(sk.id)):
			continue  # (the one already here, and skills you have not unlocked)
		rows.append(sk)
	if rows.is_empty():
		body.add_child(UIKit.label("You have no other skills. Cut a Skill Gem into one in the Skills window (the 💠 button).", 13, UIKit.TEXT_DIM, true))
		return

	body.add_child(UIKit.label("Tap a skill to put it here", 12, UIKit.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(W, minf(rows.size() * (ROW_H + 4.0), MAX_LIST_H))
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for sk in rows:
		list.add_child(_row(sk))


## One skill: its gem icon, name and level, and a dim second line (where it is now, or why it can't go here).
func _row(sk: SkillDef) -> Button:
	var id: String = sk.id
	var other := GameState.slot_of(id)
	var why := GameState.skill_gem_block_reason(id)
	var note := ""
	if why != "":
		note = why
	elif other >= 0:
		note = "Moves here from %s" % ("the main attack" if other == 0 else "skill %d" % other)

	var b := Button.new()
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	for st in ["normal", "hover", "pressed", "disabled"]:
		var bg := Color(0.18, 0.16, 0.24) if st == "hover" else Color(0.10, 0.09, 0.13)
		b.add_theme_stylebox_override(st, UIKit.box(bg, Color(0.32, 0.30, 0.40), 1, 5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	var ic := TextureRect.new()
	ic.texture = IconFactory.gem_icon("skill:" + id, sk.color, 3)
	ic.custom_minimum_size = Vector2(ROW_H - 10.0, ROW_H - 10.0)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var main := UIKit.label("%s   Lv %d" % [sk.display_name, GameState.gem_level(id)], 14,
		Color(0.92, 0.90, 0.84) if why == "" else Color(0.55, 0.53, 0.50))
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(main)
	if note != "":
		var sub := UIKit.label(note, 11, Color(0.95, 0.55, 0.45) if why != "" else UIKit.TEXT_DIM)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(sub)

	b.pressed.connect(func():
		GameState.move_skill_to_slot(_slot, id)
		close())
	return b
