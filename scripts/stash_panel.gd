class_name StashPanel
extends MenuPanel
## Shared (account-wide) stash: a grid like the bag, bigger. Drag gear between it and the bag on
## the right, or within the stash to rearrange; dropping onto one item swaps the two.

const CELL := 44.0


func panel_title() -> String:
	return "📦 Stash"


func refresh() -> void:
	UIKit.clear(self)
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
		_show_info(menu.selected)


func _show_info(it: ItemInstance) -> void:
	UIKit.item_card(self, it, true)
