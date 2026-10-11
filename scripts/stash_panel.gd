class_name StashPanel
extends MenuPanel
## Shared (account-wide) stash grid. Drag items between it and the bag on the right, or within the
## stash to rearrange; dropping on an occupied slot swaps the two items.

const COLS := 10
const CELL := Vector2(54, 54)


func panel_title() -> String:
	return "📦 Stash"


func refresh() -> void:
	UIKit.clear(self)
	var sec := UIKit.section(self, "SHARED STASH   %d / %d" % [GameState.stash.size(), GameState.STASH_SIZE])
	sec.add_child(UIKit.label("Drag items between the stash and your bag. Every character shares this stash.", 13, UIKit.TEXT_DIM, true))
	var grid := UIKit.grid(COLS)
	sec.add_child(grid)
	for i in GameState.STASH_SIZE:
		var it: ItemInstance = GameState.stash[i] if i < GameState.stash.size() else null
		var cell := UIKit.item_cell(it, it != null and it == menu.selected, CELL)
		if it != null:
			cell.payload = {"kind": "item", "from": "stash", "idx": i, "item": it}
			cell.clicked.connect(func():
				menu.selected = it
				menu.refresh()
			)
		cell.can_accept = func(d: Dictionary) -> bool:
			if d.get("kind", "") != "item":
				return false
			match d.get("from", ""):
				"bag": return true
				"stash": return int(d.get("idx", -1)) != i
			return false
		cell.on_drop = func(d: Dictionary) -> void:
			if d.get("from", "") == "bag":
				GameState.bag_to_stash_slot(int(d.get("idx", -1)), i)
			else:
				GameState.move_stash_slot(int(d.get("idx", -1)), i)
			menu.refresh()
		grid.add_child(cell)
	if menu.selected != null and GameState.stash.has(menu.selected):
		_show_info(menu.selected)


func _show_info(it: ItemInstance) -> void:
	UIKit.item_card(self, it, true)
