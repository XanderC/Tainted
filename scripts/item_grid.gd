class_name ItemGrid
extends RefCounted
## A Diablo / Path of Exile style storage grid: `cols` x `rows` cells, each item covering a
## rectangle of them (ItemInstance.grid_size()) from its top-left cell. Used by the bag and the
## stash, so how much they hold depends on what shape the gear is, not just how many pieces.

const NONE := Vector2i(-1, -1)

var cols: int
var rows: int
var _pos: Dictionary = {}  # ItemInstance -> Vector2i (top-left cell)


func _init(c := 10, r := 6) -> void:
	cols = c
	rows = r


## Items in reading order (top to bottom, then left to right), so lists built from the grid stay
## stable.
func items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for it in _pos:
		out.append(it)
	out.sort_custom(func(a, b):
		var pa: Vector2i = _pos[a]
		var pb: Vector2i = _pos[b]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x))
	return out


func count() -> int:
	return _pos.size()


func has(item: ItemInstance) -> bool:
	return item != null and _pos.has(item)


## Top-left cell of `item`, or NONE if it isn't here.
func position_of(item: ItemInstance) -> Vector2i:
	return _pos.get(item, NONE)


func rect_of(item: ItemInstance) -> Rect2i:
	return Rect2i(position_of(item), item.grid_size())


## The item covering `cell`, or null.
func item_at(cell: Vector2i) -> ItemInstance:
	for it in _pos:
		if Rect2i(_pos[it], it.grid_size()).has_point(cell):
			return it
	return null


func in_bounds(item: ItemInstance, at: Vector2i) -> bool:
	var s := item.grid_size()
	return at.x >= 0 and at.y >= 0 and at.x + s.x <= cols and at.y + s.y <= rows


## Items `item` would overlap if put at `at`, leaving out the ones in `ignore` (the item itself
## when it is being moved within this grid).
func overlaps(item: ItemInstance, at: Vector2i, ignore: Array = []) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var r := Rect2i(at, item.grid_size())
	for it in _pos:
		if it == item or ignore.has(it):
			continue
		if r.intersects(Rect2i(_pos[it], it.grid_size())):
			out.append(it)
	return out


func fits(item: ItemInstance, at: Vector2i, ignore: Array = []) -> bool:
	return in_bounds(item, at) and overlaps(item, at, ignore).is_empty()


## First free spot for `item`, column by column from the top left as Diablo fills a bag, or NONE.
func find_free(item: ItemInstance, ignore: Array = []) -> Vector2i:
	var s := item.grid_size()
	for x in cols - s.x + 1:
		for y in rows - s.y + 1:
			var at := Vector2i(x, y)
			if fits(item, at, ignore):
				return at
	return NONE


func can_fit(item: ItemInstance) -> bool:
	return has(item) or find_free(item) != NONE


## Put `item` at `at` (moving it if already here). False if it doesn't fit there.
func place(item: ItemInstance, at: Vector2i) -> bool:
	if not fits(item, at):
		return false
	_pos[item] = at
	return true


## Put `item` in the first free spot. False if there is no room.
func add(item: ItemInstance) -> bool:
	if has(item):
		return true
	var at := find_free(item)
	if at == NONE:
		return false
	_pos[item] = at
	return true


func remove(item: ItemInstance) -> bool:
	return _pos.erase(item)


func clear() -> void:
	_pos.clear()


func duplicate_grid() -> ItemGrid:
	var g := ItemGrid.new(cols, rows)
	g._pos = _pos.duplicate()
	return g


## Whether every item in `list` can be added, in order, on top of what is here now.
func can_fit_all(list: Array) -> bool:
	var g := duplicate_grid()
	for it in list:
		if not g.add(it):
			return false
	return true


## Cells no item covers.
func free_cells() -> int:
	var used := 0
	for it in _pos:
		var s: Vector2i = it.grid_size()
		used += s.x * s.y
	return cols * rows - used


# ---------- dropping one item onto another ----------

## Whether `item` can be dropped with its top-left at `at`, and what happens if so. `from` is the
## grid it comes from (this one, another, or null when it isn't in a grid -- worn gear).
##   {}                                  - it can't go there
##   {"ok": true}                        - the space is free
##   {"ok": true, "swap": b, "swap_to": cell}
##       - it lands on exactly one item, b, which goes to `cell` in `from` (where `item` was if
##         b fits there, else anywhere). With `from` null, swap_to is NONE and the caller decides
##         where b goes (back into the gear slot `item` came out of).
## Landing on two or more items is refused, as in Diablo.
func plan_drop(item: ItemInstance, at: Vector2i, from: ItemGrid) -> Dictionary:
	if not in_bounds(item, at):
		return {}
	var blockers := overlaps(item, at)
	if blockers.is_empty():
		return {"ok": true}
	if blockers.size() > 1:
		return {}
	var b := blockers[0]
	if from == null:
		return {"ok": true, "swap": b, "swap_to": NONE}
	var old := from.position_of(item)
	var src := from.duplicate_grid()
	src.remove(item)
	if from == self:
		src.remove(b)
		src._pos[item] = at
	var spot := old if old != NONE and src.fits(b, old) else src.find_free(b)
	if spot == NONE:
		return {}
	return {"ok": true, "swap": b, "swap_to": spot}


## Carry out a plan_drop() (one with no `from`-less swap -- the caller does those).
func apply_drop(item: ItemInstance, at: Vector2i, from: ItemGrid, plan: Dictionary) -> void:
	var b: ItemInstance = plan.get("swap")
	if from != null:
		from.remove(item)
	if b != null:
		remove(b)
	_pos[item] = at
	if b != null and from != null:
		from._pos[b] = plan.get("swap_to")


# ---------- saving ----------

func to_array() -> Array:
	var out: Array = []
	for it in items():
		var at: Vector2i = _pos[it]
		out.append({"item": it.to_dict(), "x": at.x, "y": at.y})
	return out


## Restores from to_array(). Also reads the old saves: a plain list of item dicts (with nulls for
## empty slots), whose items are placed in the first free spot each. Anything that no longer fits
## is returned so the caller can put it somewhere rather than lose it.
func load_array(list: Array) -> Array[ItemInstance]:
	clear()
	var homeless: Array[ItemInstance] = []
	var unplaced: Array[ItemInstance] = []
	for e in list:
		if e == null:
			continue
		if e is Dictionary and e.has("item"):
			var it := ItemInstance.from_dict(e["item"])
			if it == null:
				continue
			if not place(it, Vector2i(int(e.get("x", -1)), int(e.get("y", -1)))):
				unplaced.append(it)
		else:
			var old := ItemInstance.from_dict(e)
			if old != null:
				unplaced.append(old)
	# Largest first, so the awkward pieces get the room
	unplaced.sort_custom(func(a, b):
		var sa: Vector2i = a.grid_size()
		var sb: Vector2i = b.grid_size()
		return sa.x * sa.y > sb.x * sb.y)
	for it in unplaced:
		if not add(it):
			homeless.append(it)
	return homeless
