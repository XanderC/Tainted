class_name StashPanel
extends MenuPanel
## The shared (account-wide) stash, in tabs:
##   Items     - a grid like the bag, bigger. Drag gear between it and the bag on the right, or
##               within the stash to rearrange; dropping onto one item swaps the two.
##   Currency  - every orb, with shards. Drag an orb onto worn gear to use it.
##   Materials - crafting materials, spent by the Blacksmith's recipes.
##   Gems      - the gem station: your skill slots and the sockets of the item tapped in your
##               bag, beside the shared skill, support and socket gems. Gems can only be changed
##               here (or socketed at the Jeweler).
## Everything here is shared by all your characters.

const CELL := 44.0
const TABS := [["items", "📦 Items"], ["currency", "💰 Currency"], ["materials", "⚒ Materials"], ["gems", "💠 Gems"]]
const ORB_CELL := Vector2(64, 64)

var tab := "items"
# Built once and kept, so a gem tapped in them stays selected between refreshes
var _skills: SkillGemsPanel
var _sockets: GemsPanel


func panel_title() -> String:
	return "📦 Stash"


func refresh() -> void:
	# The embedded gem panels outlive a refresh; everything else is rebuilt
	for c in get_children():
		if c == _skills or c == _sockets:
			remove_child(c)
		else:
			c.queue_free()
	_add_tabs()
	match tab:
		"currency": _show_currency()
		"materials": _show_materials()
		"gems": _show_gems()
		_: _show_items()


func _add_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for t in TABS:
		var active: bool = tab == t[0]
		var b := UIKit.button(t[1], Color(0.24, 0.18, 0.10) if active else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.82, 0.40) if active else Color(0.35, 0.28, 0.20), Vector2(0, 40), 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = t[0]
		b.pressed.connect(func():
			tab = id
			menu.refresh()
		)
		row.add_child(b)


# ---------- items ----------

func _show_items() -> void:
	var used := GameState.STASH_SIZE - GameState.stash.free_cells()
	var sec := UIKit.section(self, "SHARED STASH   %d items   %d / %d cells" % [
		GameState.stash.count(), used, GameState.STASH_SIZE])
	sec.add_child(UIKit.label("Drag gear between the stash and your bag. Bigger pieces take more room. Every character shares this stash.", 13, UIKit.TEXT_DIM, true))

	var view := ItemGridView.new(GameState.stash, CELL, "stash")
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.selected = menu.selected
	view.can_accept_at = func(d: Dictionary, at: Vector2i) -> bool:
		var it: ItemInstance = d.get("item")
		if d.get("kind", "") != "item" or it == null:
			return false
		match d.get("from", ""):
			"bag": return GameState.can_bag_to_stash(it, at)
			"stash": return not GameState.stash.plan_drop(it, at, GameState.stash).is_empty()
		return false
	view.on_drop_at = func(d: Dictionary, at: Vector2i) -> void:
		var it: ItemInstance = d.get("item")
		if d.get("from", "") == "bag":
			GameState.bag_to_stash(it, at)
		else:
			GameState.move_in_stash(it, at)
		menu.refresh()
	view.item_clicked.connect(func(it: ItemInstance):
		menu.selected = it
		menu.refresh()
	)
	sec.add_child(view)
	view.refresh()

	if not GameState.stash_overflow.is_empty():
		var over := UIKit.section(self, "WAITING FOR ROOM   %d" % GameState.stash_overflow.size())
		over.add_child(UIKit.label("These didn't fit when your save was loaded (gear now takes more than one cell). Make room in the stash and they move in.", 13, UIKit.TEXT_DIM, true))
		var row := UIKit.grid(8)
		over.add_child(row)
		for it in GameState.stash_overflow:
			var cell := UIKit.item_cell(it, false, Vector2(52, 52))
			cell.clicked.connect(func():
				menu.selected = it
				menu.refresh()
			)
			row.add_child(cell)

	if menu.selected != null and GameState.stash.has(menu.selected):
		UIKit.item_card(self, menu.selected, true)


# ---------- currency ----------

func _show_currency() -> void:
	var sec := UIKit.section(self, "CURRENCY")
	sec.add_child(UIKit.label("Shared by all your characters. Drag an orb onto gear you're wearing to use it, or use orbs on any item from its details.", 13, UIKit.TEXT_DIM, true))
	var grid := UIKit.grid(6)
	sec.add_child(grid)
	for id in CraftingDB.ORB_ORDER:
		var o: Dictionary = CraftingDB.ORBS[id]
		var n := GameState.orb_count(id)
		var sh := GameState.shard_count(id)
		var cell := DragSlot.new(ORB_CELL)
		var tip := "%s\n%s" % [o.name, o.desc]
		if sh > 0:
			tip += "\nShards: %d / %d" % [sh, Currency.SHARDS_PER_ORB]
		cell.setup(CraftingDB.orb_icon(id), Color(o.color) if n > 0 else UIKit.EMPTY_BORDER, Color(0.08, 0.07, 0.10), n, "", tip)
		if n <= 0:
			cell.modulate = Color(1, 1, 1, 0.4)
		else:
			cell.payload = {"kind": "orb", "id": id}
		if sh > 0:
			var l := UIKit.label("%d/%d" % [sh, Currency.SHARDS_PER_ORB], 10, Color(0.85, 0.85, 0.95))
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 4)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.offset_left = 3
			cell.add_child(l)
		cell.clicked.connect(func(): menu.feedback("%s: %s" % [o.name, o.desc]))
		grid.add_child(cell)


# ---------- materials ----------

func _show_materials() -> void:
	var sec := UIKit.section(self, "CRAFTING MATERIALS")
	sec.add_child(UIKit.label("Shared by all your characters. The Blacksmith's recipes use them.", 13, UIKit.TEXT_DIM, true))
	for k in CraftingDB.MATERIALS:
		var m: Dictionary = CraftingDB.MATERIALS[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = IconFactory.material_icon(k, m.color)
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name_l := UIKit.label(m.name, 17, m.color)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(UIKit.label(str(GameState.material_count(k)), 18, Color(0.95, 0.92, 0.85)))
		sec.add_child(row)


# ---------- gems ----------

func _show_gems() -> void:
	if _skills == null:
		_skills = SkillGemsPanel.new()
		_skills.embedded = true
		_sockets = GemsPanel.new()
		_sockets.embedded = true
		for p in [_skills, _sockets]:
			p.menu = menu
			p.player = player
	add_child(_skills)
	_skills.refresh()
	add_child(_sockets)
	_sockets.refresh()


func _notification(what: int) -> void:
	# The gem panels are kept out of the tree on the other tabs; free them with the stash
	if what == NOTIFICATION_PREDELETE:
		for p in [_skills, _sockets]:
			if p != null and not p.is_inside_tree():
				p.free()
