class_name ShopPanel
extends MenuPanel
## Merchant: an icon grid of wares priced in orbs (there is no gold: orbs are the money, as in
## Path of Exile), including a currency exchange of cheaper orbs for better ones. Selling pays
## in orbs and shards (Currency.sell_value). Drag a ware onto your bag to buy it, drag a bag
## item onto the merchant grid to sell it. Tap a ware or bag item for a Buy / Sell strip.

const COLS := 8
const CELL := Vector2(58, 58)

var _ware := {}  # selected ware


func panel_title() -> String:
	return "🛒 Merchant"


func refresh() -> void:
	UIKit.clear(self)
	var sec := UIKit.section(self, "MERCHANT'S WARES")
	var grid := UIKit.grid(COLS)
	sec.add_child(grid)
	var wares := _wares()
	for w in wares:
		grid.add_child(_ware_cell(w))
	# Spare cells so there is always room to drop items to sell
	var spare := COLS - (wares.size() % COLS) + COLS
	for i in spare:
		var cell := DragSlot.new(CELL)
		cell.setup(null, UIKit.EMPTY_BORDER)
		cell.can_accept = _accepts_sell
		cell.on_drop = _sell_dropped
		grid.add_child(cell)
	_add_trade_strip()


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
			"desc": "%s (needs level %d)" % [sk.description, SkillTree.gem_level_req(sk.id)],
			"price": SkillTree.gem_price(sk.id), "color": sk.color, "icon": IconFactory.gem_icon("skill:" + sk.id, sk.color, 3)})
	# Normal flasks of every base; find or craft better ones
	for b in LootGenerator.bases:
		if b.slot != "flask":
			continue
		var f := ItemInstance.new()
		f.base = b
		list.append({"type": "flask", "id": b.id, "name": b.display_name,
			"desc": "%s, cooldown %.0fs. Never runs out." % [f.flask_text(player.class_def.power_name), float(b.flask.cooldown)],
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
	for id in CraftingDB.MATERIALS:
		var m: Dictionary = CraftingDB.MATERIALS[id]
		if m.has("bundle"):
			list.append({"type": "material", "id": id, "name": "%d %s" % [int(m.bundle[0]), m.name], "desc": "Crafting material",
				"price": m.bundle[1], "color": m.color, "icon": IconFactory.material_icon(id, m.color)})
	return list


func _ware_cell(w: Dictionary) -> DragSlot:
	var cell := DragSlot.new(CELL)
	var afford := GameState.can_afford(w.price)
	var sel: bool = _ware.get("id", "") == w.id
	var border: Color = Color.WHITE if sel else (Color(w.color) if afford else Color(0.30, 0.28, 0.32))
	cell.setup(w.icon, border, Color(0.11, 0.10, 0.14), 0, "", "%s\n%s\nCosts %s" % [w.name, w.desc, _plain_price(w.price)])
	if not afford:
		cell.modulate = Color(1, 1, 1, 0.5)
	var tag := UIKit.label(Currency.price_tag(w.price), 10, Color(1.0, 0.88, 0.35) if afford else Color(0.9, 0.4, 0.4))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 4)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(tag)
	cell.payload = {"kind": "ware", "ware": w}
	cell.clicked.connect(func():
		_ware = w
		menu.selected = null
		menu.refresh()
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


func _buy(w: Dictionary) -> void:
	if w.is_empty():
		return
	var ok := false
	match w.get("type", ""):
		"recipe": ok = GameState.buy_recipe(w.id)
		"orb": ok = GameState.buy_orb(w.id)
		"material": ok = GameState.buy_material(w.id)
		"flask": ok = GameState.buy_flask(w.id, w.price)
		"skillgem": ok = GameState.buy_skill_gem(w.id)
	var why := "Not enough orbs!" if not GameState.can_afford(w.price) else "No room in your bag!"
	menu.feedback(("Bought %s!" % w.name) if ok else why)
	menu.refresh()


## One line: what is selected, its price, and a Buy / Sell button.
func _add_trade_strip() -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	add_child(strip)
	var info := UIKit.label("", 15, Color.WHITE, true)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(info)
	var btn := UIKit.button("", Color(0.22, 0.16, 0.08), Color(0.95, 0.80, 0.30), Vector2(170, 52), 18)
	strip.add_child(btn)
	var it := menu.selected
	if it != null and player.inventory.has(it):
		_ware = {}
		info.text = it.display_name
		info.add_theme_color_override("font_color", ItemInstance.RARITY_COLORS[it.rarity])
		btn.text = "💰 Sell"
		info.text = "%s  ➜  %s" % [it.display_name, Currency.reward_text(Currency.sell_value(it))]
		btn.pressed.connect(_sell.bind(it))
	elif not _ware.is_empty():
		info.text = "%s — %s" % [_ware.name, _ware.desc]
		info.add_theme_color_override("font_color", _ware.color)
		info.text += "\nCosts " + _plain_price(_ware.price)
		btn.text = "🛒 Buy"
		btn.disabled = not GameState.can_afford(_ware.price)
		btn.pressed.connect(_buy.bind(_ware))
	else:
		info.text = "Drag wares into your bag to buy. Drag bag items onto the merchant to sell. Tap anything to inspect."
		info.add_theme_color_override("font_color", UIKit.TEXT_DIM)
		btn.visible = false

	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 8)
	add_child(bulk)
	for r in [ItemInstance.Rarity.NORMAL, ItemInstance.Rarity.MAGIC]:
		var b := UIKit.button("Sell All %s" % ItemInstance.Rarity.keys()[r].capitalize(),
			Color(0.13, 0.12, 0.16), Color(0.50, 0.48, 0.55), Vector2(0, 42), 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not player.inventory.any(func(x): return x != null and x.rarity == r)
		b.pressed.connect(func():
			var total := {"orbs": {}, "shards": {}}
			for x in player.inventory.duplicate():
				if x != null and x.rarity == r:
					var got := GameState.sell_item(x)
					for key in ["orbs", "shards"]:
						for k in got.get(key, {}):
							total[key][k] = int(total[key].get(k, 0)) + int(got[key][k])
			menu.selected = null
			menu.feedback("Sold items: %s" % Currency.reward_text(total))
			menu.refresh()
		)
		bulk.add_child(b)


func _plain_price(price: Dictionary) -> String:
	var parts: Array[String] = []
	for id in price:
		parts.append("%d %s" % [int(price[id]), Currency.orb_name(id)])
	return ", ".join(PackedStringArray(parts))
