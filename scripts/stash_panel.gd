class_name StashPanel
extends MenuPanel
## The shared (account-wide) stash. At the stash the menu's tab row is Items, Skills, Currency,
## Gems (GameMenu._build_tabs); Items and Currency are this panel, Skills and Gems are the usual
## gem panels, which can change gems here (GameState.gem_station).
##   Items     - a grid like the bag, bigger. Drag gear between it and the bag on the right, or
##               within the stash to rearrange; dropping onto one item swaps the two.
##   Currency  - the one place currency is used. Drag a piece of gear into the slot (or tap it),
##               pick an orb, then tap Use. After a use the item shows before and after.
## Everything here is shared by all your characters.

const CELL := 44.0
const ORB_CELL := Vector2(60, 60)
const BENCH_SLOT := Vector2(150, 150)

var tab := "items"  # "items" | "currency"
var _orb := ""  # the orb picked on the Currency tab
# The item as it was before the last orb used on it, to show what changed
var _before: ItemInstance = null
var _before_of: ItemInstance = null


func panel_title() -> String:
	return "📦 Stash"


func refresh() -> void:
	UIKit.clear(self)
	if tab == "currency":
		_show_currency()
	else:
		_show_items()


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
		menu.show_item_tip(it)
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
				menu.show_item_tip(it)
			)
			row.add_child(cell)

	if menu.selected != null:
		UIKit.item_card(self, menu.selected, true)


# ---------- currency ----------

func _show_currency() -> void:
	# The item on the bench is the menu's selection: dragged into the slot, or tapped anywhere
	var it := menu.selected
	if it != _before_of:
		_before = null
		_before_of = null
	var sec := UIKit.section(self, "CURRENCY")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	sec.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = BENCH_SLOT.x
	row.add_child(left)
	left.add_child(_bench_slot(it))
	var why := _use_block_reason(it)
	var have := GameState.orb_count(_orb) if _orb != "" else 0
	var use := UIKit.button("✨ Use %s" % CraftingDB.ORBS[_orb].short if _orb != "" else "✨ Use",
		Color(0.12, 0.18, 0.30), Color(0.55, 0.75, 1.0), Vector2(0, 52), 15)
	use.disabled = why != ""
	use.pressed.connect(_use.bind(it))
	left.add_child(use)
	if _orb != "":
		left.add_child(UIKit.label("You have %d" % have, 13, UIKit.TEXT_DIM))
	if why != "":
		left.add_child(UIKit.label(why, 13, Color(0.95, 0.55, 0.45), true))
	if it != null:
		var clear := UIKit.button("✕ Take out", Color(0.16, 0.12, 0.12), Color(0.50, 0.35, 0.30), Vector2(0, 40), 14)
		clear.pressed.connect(func():
			menu.selected = null
			menu.refresh()
		)
		left.add_child(clear)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	if it == null:
		right.add_child(UIKit.rich("[color=#8a7f6e]Drag a piece of gear from your bag, your equipment or the Items tab " +
			"into the slot (or tap it), pick an orb below, then tap Use.\n\nThe item's details show here, " +
			"and after each use you see it before and after.[/color]", 15))
	elif _before != null:
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 8)
		right.add_child(cols)
		UIKit.item_card(_column(cols, "BEFORE"), _before, true)
		UIKit.item_card(_column(cols, "AFTER"), it, true)
		var changes := _changes(_before, it)
		if changes != "":
			right.add_child(UIKit.rich(changes, 14))
	else:
		UIKit.item_card(right, it, true)

	sec.add_child(UIKit.label("Tap an orb to pick it and see what it does. Dimmed orbs can't be used on this item.", 13, UIKit.TEXT_DIM, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	sec.add_child(flow)
	for id in CraftingDB.ORB_ORDER:
		flow.add_child(_orb_cell(id, it))


## The slot gear is dragged into. It holds a reference: the item stays where it is.
func _bench_slot(it: ItemInstance) -> DragSlot:
	var slot := DragSlot.new(BENCH_SLOT)
	if it != null:
		slot.setup(it.base.icon, ItemInstance.RARITY_COLORS[it.rarity], it.base.color.darkened(0.72), 0, it.display_name)
	else:
		slot.setup(null, Color(0.40, 0.34, 0.26), Color(0.08, 0.07, 0.10), 0, "Drag gear here", "Drag a piece of gear here")
	slot.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "item" and d.get("item") != null
	slot.on_drop = func(d: Dictionary) -> void:
		menu.selected = d.item
		menu.refresh()
	return slot


func _orb_cell(id: String, it: ItemInstance) -> DragSlot:
	var o: Dictionary = CraftingDB.ORBS[id]
	var n := GameState.orb_count(id)
	var sh := GameState.shard_count(id)
	var cell := DragSlot.new(ORB_CELL)
	var why := Crafting.orb_block_reason(it, id) if it != null else ""
	var border: Color = Color.WHITE if id == _orb else (Color(o.color) if n > 0 else UIKit.EMPTY_BORDER)
	cell.setup(CraftingDB.orb_icon(id), border, Color(0.20, 0.18, 0.28) if id == _orb else Color(0.08, 0.07, 0.10), n)
	if n <= 0 or why != "":
		cell.modulate = Color(1, 1, 1, 0.4)
	if sh > 0:
		var l := UIKit.label("%d/%d" % [sh, Currency.SHARDS_PER_ORB], 10, Color(0.85, 0.85, 0.95))
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.offset_left = 3
		cell.add_child(l)
	cell.clicked.connect(func():
		_orb = id
		menu.refresh()
		show_orb_tip(id, it)
	)
	return cell


## Pops up an orb's card where it was tapped: what it does, how many you have (and shards), and
## why it can't be used on `it` (the item on the bench), if it can't.
func show_orb_tip(id: String, it: ItemInstance = null) -> void:
	var o: Dictionary = CraftingDB.ORBS[id]
	menu.item_tip().show_content(get_viewport().get_mouse_position(), func(d: VBoxContainer):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		d.add_child(head)
		var icon := TextureRect.new()
		icon.texture = CraftingDB.orb_icon(id)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(icon)
		var title := UIKit.label(String(o.name), 18, Color(o.color).lightened(0.2), true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.custom_minimum_size.x = 200  # clear of the close button
		head.add_child(title)
		d.add_child(UIKit.label(String(o.desc), 14, Color(0.85, 0.82, 0.76), true))
		var have := "You have %d" % GameState.orb_count(id)
		var sh := GameState.shard_count(id)
		if sh > 0:
			have += "  •  Shards %d / %d" % [sh, Currency.SHARDS_PER_ORB]
		d.add_child(UIKit.label(have, 13, Color(0.38, 0.65, 0.98)))
		var why: String = Crafting.NOT_ITEM_ORBS.get(id, "") if Crafting.NOT_ITEM_ORBS.has(id) else (Crafting.orb_block_reason(it, id) if it != null else "")
		if why != "":
			d.add_child(UIKit.label("⛔ " + String(why), 13, Color(0.95, 0.45, 0.40), true)))


## "" when the picked orb can be used on the item now, otherwise what is missing.
func _use_block_reason(it: ItemInstance) -> String:
	if _orb == "":
		return "Pick an orb"
	if Crafting.NOT_ITEM_ORBS.has(_orb):
		return Crafting.NOT_ITEM_ORBS[_orb]
	if it == null:
		return "Put an item in the slot"
	if GameState.orb_count(_orb) <= 0:
		return "You have none"
	return Crafting.orb_block_reason(it, _orb)


func _use(it: ItemInstance) -> void:
	var before := ItemInstance.from_dict(it.to_dict())
	var res := Crafting.apply_orb(player, it, _orb)
	if res.ok:
		_before = before
		_before_of = it
	menu.feedback(res.msg)
	menu.refresh()


## What an orb changed: lines gained in green, lines lost in red.
func _changes(a: ItemInstance, b: ItemInstance) -> String:
	var la := _lines(a)
	var lb := _lines(b)
	var t := ""
	for l in lb:
		if not la.has(l):
			t += "[color=#4ade80]+ %s[/color]\n" % l
	for l in la:
		if not lb.has(l):
			t += "[color=#f87171]− %s[/color]\n" % l
	return t.strip_edges()


func _lines(it: ItemInstance) -> Array[String]:
	var out: Array[String] = [ItemInstance.Rarity.keys()[it.rarity].capitalize()]
	if it.base.implicit_stat != "":
		out.append("+%d %s (implicit)" % [int(it.implicit_value()), it.base.implicit_stat.replace("_", " ").capitalize()])
	if it.quality > 0:
		out.append("Quality +%d%%" % it.quality)
	if it.sockets > 0:
		out.append("%d socket%s" % [it.sockets, "" if it.sockets == 1 else "s"])
	if it.corrupted:
		out.append("Corrupted")
	if not it.identified:
		out.append("Unidentified")
		return out
	for af in it.affixes:
		out.append(String(af.text))
	return out


func _column(row: HBoxContainer, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var l := UIKit.label(title, 12, Color(0.60, 0.55, 0.48))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return col
