class_name GemsPanel
extends MenuPanel
## Gems: tap an item in the character panel to open its sockets here, then drag gems from the
## pouch (the inventory's Gems tab) into them, or back to the pouch to remove them. When opened at the Jeweler
## (`jeweler = true`) it also combines GemDef.COMBINE_COUNT gems into the next tier for orbs.


var jeweler := false
var _combine_gem := ""
var _sel_gem := ""  # gem tapped in the Gems tab or in a socket: its details card is shown


func panel_title() -> String:
	if jeweler:
		return "💎 Jeweler"
	var total := 0
	for g in GameState.gems:
		total += int(GameState.gems[g])
	return "💎 Gems (%d)" % total


func refresh() -> void:
	UIKit.clear(self)
	_add_sockets()
	_add_gem_details()
	add_child(UIKit.label("Drag gems in from the Gems tab of your inventory (and back to take them out).", 13, UIKit.TEXT_DIM, true))
	if jeweler:
		_add_combine()


# ---------- sockets of the selected item ----------

func _add_sockets() -> void:
	var it := menu.selected
	var sec := UIKit.section(self, "SOCKETS")
	if it == null:
		sec.add_child(UIKit.label("Tap an item in your bag or equipment to open its sockets.", 14, UIKit.TEXT_DIM, true))
		return
	sec.add_child(UIKit.label("%s%s" % [it.display_name, "   (equipped)" if player.equipment.values().has(it) else ""],
		16, ItemInstance.RARITY_COLORS[it.rarity], true))
	if it.sockets <= 0:
		sec.add_child(UIKit.label("This item has no sockets. Magic and Rare items roll more of them.", 14, UIKit.TEXT_DIM, true))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	sec.add_child(row)
	for i in it.sockets:
		row.add_child(_socket_cell(it, i))
	if jeweler and not it.gems.is_empty():
		var rm := UIKit.button("Remove All Gems", Color(0.28, 0.12, 0.12), Color(0.95, 0.45, 0.45), Vector2(0, 44), 15)
		rm.pressed.connect(func():
			var n := 0
			while not it.gems.is_empty() and GameState.unsocket_gem(it, it.gems.size() - 1):
				n += 1
			menu.feedback("Removed %d gem(s)." % n)
			menu.refresh()
		)
		sec.add_child(rm)
	# What the gems currently add
	var lines := ""
	for gid in it.gems:
		var g := GemDef.info(gid)
		lines += "[color=#%s]◆ %s[/color]  [color=#888888](%s)[/color]\n" % [Color(g.color).to_html(false), g.text, g.name]
	if lines != "":
		sec.add_child(UIKit.rich(lines, 14))


func _socket_cell(it: ItemInstance, i: int) -> DragSlot:
	var cell := DragSlot.new(Vector2(62, 62))
	if i < it.gems.size():
		var gid: String = it.gems[i]
		var g := GemDef.info(gid)
		cell.setup(GemDef.icon(gid), Color.WHITE if gid == _sel_gem else g.color, Color(g.color).darkened(0.82), 0, "",
			UIKit.gem_tip(gid) + "\n(drag back to the pouch to remove)")
		cell.payload = {"kind": "gem", "from": "socket", "idx": i, "item": it}
		cell.clicked.connect(func():
			_sel_gem = gid
			menu.refresh()
		)
	else:
		cell.setup(null, Color(0.45, 0.50, 0.70), Color(0.06, 0.06, 0.10), 0, "◇", "Empty socket - drop a gem here")
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "gem" and d.get("from", "") == "pouch"
	cell.on_drop = func(d: Dictionary) -> void:
		var gid: String = d.get("gem_id", "")
		if GameState.socket_gem(it, i, gid):
			menu.feedback("Socketed %s." % GemDef.info(gid).get("name", gid))
		menu.refresh()
	return cell


# ---------- details of the tapped gem ----------

## Card for the selected gem: its effect, tier, the next tier, how many you own, and what it would
## add to the item whose sockets are open.
func _add_gem_details() -> void:
	var g := GemDef.info(_sel_gem)
	if g.is_empty():
		return
	var card := PanelContainer.new()
	var sb := UIKit.box(Color(g.color).darkened(0.85), g.color, 2, 10)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = GemDef.icon(_sel_gem)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	row.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UIKit.label(String(g.name).to_upper(), 18, Color(g.color).lightened(0.25))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UIKit.button("✕", Color(0.12, 0.10, 0.14), Color(0.45, 0.40, 0.40), Vector2(40, 34), 15)
	close.pressed.connect(func():
		_sel_gem = ""
		menu.refresh()
	)
	head.add_child(close)
	var t := "[color=#%s][b]%s[/b][/color]   [color=#888888]Tier %d / %d  •  You own %d[/color]\n" % [
		Color(g.color).to_html(false), g.text, int(g.tier), GemDef.MAX_TIER, GameState.gem_count(_sel_gem)]
	var it := menu.selected
	if it != null and it.sockets > 0:
		var free: int = it.sockets - it.gems.size()
		if free > 0:
			t += "[color=#4ade80]Socketing it adds %s to %s[/color]%s\n" % [g.text, it.display_name,
				" (you're wearing it)" if player.equipment.values().has(it) else ""]
		else:
			t += "[color=#f59e0b]%s has no free socket: drop it on a socket to swap gems.[/color]\n" % it.display_name
	elif it == null:
		t += "[color=#9ca3af]Tap an item to open its sockets, then drag this gem onto one.[/color]\n"
	if int(g.tier) < GemDef.MAX_TIER:
		var nxt := GemDef.info(GemDef.make_id(String(g.type), int(g.tier) + 1))
		t += "[color=#888888]Next tier: %s gives %s (combine %d at the Jeweler)[/color]" % [nxt.name, nxt.text, GemDef.COMBINE_COUNT]
	else:
		t += "[color=#888888]The highest tier.[/color]"
	v.add_child(UIKit.rich(t, 14))


# ---------- pouch (shown in the inventory's Gems tab, see CharacterPanel) ----------

## Owned item gems, in catalogue order.
static func owned_gems() -> Array[String]:
	var owned: Array[String] = []
	for gid in GemDef.all_ids():
		if GameState.gem_count(gid) > 0:
			owned.append(gid)
	return owned


## One pouch cell (gid "" = empty). Drag a gem onto a socket in the Gems panel; dropping a
## socketed gem here takes it out. Tapping a gem picks it for the Jeweler's combine.
static func pouch_cell(m: GameMenu, gid: String, sz: Vector2) -> DragSlot:
	var cell := DragSlot.new(sz)
	if gid != "":
		var g := GemDef.info(gid)
		var gp_now := m.current_panel() as GemsPanel
		var sel := gp_now != null and gp_now._sel_gem == gid
		cell.setup(GemDef.icon(gid), Color.WHITE if sel else g.color, Color(g.color).darkened(0.82), GameState.gem_count(gid), "", UIKit.gem_tip(gid))
		cell.payload = {"kind": "gem", "from": "pouch", "gem_id": gid}
		cell.clicked.connect(func():
			var gp := m.current_panel() as GemsPanel
			if gp == null:
				m.show_panel("gems")
				gp = m.current_panel() as GemsPanel
			gp._sel_gem = gid
			gp._combine_gem = gid
			m.refresh()
		)
	else:
		cell.setup(null, UIKit.EMPTY_BORDER)
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "gem" and d.get("from", "") == "socket"
	cell.on_drop = func(d: Dictionary) -> void:
		if GameState.unsocket_gem(d.get("item"), int(d.get("idx", -1))):
			m.feedback("Gem returned to your pouch.")
		m.refresh()
	return cell


# ---------- jeweler: combine ----------

func _add_combine() -> void:
	var sec := UIKit.section(self, "COMBINE GEMS  —  %d of a gem make 1 of the next tier" % GemDef.COMBINE_COUNT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	sec.add_child(row)

	var g := GemDef.info(_combine_gem)
	if g.is_empty() or GameState.gem_count(_combine_gem) <= 0:
		_combine_gem = ""
		g = {}

	var in_cell := DragSlot.new(Vector2(64, 64))
	if g.is_empty():
		in_cell.setup(null, Color(0.45, 0.55, 0.85), Color(0.06, 0.06, 0.10), 0, "◇", "Drop or tap a gem")
	else:
		in_cell.setup(GemDef.icon(_combine_gem), g.color, Color(g.color).darkened(0.82), GameState.gem_count(_combine_gem), "", UIKit.gem_tip(_combine_gem))
	in_cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "gem" and d.get("from", "") == "pouch"
	in_cell.on_drop = func(d: Dictionary) -> void:
		_combine_gem = d.get("gem_id", "")
		refresh()
	row.add_child(in_cell)
	row.add_child(UIKit.label("➜", 28, Color.WHITE))

	var out_cell := DragSlot.new(Vector2(64, 64))
	var info := UIKit.label("Drop a gem here (or tap one in your Gems tab) to see what it becomes.", 14, UIKit.TEXT_DIM, true)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var can := false
	if g.is_empty():
		out_cell.setup(null, Color(0.25, 0.25, 0.32))
	elif g.tier >= GemDef.MAX_TIER:
		out_cell.setup(null, Color(0.25, 0.25, 0.32))
		info.text = "%s is already the highest tier." % g.name
	else:
		var up := GemDef.make_id(g.type, g.tier + 1)
		var ug := GemDef.info(up)
		var cost := GemDef.combine_cost(g.tier)
		var have := GameState.gem_count(_combine_gem)
		can = have >= GemDef.COMBINE_COUNT and GameState.can_afford(cost)
		out_cell.setup(GemDef.icon(up), ug.color, Color(ug.color).darkened(0.82), 0, "", UIKit.gem_tip(up))
		var cost_txt := ", ".join(PackedStringArray(cost.keys().map(func(k): return "%d %s" % [int(cost[k]), Currency.orb_name(k)])))
		info.text = "%d × %s ➜ 1 %s (%s)\nHave %d  •  %s each" % [GemDef.COMBINE_COUNT, g.name, ug.name, ug.text, have, cost_txt]
		info.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0) if can else Color(0.95, 0.55, 0.50))
	row.add_child(out_cell)
	row.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	sec.add_child(btns)
	for times in [1, 0]:
		var b := UIKit.button("Combine" if times == 1 else "Combine All",
			Color(0.15, 0.30, 0.20) if times == 1 else Color(0.15, 0.22, 0.32),
			Color(0.40, 1.0, 0.55) if times == 1 else Color(0.45, 0.65, 1.0), Vector2(0, 48), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not can
		b.pressed.connect(func():
			var made := GameState.combine_gems(_combine_gem, times)
			var nxt := GemDef.info(GemDef.make_id(g.type, g.tier + 1))
			menu.feedback("Created %d %s!" % [made, nxt.get("name", "")] if made > 0 else "Not enough gems or orbs.")
			menu.refresh()
		)
		btns.add_child(b)
