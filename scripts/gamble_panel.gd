class_name GamblePanel
extends MenuPanel
## The Gambler's stall (Gambler): unidentified gear in a grid, as big as fits the panel. Tap a piece
## for its card with its price and Buy, or drag it into your bag to buy it. On the stall every piece
## shows as a plain one of its base (_shown): no rarity colour, no sockets, so nothing gives away what
## it really is until it's yours. The stall is new every so often, or once
## it's sold out; how long until then shows at the top.

const SEP := 4
const MIN_CELL := 64.0
const MAX_CELL := 120.0

var _cell := 0.0
var _timer: Label
var _picked: ItemInstance = null  # the piece tapped last (outlined)
var _plain := {}  # piece -> how the stall shows it (_shown)


func panel_title() -> String:
	return "🎲 Gambler"


func _ready() -> void:
	resized.connect(_refit.call_deferred)
	visibility_changed.connect(_refit.call_deferred)


func _refit() -> void:
	if is_visible_in_tree() and _fit(Gambler.STOCK_SIZE)[1] != _cell:
		refresh()


## The countdown, and new wares when it runs out while the stall is open.
func _process(_delta: float) -> void:
	if _timer == null or not is_visible_in_tree():
		return
	var left := Gambler.seconds_left()
	if left <= 0:
		Gambler.restock()
		menu.feedback("The Gambler lays out new wares.")
		menu.refresh()
		return
	_timer.text = "New wares in %d:%02d, or as soon as you've bought them all." % [left / 60, left % 60]


func _scroll() -> ScrollContainer:
	var n := get_parent()
	while n != null and not n is ScrollContainer:
		n = n.get_parent()
	return n as ScrollContainer


## [columns, cell size] for `n` pieces: the biggest square cells that fit them all in the panel.
func _fit(n: int) -> Array:
	var w := (size.x if size.x > 0.0 else 600.0) - 24.0
	var sc := _scroll()
	var h := (sc.size.y if sc != null and sc.size.y > 0.0 else 500.0) - 84.0  # the title and the countdown
	var best := [maxi(1, int(w / (MIN_CELL + SEP))), MIN_CELL]
	for cols in range(1, n + 1):
		var rows := ceili(float(n) / cols)
		var c := floorf(minf(w / cols, h / rows) - SEP)
		if c > best[1]:
			best = [cols, minf(c, MAX_CELL)]
	return best


func refresh() -> void:
	UIKit.clear(self)
	var wares := Gambler.stock()
	for k in _plain.keys():
		if not k in wares:
			_plain.erase(k)  # sold or gone
	var fit := _fit(Gambler.STOCK_SIZE)
	_cell = fit[1]
	var sec := UIKit.section(self, "THE GAMBLER'S WARES  —  unidentified: you pay for what it might be")
	_timer = UIKit.label("", 13, UIKit.TEXT_DIM, true)
	sec.add_child(_timer)
	var grid := UIKit.grid(fit[0], SEP)
	sec.add_child(grid)
	for it in wares:
		grid.add_child(_ware_cell(it))
	_process(0.0)


## How the stall shows a piece: a plain (Normal) one of its base and item level, unidentified, its
## sockets and rarity hidden.
func _shown(it: ItemInstance) -> ItemInstance:
	if not _plain.has(it):
		var p := ItemInstance.new()
		p.base = it.base
		p.ilvl = it.ilvl
		p.implicit_roll = it.implicit_roll
		p.display_name = it.base.display_name
		p.identified = false
		_plain[it] = p
	return _plain[it]


func _ware_cell(it: ItemInstance) -> DragSlot:
	var cell := UIKit.item_cell(_shown(it), it == _picked, Vector2(_cell, _cell))
	if not GameState.can_afford(Gambler.price(it)):
		cell.modulate = Color(1, 1, 1, 0.5)
	cell.payload = {"kind": "gamble", "item": it}
	cell.clicked.connect(func():
		_picked = it
		var at := get_viewport().get_mouse_position()
		menu.refresh()
		_show_card(it, at))
	return cell


## A piece's card where it was tapped: only what the stall shows (no Identify), its price, and Buy.
func _show_card(it: ItemInstance, at: Vector2) -> void:
	menu.item_tip().show_card(_shown(it), at, {}, func(d: VBoxContainer):
		var p := Gambler.price(it)
		var afford := GameState.can_afford(p)
		d.add_child(UIKit.rich("[color=#9a8f7e]Costs[/color] %s  [color=#9a8f7e](you have %s)[/color]" % [Currency.price_text(p),
			", ".join(PackedStringArray(p.keys().map(func(k): return str(GameState.orb_count(k)))))], 14))
		var buy := UIKit.button("🎲 Buy" if afford else "🎲 Buy (not enough orbs)", Color(0.22, 0.16, 0.08), Color(0.95, 0.80, 0.30), Vector2(0, 48), 16)
		buy.disabled = not afford
		buy.pressed.connect(func():
			menu.item_tip().close()
			_buy(it))
		d.add_child(buy)
		d.add_child(UIKit.label("Or drag it into your bag.", 12, UIKit.TEXT_DIM)))


func accepts_bag_drop(d: Dictionary) -> bool:
	return d.get("kind", "") == "gamble"


func on_bag_drop(d: Dictionary, _at: Vector2i) -> void:
	_buy(d.get("item"))


func _buy(it: ItemInstance) -> void:
	if it == null:
		return
	var why := Gambler.buy(player, it)
	if why != "":
		menu.feedback(why)
	elif GameState.gamble_stock.is_empty():
		Gambler.restock()
		menu.feedback("You bought %s. That's the lot: the Gambler lays out new wares." % it.display_name)
	else:
		menu.feedback("You bought %s. Identify it to see what it is." % it.display_name)
	_picked = null
	menu.refresh()
