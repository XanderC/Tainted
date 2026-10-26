class_name ShopPanel
extends MenuPanel
## Merchant: an icon grid of wares priced in orbs (there is no gold: orbs are the money, as in
## Path of Exile), including a currency exchange of cheaper orbs for better ones. Selling pays
## in orbs and shards (Currency.sell_value). Drag a ware onto your bag to buy it, drag a bag
## item onto the merchant grid to sell it. Tap a ware for its card with Buy, or a bag item for its
## card with what it sells for and Sell (the menu's ItemTip, where it was tapped).
## The wares fill the panel: the grid takes the biggest cells that fit them all without scrolling.
## A ware shows only its icon (dimmed when you can't afford it); its price is on its card.

## Between cells: the slot art fades out over its outer 4 px, so cells overlap by that, leaving
## its frames 2 px apart
const SEP := -6
const MIN_CELL := 48.0
const MAX_CELL := 112.0

var _cols := 0  # columns and cell size last laid out; a resize that changes them rebuilds the grid
var _cell := 0.0

var _ware := {}  # the ware last tapped (outlined)


func panel_title() -> String:
	return "🛒 Merchant"


func _ready() -> void:
	resized.connect(_refit.call_deferred)
	visibility_changed.connect(_refit.call_deferred)
	var scroll := _scroll()
	if scroll != null:
		scroll.resized.connect(_refit.call_deferred)


## Lays the wares out again when the room for them changed (once the menu's layout has settled).
func _refit() -> void:
	if is_visible_in_tree() and _fit(_wares().size()) != [_cols, _cell]:
		refresh()


## The scroll area the panel sits in (its height is the room the wares have).
func _scroll() -> ScrollContainer:
	var n := get_parent()
	while n != null and not n is ScrollContainer:
		n = n.get_parent()
	return n as ScrollContainer


## [columns, cell size] for `n` wares: the biggest cells that fit them all in the panel.
func _fit(n: int) -> Array:
	var w := (size.x if size.x > 0.0 else 600.0) - 24.0  # the section's padding
	var sc := _scroll()
	var h := (sc.size.y if sc != null and sc.size.y > 0.0 else 500.0) - 60.0  # its title and padding
	var best := [maxi(1, int(w / (MIN_CELL + SEP))), MIN_CELL]
	for cols in range(1, n + 1):
		var rows := ceili(float(n) / cols)
		var c := floorf(minf(w / cols, h / rows) - SEP)
		if c > best[1]:
			best = [cols, minf(c, MAX_CELL)]
	return best


func refresh() -> void:
	UIKit.clear(self)
	var wares := _wares()
	var fit := _fit(wares.size())
	_cols = fit[0]
	_cell = fit[1]
	var sec := UIKit.section(self, "MERCHANT'S WARES")
	var grid := UIKit.grid(_cols, SEP)
	sec.add_child(grid)
	for w in wares:
		grid.add_child(_ware_cell(w))
	# Spare cells to drop items on to sell: the rest of the last row
	for i in (_cols - wares.size() % _cols) % _cols:
		var cell := DragSlot.new(Vector2(_cell, _cell))
		cell.setup(null, UIKit.EMPTY_BORDER)
		cell.can_accept = _accepts_sell
		cell.on_drop = _sell_dropped
		grid.add_child(cell)


func accepts_bag_drop(d: Dictionary) -> bool:
	return d.get("kind", "") == "ware"


func on_bag_drop(d: Dictionary, _at: Vector2i) -> void:
	_buy(d.get("ware", {}))


## What a Normal flask costs, by tier (small, medium, large; utility flasks as small).
const FLASK_PRICES := [{"transmute": 1}, {"alteration": 2}, {"alchemy": 1}]


func _wares() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id in CraftingDB.RECIPES:
		var r: Dictionary = CraftingDB.RECIPES[id]
		if r.source == "vendor" and not GameState.knows_recipe(id):
			list.append({"type": "recipe", "id": id, "name": "Recipe: " + r.name, "desc": r.desc,
				"price": r.price, "color": Color(0.95, 0.85, 0.45), "icon": IconFactory.recipe_icon(id)})
	for sk in SkillTree.active_skills():
		list.append({"type": "skillgem", "id": sk.id, "name": "Skill Gem: " + sk.display_name,
			"desc": "%s (needs level %d, %s; %s)" % [sk.description, SkillTree.gem_level_req(sk.id), _gem_need_text(sk.id),
				"costs nothing" if sk.resource_cost <= 0.0 and sk.resource_gain <= 0.0 else sk.resource_name()],
			"price": SkillTree.gem_price(sk.id), "color": sk.gem_color(), "icon": IconFactory.gem_icon("skill:" + sk.id, sk.color, 3)})
	list.append({"type": "scroll", "id": "town_portal", "name": "Scroll of Town Portal",
		"desc": "Read it (🌀 at the top of the screen, or G) in a zone or a rift: a portal to town opens where you stand, and going back through it you come out there again. Your party can use it too. You carry %d (at most %d)." % [GameState.tp_scrolls, GameState.MAX_SCROLLS],
		"price": GameState.SCROLL_PRICE, "color": TownPortals.MINE, "icon": IconFactory.scroll_icon()})
	# Normal flasks of every base; find or craft better ones
	for b in LootGenerator.bases:
		if b.slot != "flask":
			continue
		var f := ItemInstance.new()
		f.base = b
		list.append({"type": "flask", "id": b.id, "name": b.display_name,
			"desc": "%s, cooldown %.0fs. Never runs out." % [f.flask_text("Mana"), float(b.flask.cooldown)],
			"price": FLASK_PRICES[int(b.flask.get("tier", 1)) - 1] if b.flask.kind != "utility" else FLASK_PRICES[0],
			"color": b.color, "icon": b.icon})
	# Currency exchange: better orbs for cheaper ones
	for id in CraftingDB.ORB_ORDER:
		var price := Currency.orb_price(id)
		if price.is_empty():
			continue
		var o: Dictionary = CraftingDB.ORBS[id]
		list.append({"type": "orb", "id": id, "name": o.name, "desc": o.desc,
			"price": price, "color": o.color, "icon": CraftingDB.orb_icon(id)})
	return list


## "18 Dexterity", "18 Strength and 13 Energy": what a skill gem needs.
static func _gem_need_text(skill_id: String) -> String:
	var req := SkillTree.gem_attr_req(skill_id)
	var parts: Array[String] = []
	for k in req:
		parts.append("%d %s" % [int(req[k]), Attributes.NAMES[k]])
	return " and ".join(PackedStringArray(parts))


func _ware_cell(w: Dictionary) -> DragSlot:
	var cell := DragSlot.new(Vector2(_cell, _cell))
	var afford := GameState.can_afford(w.price)
	var sel: bool = _ware.get("id", "") == w.id
	var border: Color = Color.WHITE if sel else (Color(w.color) if afford else Color(0.30, 0.28, 0.32))
	cell.setup(w.icon, border, Color(0.11, 0.10, 0.14))  # tap: its card
	if not afford:
		cell.modulate = Color(1, 1, 1, 0.5)
	cell.payload = {"kind": "ware", "ware": w}
	cell.clicked.connect(func():
		_ware = w
		menu.selected = null
		var at := get_viewport().get_mouse_position()
		menu.refresh()
		_show_ware_tip(w, at)
	)
	cell.can_accept = _accepts_sell
	cell.on_drop = _sell_dropped
	return cell


func _accepts_sell(d: Dictionary) -> bool:
	return d.get("kind", "") == "item" and d.get("from", "") == "bag"


func _sell_dropped(d: Dictionary) -> void:
	_sell(d.get("item"))


func _sell(it: ItemInstance) -> void:
	if it == null:
		return
	var r := GameState.sell_item(it)
	if menu.selected == it:
		menu.selected = null
	menu.feedback("Sold %s: %s" % [it.display_name, Currency.reward_text(r)] if not r.is_empty() else "Could not sell that.")
	menu.refresh()


## A ware's card where it was tapped: what it is, what it costs, and Buy (the card stays, so you
## can buy another).
func _show_ware_tip(w: Dictionary, at: Vector2) -> void:
	menu.item_tip().show_content(at, func(d: VBoxContainer):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		d.add_child(head)
		var icon := TextureRect.new()
		icon.texture = w.icon
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(icon)
		var title := UIKit.label(String(w.name), 18, Color(w.color).lightened(0.2), true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.custom_minimum_size.x = 200  # clear of the close button
		head.add_child(title)
		d.add_child(UIKit.rich("[color=#d9d1c2]%s[/color]" % w.desc, 14))
		if w.type == "orb":
			d.add_child(UIKit.label("You have %d" % GameState.orb_count(w.id), 13, Color(0.38, 0.65, 0.98)))
		var afford := GameState.can_afford(w.price)
		d.add_child(UIKit.label("Costs " + _plain_price(w.price), 14, Color(1.0, 0.88, 0.35) if afford else Color(0.95, 0.45, 0.40), true))
		var buy := UIKit.button("🛒 Buy" if afford else "🛒 Buy (not enough orbs)", Color(0.22, 0.16, 0.08), Color(0.95, 0.80, 0.30), Vector2(0, 48), 16)
		buy.disabled = not afford
		buy.pressed.connect(func():
			_buy(w)
			if _wares().any(func(x): return x.id == w.id):  # a learnt recipe leaves the wares
				_show_ware_tip(w, at)
			else:
				menu.item_tip().close())
		d.add_child(buy)
		d.add_child(UIKit.label("Or drag it into your bag.", 12, UIKit.TEXT_DIM)))


## A bag item tapped: its card (compared with what you wear), what it sells for, and Sell.
func on_item_tapped(it: ItemInstance) -> void:
	_ware = {}
	if not player.inventory.has(it):
		menu.show_item_tip(it)
		return
	menu.show_item_tip(it, func(d: VBoxContainer):
		d.add_child(UIKit.label("Sells for " + Currency.reward_text(Currency.sell_value(it)), 14, Color(1.0, 0.88, 0.35), true))
		var sell := UIKit.button("💰 Sell", Color(0.22, 0.16, 0.08), Color(0.95, 0.80, 0.30), Vector2(0, 48), 16)
		sell.pressed.connect(func():
			menu.item_tip().close()
			_sell(it))
		d.add_child(sell))


func _buy(w: Dictionary) -> void:
	if w.is_empty():
		return
	var ok := false
	match w.get("type", ""):
		"recipe": ok = GameState.buy_recipe(w.id)
		"orb": ok = GameState.buy_orb(w.id)
		"flask": ok = GameState.buy_flask(w.id, w.price)
		"skillgem": ok = GameState.buy_skill_gem(w.id)
		"scroll": ok = GameState.buy_scroll()
	var why := "Not enough orbs!" if not GameState.can_afford(w.price) else "No room in your bag!"
	if w.get("type", "") == "scroll" and GameState.tp_scrolls >= GameState.MAX_SCROLLS:
		why = "You carry all the scrolls you can (%d)." % GameState.MAX_SCROLLS
	menu.feedback(("Bought %s!" % w.name) if ok else why)
	menu.refresh()


func _plain_price(price: Dictionary) -> String:
	var parts: Array[String] = []
	for id in price:
		parts.append("%d %s" % [int(price[id]), Currency.orb_name(id)])
	return ", ".join(PackedStringArray(parts))
