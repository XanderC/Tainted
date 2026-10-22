class_name ItemGridView
extends Control
## Shows an ItemGrid (the bag, the stash): a board of cells with each item drawn across the cells
## it covers. Items drag out of it like any DragSlot; anything dragged over it shows the cells it
## would take, green where it fits and red where it doesn't. The owner decides what a drop does:
##   can_accept_at - Callable(data: Dictionary, at: Vector2i) -> bool
##   on_drop_at    - Callable(data: Dictionary, at: Vector2i)
## `at` is the top-left cell an item would land on (ItemGrid.NONE for drops that aren't gear, such
## as a merchant's ware, which can land anywhere). Something dropped onto an item rather than into
## the grid (a socket gem) goes to can_accept_item / on_drop_item instead, with that item.

signal item_clicked(item: ItemInstance)

const LINE := Color(0.20, 0.17, 0.22)
const BOARD := Color(0.06, 0.05, 0.08)
const FIT := Color(0.35, 1.0, 0.45)
const NO_FIT := Color(1.0, 0.35, 0.35)

var grid: ItemGrid
var cell := 48.0
var source := "bag"  # the payload's "from" for items dragged out of here
var selected: ItemInstance = null
var can_accept_at: Callable = Callable()
var on_drop_at: Callable = Callable()
## Drops onto an item (data["kind"] == "gem"): Callable(data, item) -> bool, Callable(data, item)
var can_accept_item: Callable = Callable()
var on_drop_item: Callable = Callable()

var _hover := Rect2i()
var _hover_ok := false
var _hovering := false
## Drawn above the item tiles: a control draws beneath its own children, so the landing outline
## would be hidden under any item it overlaps.
var _overlay := Control.new()


func _init(g: ItemGrid, cell_px: float, from: String) -> void:
	grid = g
	cell = cell_px
	source = from
	custom_minimum_size = Vector2(g.cols, g.rows) * cell
	mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = custom_minimum_size
	_overlay.draw.connect(_draw_hover)
	add_child(_overlay)


## Rebuild the item tiles from the grid.
func refresh() -> void:
	for c in get_children():
		if c != _overlay:
			c.queue_free()
	for it in grid.items():
		var r := grid.rect_of(it)
		var px := Vector2(r.size) * cell
		var tile := UIKit.item_cell(it, it == selected, px - Vector2(2, 2))
		tile.position = Vector2(r.position) * cell + Vector2(1, 1)
		tile.size = px - Vector2(2, 2)
		tile.grid_cell = cell
		tile.payload = {"kind": "item", "from": source, "item": it}
		var origin := Vector2(r.position) * cell
		tile.can_accept_at = func(d: Dictionary, p: Vector2) -> bool:
			if d.get("kind", "") == "gem":  # onto this item (into a socket), not into the grid
				return can_accept_item.is_valid() and bool(can_accept_item.call(d, it))
			return _check(d, origin + p)
		tile.on_drop_at = func(d: Dictionary, p: Vector2) -> void:
			if d.get("kind", "") == "gem":
				if on_drop_item.is_valid():
					on_drop_item.call(d, it)
				return
			_drop(d, origin + p)
		tile.clicked.connect(func(): item_clicked.emit(it))
		add_child(tile)
	move_child(_overlay, -1)
	queue_redraw()


## The top-left cell `data`'s item would land on with the pointer at `pos`: the cell it was
## grabbed by goes under the pointer, kept inside the grid.
func target_cell(data: Dictionary, pos: Vector2) -> Vector2i:
	var it: ItemInstance = data.get("item")
	if it == null:
		return ItemGrid.NONE
	var s := it.grid_size()
	var grab: Vector2i = data.get("grab", Vector2i(s.x / 2, s.y / 2))
	var c := Vector2i(int(floor(pos.x / cell)), int(floor(pos.y / cell))) - grab
	return Vector2i(clampi(c.x, 0, maxi(grid.cols - s.x, 0)), clampi(c.y, 0, maxi(grid.rows - s.y, 0)))


func _check(data: Variant, pos: Vector2) -> bool:
	if not data is Dictionary or not can_accept_at.is_valid():
		return false
	var at := target_cell(data, pos)
	var ok := bool(can_accept_at.call(data, at))
	var it: ItemInstance = data.get("item")
	if it != null and data.get("kind", "") == "item":
		_hover = Rect2i(at, it.grid_size())
		_hover_ok = ok
		_hovering = true
	else:
		_hovering = false
	_overlay.queue_redraw()
	return ok


func _drop(data: Variant, pos: Vector2) -> void:
	_hovering = false
	_overlay.queue_redraw()
	if data is Dictionary and on_drop_at.is_valid():
		on_drop_at.call(data, target_cell(data, pos))


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return _check(data, at_position)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_drop(data, at_position)


func _notification(what: int) -> void:
	if (what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT) and _hovering:
		_hovering = false
		_overlay.queue_redraw()


func _draw() -> void:
	var slot := UIKit.mmo("slot")
	# Not under an item: its tile is one slot of its own size, and the cells would show through it
	var covered := {}
	for it in grid.items():
		var r := grid.rect_of(it)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				covered[Vector2i(x, y)] = true
	for y in grid.rows:
		for x in grid.cols:
			if not covered.has(Vector2i(x, y)):
				draw_texture_rect(slot, Rect2(x * cell, y * cell, cell, cell), false)


func _draw_hover() -> void:
	if not _hovering:
		return
	var r := Rect2(Vector2(_hover.position) * cell, Vector2(_hover.size) * cell)
	var col := FIT if _hover_ok else NO_FIT
	_overlay.draw_rect(r, Color(col, 0.22))
	_overlay.draw_rect(r, col, false, 3.0)
