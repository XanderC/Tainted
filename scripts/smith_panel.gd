class_name SmithPanel
extends MenuPanel
## Blacksmith: Orbs (modify the selected item), Salvage, Recipes (forge new items) and Plans
## (forge Legendary and Set items from plans collected from rift bosses).
## Pick the item to work on by tapping it in the character panel on the right.

var _sub := "orbs"


func panel_title() -> String:
	return "🔨 Blacksmith"


func refresh() -> void:
	UIKit.clear(self)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	for t in [["orbs", "🔮 Orbs"], ["salvage", "🔨 Salvage"], ["recipes", "📜 Recipes"], ["plans", "✦ Plans"]]:
		var active: bool = _sub == t[0]
		var b := UIKit.button(t[1], Color(0.24, 0.18, 0.10) if active else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.82, 0.40) if active else Color(0.35, 0.28, 0.20), Vector2(0, 40), 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = t[0]
		b.pressed.connect(func():
			_sub = id
			refresh()
		)
		tabs.add_child(b)
	match _sub:
		"orbs": _build_orbs()
		"salvage": _build_salvage()
		"recipes": _build_recipes()
		"plans": _build_plans()


func _need_item() -> bool:
	if menu.selected == null:
		add_child(UIKit.rich("[center][color=#665c4f]\n◈ SELECT AN ITEM ◈\n\nTap an item in your bag or equipment on the right.[/color][/center]", 16))
		return false
	UIKit.item_card(self, menu.selected)
	return true


func _build_orbs() -> void:
	if not _need_item():
		return
	add_child(orb_grid(menu, player, menu.selected, false))


## Grid of item orbs to apply to `item` (also used by the inventory's Item panel, where only
## owned orbs are shown: `owned_only`). Tap an orb to use it.
static func orb_grid(m: GameMenu, p: Player, it: ItemInstance, owned_only: bool) -> VBoxContainer:
	var holder := VBoxContainer.new()
	var sec := UIKit.section(holder, "APPLY CURRENCY")
	var grid := UIKit.grid(6, 6)
	sec.add_child(grid)
	var shown := 0
	for id in CraftingDB.ORB_ORDER:
		if Crafting.NOT_ITEM_ORBS.has(id):
			continue
		var count := GameState.orb_count(id)
		if owned_only and count <= 0:
			continue
		shown += 1
		var o: Dictionary = CraftingDB.ORBS[id]
		var reason: String = Crafting.orb_block_reason(it, id)
		var can := count > 0 and reason == ""
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 70)
		b.icon = CraftingDB.orb_icon(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = "x%d" % count
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "%s\n%s%s" % [o.name, o.desc, ("\n" + reason) if reason != "" else ""]
		b.disabled = not can
		b.add_theme_stylebox_override("normal", UIKit.box(Color(0.12, 0.10, 0.15), o.color if can else Color(0.3, 0.3, 0.3), 2 if can else 1, 6))
		b.pressed.connect(func():
			var res := Crafting.apply_orb(p, it, id)
			m.feedback(res.msg)
			m.refresh()
		)
		grid.add_child(b)
	if shown == 0:
		sec.add_child(UIKit.label("You have no orbs that work on items.", 13, UIKit.TEXT_DIM))
	else:
		sec.add_child(UIKit.label("Hold or hover an orb to see what it does.", 12, UIKit.TEXT_DIM))
	return holder


func _build_salvage() -> void:
	if menu.selected != null and player.inventory.has(menu.selected):
		var it := menu.selected
		UIKit.item_card(self, it)
		add_child(UIKit.label("Yield: %s" % CraftingDB.salvage_preview(it), 14, Color(0.85, 0.65, 0.40), true))
		var b := UIKit.button("🔨 Salvage This Item", Color(0.22, 0.14, 0.08), Color(0.85, 0.55, 0.25), Vector2(0, 52), 18)
		b.pressed.connect(func():
			var g := Crafting.salvage(player, it)
			menu.selected = null
			menu.feedback("Salvaged materials!" if not g.is_empty() else "Failed to salvage.")
			menu.refresh()
		)
		add_child(b)
	else:
		add_child(UIKit.label("Tap an item in your bag to salvage it into materials.", 14, UIKit.TEXT_DIM, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for r in [ItemInstance.Rarity.NORMAL, ItemInstance.Rarity.MAGIC]:
		var bb := UIKit.button("🔨 Salvage All %s" % ItemInstance.Rarity.keys()[r].capitalize(),
			Color(0.13, 0.12, 0.16), Color(0.50, 0.48, 0.55), Vector2(0, 44), 14)
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.pressed.connect(func():
			Crafting.salvage_all(player, r)
			menu.selected = null
			menu.refresh()
		)
		row.add_child(bb)


func _build_recipes() -> void:
	var sec := UIKit.section(self, "FORGE RECIPES")
	var any := false
	for id in CraftingDB.RECIPES:
		if not GameState.knows_recipe(id) or CraftingDB.is_plan(id):
			continue
		any = true
		var r: Dictionary = CraftingDB.RECIPES[id]
		var can: bool = GameState.can_afford_materials(r.cost)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		sec.add_child(row)
		var icon := TextureRect.new()
		icon.texture = IconFactory.recipe_icon(id)
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var info := UIKit.rich("[b]%s[/b]  [color=#999999]%s[/color]\n%s" % [r.name, r.desc, CraftingDB.cost_text(r.cost, GameState.materials)], 14)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := UIKit.button("Forge", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(90, 46), 16)
		b.disabled = not can
		b.pressed.connect(func():
			var res := Crafting.craft(player, id)
			menu.feedback(res.msg)
			menu.refresh()
		)
		row.add_child(b)
	if not any:
		sec.add_child(UIKit.label("You don't know any recipes yet.", 14, UIKit.TEXT_DIM))


## Every Legendary and Set plan: known ones can be forged (again and again, for better rolls);
## unknown ones are shown greyed out so you know what is still out there to find.
func _build_plans() -> void:
	var mats := ""
	for k in ["soul", "core", "essence", "dust"]:
		mats += "[color=#%s]%s %d[/color]     " % [CraftingDB.MATERIALS[k].color.to_html(false),
			CraftingDB.MATERIALS[k].name, GameState.material_count(k)]
	add_child(UIKit.rich(mats, 14))
	for group in [[false, "LEGENDARY PLANS"], [true, "SET PLANS"]]:
		var ids := CraftingDB.plan_ids(group[0])
		var known := ids.filter(func(id): return GameState.knows_recipe(id)).size()
		var sec := UIKit.section(self, "%s  —  %d / %d found" % [group[1], known, ids.size()])
		for id in ids:
			sec.add_child(_plan_row(id))
	add_child(UIKit.label("Plans drop from rift bosses: better odds in higher rift levels and fast clears. " +
		"Forgotten Souls come from bosses and from salvaging Legendary and Set items.", 12, UIKit.TEXT_DIM, true))


func _plan_row(id: String) -> HBoxContainer:
	var r: Dictionary = CraftingDB.RECIPES[id]
	var knows := GameState.knows_recipe(id)
	var col := CraftingDB.recipe_color(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var base := LootGenerator.base_by_id(String(UniqueItems.info_of(r.result.id).base))
	var icon := TextureRect.new()
	icon.texture = base.icon if base != null else IconFactory.recipe_icon(id)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not knows:
		icon.modulate = Color(0.3, 0.3, 0.3)
	row.add_child(icon)
	var txt := "[b][color=#%s]%s[/color][/b]  [color=#999999]%s[/color]\n" % [
		(col if knows else Color(0.45, 0.45, 0.45)).to_html(false), r.name, r.desc]
	txt += CraftingDB.cost_text(r.cost, GameState.materials) if knows else "[color=#666666]Not found yet[/color]"
	var info := UIKit.rich(txt, 14)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	if knows:
		var b := UIKit.button("Forge", col.darkened(0.75), col, Vector2(90, 46), 16)
		b.disabled = not GameState.can_afford_materials(r.cost)
		b.pressed.connect(func():
			var res := Crafting.craft(player, id)
			menu.feedback(res.msg)
			if res.get("item") != null:
				menu.select(res.item)
			else:
				menu.refresh()
		)
		row.add_child(b)
	return row
