class_name DetailsPanel
extends MenuPanel
## Default inventory panel: the selected item's card side by side with what is worn in that
## slot (green/red arrows per stat), the stat changes, Equip / Salvage / Drop actions, and the
## orbs you own to use on it.

var _pending_salvage: ItemInstance = null


func panel_title() -> String:
	return "⚔ Item"


func refresh() -> void:
	UIKit.clear(self)
	var it := menu.selected
	if it == null:
		_pending_salvage = null
		var hint := UIKit.rich("[center][color=#665c4f]\n\n◈ NO ITEM SELECTED ◈\n\nTap an item in your bag or equipment to inspect and compare it.\n\n" +
			"Drag items to rearrange your bag, onto an equipment slot to equip, or back into the bag to unequip.[/color][/center]", 16)
		add_child(hint)
		_add_bulk_salvage()
		return

	var worn_now := player.equipment.values().has(it)
	var worn: ItemInstance = null if worn_now else player.equipment.get(player.equip_slot_for(it))

	if worn != null:
		var deltas := UIKit.equip_deltas(player, it)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		UIKit.item_card(_column(row, "SELECTED"), it, true, deltas)
		UIKit.item_card(_column(row, "EQUIPPED"), worn, true, deltas)
	else:
		UIKit.item_card(self, it)

	if _pending_salvage == it:
		_add_salvage_warning(it)
		return

	if not worn_now:
		if player.is_better_in_slot(it):
			var up := PanelContainer.new()
			var usb := UIKit.box(Color(0.10, 0.22, 0.14, 0.95), Color(0.35, 1.0, 0.50), 1, 6)
			usb.set_content_margin_all(8)
			up.add_theme_stylebox_override("panel", usb)
			var ul := UIKit.label("🔺 BETTER IN SLOT UPGRADE!", 14, Color(0.40, 1.0, 0.60))
			ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			up.add_child(ul)
			add_child(up)
		var cmp := UIKit.section(self, "EQUIPPING THIS ITEM:")
		cmp.add_child(UIKit.rich(UIKit.delta_bbcode(player, it)))
		var sal := UIKit.label("🔨 Salvage yield: %s" % CraftingDB.salvage_preview(it), 13, Color(0.85, 0.65, 0.40), true)
		add_child(sal)

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	add_child(acts)
	if worn_now:
		var unequip := UIKit.button("⬇ Unequip", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 52), 18)
		unequip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unequip.disabled = not player.can_fit(it)  # needs a space its shape fits
		unequip.pressed.connect(func():
			for s in player.equipment.keys():
				if player.equipment[s] == it:
					player.unequip(s)
			menu.refresh()
		)
		acts.add_child(unequip)
		if unequip.disabled:
			add_child(UIKit.label("⚠ Bag full! Free a slot to unequip.", 14, Color(0.95, 0.40, 0.40)))
	else:
		var equip := UIKit.button("⚔ Equip", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 52), 18)
		equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var reason := player.equip_block_reason(it)
		if reason != "":
			equip.disabled = true
			add_child(UIKit.label("⛔ " + reason, 15, Color(0.95, 0.40, 0.40)))
		elif it.base.two_handed and player.equipment.has("offhand"):
			add_child(UIKit.label("Two-handed: your off-hand item goes back to the bag.", 13, UIKit.TEXT_DIM, true))
		equip.pressed.connect(func():
			player.equip_from_bag(it)
			menu.refresh()
		)
		acts.add_child(equip)
		var salvage := UIKit.button("🔨 Salvage", Color(0.22, 0.14, 0.08), Color(0.85, 0.55, 0.25), Vector2(0, 52), 17)
		salvage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		salvage.pressed.connect(func():
			if player.is_better_in_slot(it):
				_pending_salvage = it
				refresh()
			else:
				_salvage(it)
		)
		acts.add_child(salvage)
		var drop := UIKit.button("🗑 Drop", Color(0.20, 0.08, 0.08), Color(0.70, 0.25, 0.25), Vector2(100, 52), 17)
		drop.pressed.connect(func():
			player.drop_item(it)
			menu.select(null)
		)
		acts.add_child(drop)

	# Orbs work anywhere, as in Path of Exile (the Blacksmith shows every orb, this only owned ones)
	add_child(SmithPanel.orb_grid(menu, player, it, true))
	_add_bulk_salvage()


func _column(row: HBoxContainer, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var l := UIKit.label(title, 12, Color(0.60, 0.55, 0.48))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return col


func _add_salvage_warning(it: ItemInstance) -> void:
	var w := UIKit.section(self, "⚠ UPGRADE WARNING")
	w.add_child(UIKit.rich("[b]%s[/b] is [color=#4ade80]better[/color] than what you are wearing.\n%s\n[color=#f87171]Salvage it anyway?[/color]" % [
		it.display_name, player.get_upgrade_summary(it)], 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	w.add_child(row)
	var eq := UIKit.button("⚡ Equip Instead", Color(0.12, 0.28, 0.16), Color(0.35, 1.0, 0.50))
	eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.pressed.connect(func():
		_pending_salvage = null
		player.equip_with_overflow(it)
		menu.refresh()
	)
	row.add_child(eq)
	var sv := UIKit.button("🔨 Salvage Anyway", Color(0.25, 0.10, 0.10), Color(0.95, 0.40, 0.40))
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.pressed.connect(func():
		_pending_salvage = null
		_salvage(it)
	)
	row.add_child(sv)
	var cancel := UIKit.button("Cancel", Color(0.14, 0.14, 0.18), Color(0.5, 0.5, 0.55), Vector2(90, 46))
	cancel.pressed.connect(func():
		_pending_salvage = null
		refresh()
	)
	row.add_child(cancel)


func _add_bulk_salvage() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for r in [ItemInstance.Rarity.NORMAL, ItemInstance.Rarity.MAGIC]:
		var b := UIKit.button("🔨 Salvage All %s" % ItemInstance.Rarity.keys()[r].capitalize(),
			Color(0.13, 0.12, 0.16), Color(0.50, 0.48, 0.55), Vector2(0, 42), 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_bulk_salvage.bind(r))
		row.add_child(b)


func _salvage(it: ItemInstance) -> void:
	var gain := Crafting.salvage(player, it)
	menu.selected = null
	menu.feedback("Salvaged %s: %s" % [it.display_name, _gain_text(gain)])
	menu.refresh()


## Salvages every item of `rarity` in the bag, except ones that would be upgrades.
func _bulk_salvage(rarity: int) -> void:
	var total := {}
	var n := 0
	var kept := 0
	for it in player.inventory.duplicate():
		if it == null or it.rarity != rarity:
			continue
		if player.is_better_in_slot(it):
			kept += 1
			continue
		var g := Crafting.salvage(player, it)
		n += 1
		for k in g:
			total[k] = int(total.get(k, 0)) + int(g[k])
	menu.selected = null
	var msg := "Salvaged %d item(s): %s" % [n, _gain_text(total)] if n > 0 else "Nothing to salvage."
	if kept > 0:
		msg += " (kept %d upgrade%s)" % [kept, "" if kept == 1 else "s"]
	menu.feedback(msg)
	menu.refresh()


func _gain_text(gain: Dictionary) -> String:
	var parts: Array[String] = []
	for k in gain:
		parts.append("+%d %s" % [gain[k], CraftingDB.MATERIALS.get(k, {}).get("name", k)])
	return ", ".join(PackedStringArray(parts))
