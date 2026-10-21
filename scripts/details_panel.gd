class_name DetailsPanel
extends MenuPanel
## Default inventory panel: the selected item's card side by side with what is worn in that
## slot (green/red arrows per stat), the stat changes, and Unequip for worn gear (equipping and
## dropping are drag and drop: onto a slot, or the drop box under the boots). Selling and
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
		# Unidentified: comparing would give its hidden modifiers away
		var deltas := UIKit.equip_deltas(player, it) if it.identified else {}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		UIKit.item_card(_column(row, "SELECTED"), it, true, deltas)
		UIKit.item_card(_column(row, "EQUIPPED"), worn, true, deltas)
	else:
		UIKit.item_card(self, it)

	if not worn_now and not it.is_flask() and it.identified:
		if player.is_better_in_slot(it):
			var up := PanelContainer.new()
			var usb := UIKit.inset_box(8, Color(0.6, 1.0, 0.7))
			up.add_theme_stylebox_override("panel", usb)
			var ul := UIKit.label("🔺 BETTER IN SLOT UPGRADE!", 14, Color(0.40, 1.0, 0.60))
			ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			up.add_child(ul)
			add_child(up)
		var cmp := UIKit.section(self, "EQUIPPING THIS ITEM:")
		cmp.add_child(UIKit.rich(UIKit.delta_bbcode(player, it)))

	# Unidentified: a Scroll of Identify works anywhere (the Sage in town does it for free)
	if not it.identified:
		var have := GameState.orb_count("identify")
		var ident := UIKit.button("📜 Identify  (%d scroll%s)" % [have, "" if have == 1 else "s"],
			Color(0.22, 0.19, 0.12), Color(0.93, 0.86, 0.66), Vector2(0, 52), 18)
		ident.disabled = have <= 0
		ident.pressed.connect(func():
			menu.feedback(Crafting.apply_orb(player, it, "identify").msg)
			menu.refresh()
		)
		add_child(ident)
		if have <= 0:
			add_child(UIKit.label("No Scrolls of Identify. Buy them from the Merchant, or the Sage in town identifies everything for free.", 13, UIKit.TEXT_DIM, true))

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
		# Equipping and dropping are drag and drop: onto an equipment (or flask) slot, or onto the
		# drop box under the boots on the paperdoll (CharacterPanel)
		var reason := player.equip_block_reason(it)
		if reason != "":
			add_child(UIKit.label("⛔ " + reason, 15, Color(0.95, 0.40, 0.40)))
		elif it.base.two_handed and player.equipment.has("offhand"):
			add_child(UIKit.label("Two-handed: your off-hand item goes back to the bag.", 13, UIKit.TEXT_DIM, true))
		if reason == "" and it.is_unique():
			for s in player.equipment:
				if player.equipment[s].unique_id == it.unique_id:
					add_child(UIKit.label("You are already wearing one: each %s item can only be worn once, so this can only replace it (%s)." % [
						"Set" if it.rarity == ItemInstance.Rarity.SET else "Legendary", String(UIKit.SLOT_NAMES.get(s, s))],
						14, Color(1.0, 0.70, 0.35), true))
					break
		if Hirelings.has() and not it.is_flask() and Hirelings.slot_block_reason(it, it.base.slot) == "":
			add_child(UIKit.label("🛡 %s can wear this: drag it onto their slot in the Hireling tab." % String(GameState.hireling.get("name", "Your hireling")),
				14, Color(0.55, 0.90, 0.60), true))
		add_child(UIKit.label("Drag it onto %s to equip it, or onto 🗑 Drop (under the boots) to drop it." % (
			"a flask slot" if it.is_flask() else "its equipment slot"), 13, UIKit.TEXT_DIM, true))

	# Currency is used at the stash (Scrolls of Identify anywhere), selling at the Merchant
	add_child(UIKit.label("💰 Use currency on this item at the stash in town (Currency tab). Sell it at the Merchant.", 13, UIKit.TEXT_DIM, true))


func _column(row: HBoxContainer, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var l := UIKit.label(title, 12, Color(0.60, 0.55, 0.48))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return col


