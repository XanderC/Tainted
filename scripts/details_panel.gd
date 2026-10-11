class_name DetailsPanel
extends MenuPanel
## Default inventory panel: the selected item's card side by side with what is worn in that
## slot (green/red arrows per stat), the stat changes, and Equip / Drop actions. Selling and
## currency happen in town: the Merchant and the stash.


func panel_title() -> String:
	return "⚔ Item"


func refresh() -> void:
	UIKit.clear(self)
	var it := menu.selected
	if it == null:
		var hint := UIKit.rich("[center][color=#665c4f]\n\n◈ NO ITEM SELECTED ◈\n\nTap an item in your bag or equipment to inspect and compare it.\n\n" +
			"Drag items to rearrange your bag, onto an equipment slot to equip, or back into the bag to unequip.[/color][/center]", 16)
		add_child(hint)
		return

	var worn_now := player.is_worn(it)
	# Flasks give nothing while worn, so there is nothing to compare
	var worn: ItemInstance = null if worn_now or it.is_flask() else player.equipment.get(player.equip_slot_for(it))

	if worn != null:
		var deltas := UIKit.equip_deltas(player, it)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		UIKit.item_card(_column(row, "SELECTED"), it, true, deltas)
		UIKit.item_card(_column(row, "EQUIPPED"), worn, true, deltas)
	else:
		UIKit.item_card(self, it)

	if not worn_now and not it.is_flask():
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

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	add_child(acts)
	if worn_now:
		var unequip := UIKit.button("⬇ Unequip", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 52), 18)
		unequip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unequip.disabled = not player.can_fit(it)  # needs a space its shape fits
		unequip.pressed.connect(func():
			if player.flasks.has(it):
				player.unequip_flask(player.flasks.find(it))
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
			if it.is_flask():
				# The first open, empty flask slot; with none, it swaps with the first flask
				var fi := player.free_flask_slot()
				if not player.equip_flask(it, fi if fi != -1 else 0):
					menu.feedback("No room in the bag for the flask it replaces.")
			else:
				player.equip_from_bag(it)
			menu.refresh()
		)
		acts.add_child(equip)
		var drop := UIKit.button("🗑 Drop", Color(0.20, 0.08, 0.08), Color(0.70, 0.25, 0.25), Vector2(100, 52), 17)
		drop.pressed.connect(func():
			player.drop_item(it)
			menu.select(null)
		)
		acts.add_child(drop)

	# Currency is used at the stash, selling and salvaging at the Merchant
	add_child(UIKit.label("💰 Use currency on this item from the stash's Currency tab in town. Sell it at the Merchant.", 13, UIKit.TEXT_DIM, true))


func _column(row: HBoxContainer, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var l := UIKit.label(title, 12, Color(0.60, 0.55, 0.48))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return col


