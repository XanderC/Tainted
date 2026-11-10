class_name StashTabsDialog
extends Control
## The window that edits the stash's tabs (GameState.stash_tabs), opened from the ✎ button at the end of the stash's
## tab row: rename a tab, choose what it is (Items for any gear, Uniques for Legendary and Set gear, Currency, Gems,
## Runes), move it up or down, delete it (its gear goes to the other tabs), add a new one. The main stash is
## always the first Items tab: it can be renamed, not moved, retyped or deleted. What cannot be done says why.

var menu: GameMenu
var _list: VBoxContainer
var _note: Label


## Opens the dialog over `menu` (the game menu).
static func open(menu_: GameMenu) -> StashTabsDialog:
	var d := StashTabsDialog.new()
	d.name = "StashTabsDialog"
	d.menu = menu_
	menu_.add_child(d)
	return d


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close()
	)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	var sb := UIKit.inset_box(12, Color(1.0, 0.85, 0.85))
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UIKit.label("STASH TABS", 20, Color(1.0, 0.88, 0.45)))
	box.add_child(UIKit.label("Shared by all your characters. A Uniques tab takes Legendary and Set gear only; there is one Currency, one Gems and one Runes tab at most.",
		12, UIKit.TEXT_DIM, true))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)
	_note = UIKit.label("", 13, Color(0.95, 0.55, 0.45), true)
	box.add_child(_note)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	box.add_child(foot)
	var add := UIKit.button("＋ Add a tab", Color(0.12, 0.35, 0.18), Color(0.35, 1.0, 0.50), Vector2(0, 44), 15)
	add.name = "AddTab"
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(func():
		var why := GameState.add_stash_tab("Tab %d" % (GameState.stash_tabs.size() + 1), "items")
		_changed(why))
	foot.add_child(add)
	var done := UIKit.button("Done", Color(0.16, 0.14, 0.18), Color(0.6, 0.55, 0.5), Vector2(120, 44), 15)
	done.name = "Done"
	done.pressed.connect(close)
	foot.add_child(done)
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	queue_free()


## Something was changed (or refused, `why`): show it, redraw this and the menu's tab row.
func _changed(why := "") -> void:
	_note.text = why
	_rebuild()
	if menu != null:
		menu.stash_tabs_changed()


func _rebuild() -> void:
	for c in _list.get_children():  # (taken out now, so the new rows can have the old rows' names)
		_list.remove_child(c)
		c.queue_free()
	for i in GameState.stash_tabs.size():
		_list.add_child(_row(i))
	var add := find_child("AddTab", true, false) as Button
	if add != null:
		add.disabled = GameState.stash_tabs.size() >= GameState.MAX_STASH_TABS


func _row(i: int) -> HBoxContainer:
	var t: Dictionary = GameState.stash_tabs[i]
	var row := HBoxContainer.new()
	row.name = "Tab_%d" % i
	row.add_theme_constant_override("separation", 6)
	var name_edit := LineEdit.new()
	name_edit.name = "Name"
	name_edit.text = String(t.name)
	name_edit.max_length = GameState.TAB_NAME_MAX
	name_edit.custom_minimum_size = Vector2(190, 42)
	name_edit.add_theme_font_size_override("font_size", 16)
	var commit := func(text: String):
		if text.strip_edges() != String(GameState.stash_tabs[i].name):
			GameState.rename_stash_tab(i, text)
			_changed()
	name_edit.text_submitted.connect(commit)
	name_edit.focus_exited.connect(func(): commit.call(name_edit.text))
	row.add_child(name_edit)

	var kind := OptionButton.new()
	kind.name = "Kind"
	kind.custom_minimum_size = Vector2(130, 42)
	kind.add_theme_font_size_override("font_size", 15)
	for k in GameState.TAB_TYPES.size():
		var type: String = GameState.TAB_TYPES[k]
		kind.add_item("%s %s" % [GameState.TAB_ICONS[type], GameState.TAB_TYPE_NAMES[type]], k)
		if type == t.type:
			kind.select(k)
	kind.disabled = i == 0
	kind.item_selected.connect(func(idx: int):
		var why := GameState.set_stash_tab_type(i, String(GameState.TAB_TYPES[idx]))
		_changed(why))
	row.add_child(kind)

	for m in [["▲", -1], ["▼", 1]]:
		var b := UIKit.button(m[0], Color(0.12, 0.10, 0.16), Color(0.5, 0.45, 0.6), Vector2(42, 42), 15)
		b.name = "Up" if m[1] < 0 else "Down"
		var d: int = m[1]
		b.disabled = i == 0 or i + d <= 0 or i + d >= GameState.stash_tabs.size()
		b.pressed.connect(func():
			GameState.move_stash_tab(i, d)
			_changed())
		row.add_child(b)

	var del := UIKit.button("🗑", Color(0.25, 0.10, 0.10), Color(0.85, 0.45, 0.30), Vector2(46, 42), 16)
	del.name = "Delete"
	del.disabled = i == 0
	var holds: int = GameState.stash_grid(i).count() if GameState.stash_grid(i) != null else 0
	del.tooltip_text = "Delete this tab" + (" (its %d item%s move to the other tabs)" % [holds, "" if holds == 1 else "s"] if holds > 0 else "")
	del.pressed.connect(func():
		GameState.remove_stash_tab(i)
		_changed())
	row.add_child(del)
	return row
