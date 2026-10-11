class_name SmithPanel
extends MenuPanel
## Blacksmith: Recipes (forge new items) and Plans (forge Legendary and Set items from plans
## collected from rift bosses), paid for in orbs. Currency is used on items at the stash.
## Pick the item to work on by tapping it in the character panel on the right.

var _sub := "recipes"


func panel_title() -> String:
	return "🔨 Blacksmith"


func refresh() -> void:
	UIKit.clear(self)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	for t in [["recipes", "📜 Recipes"], ["plans", "✦ Plans"]]:
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
		"recipes": _build_recipes()
		"plans": _build_plans()


func _build_recipes() -> void:
	var sec := UIKit.section(self, "FORGE RECIPES")
	var any := false
	for id in CraftingDB.RECIPES:
		if not GameState.knows_recipe(id) or CraftingDB.is_plan(id):
			continue
		any = true
		var r: Dictionary = CraftingDB.RECIPES[id]
		var can: bool = GameState.can_afford(r.cost)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		sec.add_child(row)
		var icon := TextureRect.new()
		icon.texture = IconFactory.recipe_icon(id)
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var info := UIKit.rich("[b]%s[/b]  [color=#999999]%s[/color]\n%s" % [r.name, r.desc, Currency.price_text(r.cost)], 14)
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
	add_child(UIKit.rich("Forge a plan as often as you like, for better rolls: %s" % _orbs_held(["chaos"]), 14))
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
	txt += Currency.price_text(r.cost) if knows else "[color=#666666]Not found yet[/color]"
	var info := UIKit.rich(txt, 14)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	if knows:
		var b := UIKit.button("Forge", col.darkened(0.75), col, Vector2(90, 46), 16)
		b.disabled = not GameState.can_afford(r.cost)
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


## "you have 12 Chaos Orb" for the orbs named.
func _orbs_held(ids: Array) -> String:
	var parts: Array[String] = []
	for id in ids:
		parts.append("you have %d %s" % [GameState.orb_count(id), Currency.orb_name(id)])
	return ", ".join(PackedStringArray(parts))
