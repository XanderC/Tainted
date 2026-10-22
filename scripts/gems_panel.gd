class_name GemsPanel
extends MenuPanel
## Gems: socket gems (and runes) are the account's, in the shared stash, so they go in and out of
## sockets only at the stash or the Jeweler (GameState.gem_station), where the shared gems show here:
## drag one onto any item with a free socket, worn or in the bag (CharacterPanel takes the drop), or
## onto a socket of the item tapped. Tap an item to see its sockets here, and drag a socketed gem back
## onto the shared gems to take it out. Elsewhere the sockets are view-only. At the Jeweler
## (`jeweler = true`) it also combines GemDef.COMBINE_COUNT gems into the next tier for orbs.
## Tapping a gem (or rune) pops up its card where it was tapped (the menu's ItemTip).


var jeweler := false
## Shown inside another panel (the stash's Gems tab): tapping a gem doesn't switch panels.
var embedded := false
var _combine_gem := ""
var _sel_gem := ""  # gem tapped in the Gems tab or in a socket (outlined; its card pops up)


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
	if GameState.gem_station:
		add_child(UIKit.label("Drag a gem or rune onto any item with a free socket, worn or in your bag. Tap an item to see its sockets; drag a gem from a socket back here to take it out.", 13, UIKit.TEXT_DIM, true))
		_add_pool()
	else:
		add_child(UIKit.label("🔒 Socket gems at the stash or the Jeweler in town.", 13, UIKit.TEXT_DIM, true))
	if jeweler:
		_add_combine()


# ---------- sockets of the selected item ----------

func _add_sockets() -> void:
	var it := menu.selected
	var sec := UIKit.section(self, "SOCKETS")
	if it == null:
		sec.add_child(UIKit.label("Tap an item in your bag or equipment to see its sockets.", 14, UIKit.TEXT_DIM, true))
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
	if it.is_runeword():
		sec.add_child(UIKit.label("The runes of a runeword are set for good: they can't be taken out or swapped.",
			13, Color(0.78, 0.70, 0.47), true))
	elif jeweler and not it.gems.is_empty():
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
	var lines := Runewords.card_bbcode(it)
	var why := Runewords.why_not(it)
	if why != "":
		lines += "[color=#f59e0b]⚠ %s[/color]\n" % why
	for gid in it.gems:
		var g := it.socket_info(gid)
		lines += "[color=#%s]◆ %s[/color]  [color=#888888](%s)[/color]\n" % [Color(g.color).to_html(false), g.text, g.name]
	if lines != "":
		sec.add_child(UIKit.rich(lines, 14))


func _socket_cell(it: ItemInstance, i: int) -> DragSlot:
	var cell := DragSlot.new(Vector2(62, 62))
	if i < it.gems.size():
		var gid: String = it.gems[i]
		var g := GemDef.info(gid)
		cell.setup(GemDef.icon(gid), Color.WHITE if gid == _sel_gem else g.color, Color(g.color).darkened(0.82))
		cell.payload = {"kind": "gem", "from": "socket", "idx": i, "item": it}
		cell.clicked.connect(func():
			_sel_gem = gid
			menu.refresh()
			show_gem_tip(gid, "Set in the runeword for good." if it.is_runeword() else "Drag it back onto the shared gems to take it out.")
		)
	else:
		cell.setup(null, Color(0.45, 0.50, 0.70), Color(0.06, 0.06, 0.10), 0, "◇", "Empty socket - drop a gem here")
	if not GameState.gem_station or it.is_runeword():
		cell.payload = {}  # view-only away from the stash and the Jeweler, and a runeword's runes are set
		return cell
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "gem" and d.get("from", "") == "pouch"
	cell.on_drop = func(d: Dictionary) -> void:
		socket_into(menu, it, i, String(d.get("gem_id", "")))
	return cell


## Puts gem `gid` into socket `idx` of `it` (past the filled ones: the next free one) and says how it
## went: socketed, a runeword formed, or why the runes don't make one yet. (Also for gems dropped
## straight onto an item in the character panel.)
static func socket_into(m: GameMenu, it: ItemInstance, idx: int, gid: String) -> void:
	var was := it.runeword_id
	if GameState.socket_gem(it, idx, gid):
		if it.is_runeword() and it.runeword_id != was:
			m.feedback("The runes awaken: %s! Its runes are now set for good." % it.display_name)
		elif Runewords.why_not(it) != "":
			m.feedback(Runewords.why_not(it))
		else:
			m.feedback("Socketed %s into %s." % [GemDef.info(gid).get("name", gid), it.display_name])
	m.refresh()


# ---------- the tapped gem's card ----------

## Pops up `gid`'s card where it was tapped; `note` (optional) is a line under it.
func show_gem_tip(gid: String, note := "") -> void:
	if GemDef.info(gid).is_empty():
		return
	menu.item_tip().show_content(get_viewport().get_mouse_position(), func(d: VBoxContainer):
		_gem_card(d, gid)
		if note != "":
			d.add_child(UIKit.label(note, 12, UIKit.TEXT_DIM, true)))


## A gem's card: its effect, tier, the next tier, how many you own, what it would add to the item
## whose sockets are open, and for a rune the runewords it is part of.
func _gem_card(v: VBoxContainer, gid: String) -> void:
	var g := GemDef.info(gid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var icon := TextureRect.new()
	icon.texture = GemDef.icon(gid)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var title := UIKit.label(String(g.name).to_upper(), 18, Color(g.color).lightened(0.25), true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.x = 200  # clear of the close button
	head.add_child(title)
	var is_rune: bool = g.get("rune", false)
	var t := "[color=#%s][b]%s[/b][/color]\n[color=#888888]%s  •  You own %d[/color]\n" % [
		Color(g.color).to_html(false), g.text,
		"Rune %d / %d" % [int(g.tier), SocketRune.LADDER.size()] if is_rune else "Tier %d / %d" % [int(g.tier), GemDef.MAX_TIER],
		GameState.gem_count(gid)]
	var it := menu.selected
	if it != null and it.sockets > 0:
		var free: int = it.sockets - it.gems.size()
		var adds: String = it.socket_info(gid).get("text", g.text)
		if free > 0:
			t += "[color=#4ade80]Socketing it adds %s to %s[/color]%s\n" % [adds, it.display_name,
				" (you're wearing it)" if player.equipment.values().has(it) else ""]
		else:
			t += "[color=#f59e0b]%s has no free socket: drop it on a socket to swap gems.[/color]\n" % it.display_name
	elif it == null:
		t += "[color=#9ca3af]Drag it onto an item with a free socket, worn or in your bag.[/color]\n"
	var nxt_id := GemDef.next_id(gid)
	if nxt_id != "":
		var nxt := GemDef.info(nxt_id)
		t += "[color=#888888]Next: %s gives %s (combine %d at the Jeweler)[/color]" % [nxt.name, nxt.text, GemDef.combine_count_of(gid)]
	else:
		t += "[color=#888888]The highest %s.[/color]" % ("rune" if is_rune else "tier")
	if is_rune:
		# Runewords it is part of: fill a Normal item's sockets with exactly these runes, in order
		var rws := Runewords.using_rune(gid)
		if not rws.is_empty():
			t += "\n[color=#c7b377]Runewords (Normal item, exactly that many sockets, runes in order):[/color]"
			for rw in rws:
				t += "\n[color=#c7b377]• %s[/color]" % Runewords.recipe_text(rw)
	v.add_child(UIKit.rich(t, 14))


# ---------- the shared gems (at the stash or the Jeweler) ----------

const POOL_COLS := 8


func _add_pool() -> void:
	var sec := UIKit.section(self, "SHARED SOCKET GEMS")
	var grid := UIKit.grid(POOL_COLS)
	sec.add_child(grid)
	var ids := owned_gems()
	var total := maxi(POOL_COLS, int(ceil(float(ids.size() + 1) / POOL_COLS)) * POOL_COLS)
	for i in total:
		grid.add_child(pouch_cell(menu, ids[i] if i < ids.size() else "", Vector2(54, 54), self))

## Owned item gems, in catalogue order.
static func owned_gems() -> Array[String]:
	var owned: Array[String] = []
	for gid in GemDef.all_ids():
		if GameState.gem_count(gid) > 0:
			owned.append(gid)
	return owned


## One pouch cell (gid "" = empty). Drag a gem onto a socket in the Gems panel; dropping a
## socketed gem here takes it out. Tapping a gem picks it for the Jeweler's combine.
static func pouch_cell(m: GameMenu, gid: String, sz: Vector2, owner: GemsPanel = null) -> DragSlot:
	var cell := DragSlot.new(sz)
	if gid != "":
		var g := GemDef.info(gid)
		var gp_now := owner if owner != null else m.current_panel() as GemsPanel
		var sel := gp_now != null and gp_now._sel_gem == gid
		cell.setup(GemDef.icon(gid), Color.WHITE if sel else g.color, Color(g.color).darkened(0.82), GameState.gem_count(gid))
		cell.payload = {"kind": "gem", "from": "pouch", "gem_id": gid}
		cell.clicked.connect(func():
			var gp := owner if owner != null else m.current_panel() as GemsPanel
			if gp == null:
				m.show_panel("gems")
				gp = m.current_panel() as GemsPanel
			gp._sel_gem = gid
			gp._combine_gem = gid
			m.refresh()
			gp.show_gem_tip(gid)
		)
	else:
		cell.setup(null, UIKit.EMPTY_BORDER)
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "gem" and d.get("from", "") == "socket"
	cell.on_drop = func(d: Dictionary) -> void:
		if GameState.unsocket_gem(d.get("item"), int(d.get("idx", -1))):
			m.feedback("Gem returned to the shared gems.")
		m.refresh()
	return cell


# ---------- jeweler: combine ----------

func _add_combine() -> void:
	var sec := UIKit.section(self, "COMBINE GEMS & RUNES  —  %d of a gem (or low rune) make 1 of the next" % GemDef.COMBINE_COUNT)
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
		in_cell.setup(GemDef.icon(_combine_gem), g.color, Color(g.color).darkened(0.82), GameState.gem_count(_combine_gem))
		var cg := _combine_gem
		in_cell.clicked.connect(func(): show_gem_tip(cg))
	in_cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "gem" and d.get("from", "") == "pouch"
	in_cell.on_drop = func(d: Dictionary) -> void:
		_combine_gem = d.get("gem_id", "")
		refresh()
	row.add_child(in_cell)
	row.add_child(UIKit.label("➜", 28, Color.WHITE))

	var out_cell := DragSlot.new(Vector2(64, 64))
	var info := UIKit.label("Drop a gem here (or tap one in the shared gems) to see what it becomes.", 14, UIKit.TEXT_DIM, true)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var can := false
	var up := GemDef.next_id(_combine_gem) if not g.is_empty() else ""
	if g.is_empty():
		out_cell.setup(null, Color(0.25, 0.25, 0.32))
	elif up == "":
		out_cell.setup(null, Color(0.25, 0.25, 0.32))
		info.text = "%s is already the highest." % g.name
	else:
		var ug := GemDef.info(up)
		var need := GemDef.combine_count_of(_combine_gem)
		var cost := GemDef.combine_cost_of(_combine_gem)
		var have := GameState.gem_count(_combine_gem)
		can = have >= need and GameState.can_afford(cost)
		out_cell.setup(GemDef.icon(up), ug.color, Color(ug.color).darkened(0.82))
		out_cell.clicked.connect(func(): show_gem_tip(up))
		var cost_txt := ", ".join(PackedStringArray(cost.keys().map(func(k): return "%d %s" % [int(cost[k]), Currency.orb_name(k)])))
		info.text = "%d × %s ➜ 1 %s (%s)\nHave %d  •  %s each" % [need, g.name, ug.name, ug.text, have, cost_txt]
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
			var nxt := GemDef.info(up)
			menu.feedback("Created %d %s!" % [made, nxt.get("name", "")] if made > 0 else "Not enough gems or orbs.")
			menu.refresh()
		)
		btns.add_child(b)
