class_name HirelingPanel
extends MenuPanel
## The inventory's Hireling tab: your hireling's level, stats and attributes, its gear (drag gear
## from your bag onto its slots, and back), and its skill gems with the support gems you link to
## them. Its skill gems came with it and can't be changed; supports can, at the stash (like your
## own), where the shared support gems show below its skills.

const SLOT_CELL := 74.0
const GEM_CELL := Vector2(52, 52)
const POOL_COLS := 8

var _sel_slot := ""  ## its gear tapped to inspect


func panel_title() -> String:
	return "🛡 Hireling"


func refresh() -> void:
	UIKit.clear(self)
	if not Hirelings.has():
		add_child(UIKit.rich("[center][color=#665c4f]\n\n◈ NO HIRELING ◈\n\nCaptain Rourke in Ashfall has fighters for hire. One follows you, fights beside you, levels up with you and wears gear you give it.[/color][/center]", 16))
		return
	_add_header()
	_add_gear()
	_add_inspect()
	_add_skills()
	if GameState.gem_station:
		_add_pool()


func _add_header() -> void:
	var t := Hirelings.type_def()
	var lvl := Hirelings.level()
	var sec := UIKit.section(self, "")
	var top := HBoxContainer.new()
	sec.add_child(top)
	var name_l := UIKit.label("%s  •  Level %d" % [Hirelings.title(), lvl], 19, UIKit.GOLD)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	if not Hirelings.alive():
		top.add_child(UIKit.label("☠ Fallen: revive at Captain Rourke", 15, Color(0.95, 0.45, 0.40)))
	var need := GameState.xp_to_next(lvl)
	var xp_txt := "XP %d / %d" % [int(GameState.hireling.get("xp", 0.0)), int(need)]
	if lvl >= GameState.level:
		xp_txt += "  (at your level: it levels when you do)"
	sec.add_child(UIKit.label(xp_txt, 13, Color(0.38, 0.65, 0.98)))
	var st: StatBlock = Hirelings.node.stats if is_instance_valid(Hirelings.node) else Hirelings.build_stats()
	var hp := (Hirelings.node.hp if is_instance_valid(Hirelings.node) else st.get_stat("max_life")) if Hirelings.alive() else 0.0
	sec.add_child(UIKit.rich(("[color=#bdb6aa]Life[/color] [b]%d / %d[/b]   [color=#bdb6aa]Damage[/color] [b]%.0f[/b]   " +
		"[color=#bdb6aa]Attack Speed[/color] [b]%.2f[/b]   [color=#bdb6aa]Armour[/color] [b]%d[/b]   [color=#bdb6aa]Crit[/color] [b]%.0f%%[/b]") % [
		int(hp), int(st.get_stat("max_life")), st.get_stat("damage"), st.get_stat("attack_speed"),
		int(st.get_stat("armor")), st.get_stat("crit_chance") * 100.0], 14))
	var a := Hirelings.attributes()
	var parts: Array[String] = []
	for k in Attributes.KEYS:
		parts.append("[color=#%s]%s %d[/color]" % [Color(Attributes.COLORS[k]).to_html(false), Attributes.SHORT[k], int(a[k])])
	sec.add_child(UIKit.rich("   ".join(PackedStringArray(parts)) + "   [color=#8a7f6e](grow as it levels; its gear needs them)[/color]", 13))
	sec.add_child(UIKit.label(String(t.desc), 13, UIKit.TEXT_DIM, true))


## Its gear slots in a row: drop gear from your bag on them; drag theirs back to your bag.
func _add_gear() -> void:
	var sec := UIKit.section(self, "GEAR  —  drag from your bag onto a slot, and back")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	sec.add_child(row)
	for slot in Hirelings.type_def().slots:
		row.add_child(_gear_cell(String(slot)))
	# Its own flasks, beside its gear: it drinks them itself, so yours are left for you
	var sep := VSeparator.new()
	row.add_child(sep)
	for i in Hirelings.FLASK_SLOTS:
		row.add_child(_flask_cell(i))
	sec.add_child(UIKit.label("Flasks: it drinks a life flask when below half its life, and a utility flask (Granite, Quicksilver, Silver, Sulphur) as soon as it is fighting.",
		12, UIKit.TEXT_DIM, true))


func _flask_cell(i: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var it := Hirelings.flask(i)
	var cell := UIKit.item_cell(it, false, Vector2(SLOT_CELL * 0.6, SLOT_CELL * 1.2))
	if it == null:
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0, "🧪", "Flask %d: drag a life or utility flask here from your bag" % (i + 1))
	else:
		cell.payload = {"kind": "item", "from": "hireling_flask", "idx": i, "item": it}
		cell.tooltip_text = "%s\n%s" % [it.display_name, it.flask_text()]
	cell.can_accept = func(d: Dictionary) -> bool:
		var di: ItemInstance = d.get("item")
		return d.get("kind", "") == "item" and d.get("from", "") == "bag" and di != null and di.is_flask()
	cell.on_drop = func(d: Dictionary) -> void:
		var di: ItemInstance = d.get("item")
		var why := Hirelings.flask_block_reason(di)
		if why != "":
			menu.feedback(why)
		elif not Hirelings.equip_flask_from_bag(player, di, i):
			menu.feedback("Not enough bag space for the flask it has there.")
		elif menu.selected == di:
			menu.selected = null
		menu.refresh()
	col.add_child(cell)
	var cap := UIKit.label("Flask %d" % (i + 1), 11, UIKit.TEXT_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return col


func _gear_cell(slot: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var tall := slot in ["weapon", "offhand", "chest"]
	var it: ItemInstance = GameState.hireling_gear.get(slot)
	var cell := UIKit.item_cell(it, it != null and _sel_slot == slot, Vector2(SLOT_CELL, SLOT_CELL * (1.5 if tall else 1.0)))
	if it == null:
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0, UIKit.SLOT_ICONS.get(slot, ""),
			"%s: drag gear here from your bag" % UIKit.SLOT_NAMES.get(slot, slot))
	else:
		cell.payload = {"kind": "item", "from": "hireling", "slot": slot, "item": it}
		cell.clicked.connect(func():
			_sel_slot = "" if _sel_slot == slot else slot
			refresh())
		if not Hirelings.gear_active(it):
			cell.modulate = Color(1.0, 0.45, 0.45)
			cell.tooltip_text = "%s\n%s: gives nothing until it levels up enough" % [it.display_name,
				Attributes.block_reason(it.base, Hirelings.attributes(), "it has")]
	cell.can_accept = func(d: Dictionary) -> bool:
		var di: ItemInstance = d.get("item")
		return d.get("kind", "") == "item" and d.get("from", "") == "bag" and di != null
	cell.on_drop = func(d: Dictionary) -> void:
		var di: ItemInstance = d.get("item")
		var why := Hirelings.slot_block_reason(di, slot)
		if why != "":
			menu.feedback(why)
		elif not Hirelings.equip_from_bag(player, di, slot):
			menu.feedback("Not enough bag space for what it is wearing there.")
		else:
			_sel_slot = slot
			if menu.selected == di:
				menu.selected = null
		menu.refresh()
	col.add_child(cell)
	var cap := UIKit.label(String(UIKit.SLOT_NAMES.get(slot, slot)), 11, UIKit.TEXT_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return col


## Its tapped gear's card, or the bag item you have selected judged for it.
func _add_inspect() -> void:
	var it: ItemInstance = GameState.hireling_gear.get(_sel_slot) if _sel_slot != "" else null
	var bag_item := menu.selected if menu.selected != null and player.bag.has(menu.selected) else null
	if it == null and bag_item == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var have := Hirelings.attributes()
	if bag_item != null:
		var c := _column(row, "IN YOUR BAG")
		UIKit.item_card(c, bag_item, true, {}, have)
		var slot := bag_item.base.slot
		var why := Hirelings.slot_block_reason(bag_item, slot)
		c.add_child(UIKit.label(("✔ It can wear this: drag it onto its %s slot." % String(UIKit.SLOT_NAMES.get(slot, slot)).to_lower()) if why == ""
			else "⛔ " + why, 13, Color(0.45, 0.95, 0.55) if why == "" else Color(0.95, 0.45, 0.40), true))
	if it != null:
		var c2 := _column(row, "IT IS WEARING")
		UIKit.item_card(c2, it, true, {}, have)
		var take := UIKit.button("⬇ Take it back", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 44), 15)
		take.disabled = not player.can_fit(it)
		take.pressed.connect(func():
			if Hirelings.unequip(player, _sel_slot):
				_sel_slot = ""
			menu.refresh())
		c2.add_child(take)


func _column(row: HBoxContainer, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(UIKit.label(title, 13, UIKit.GOLD))
	return col


## Its skill gems (main attack first), each with its support links.
func _add_skills() -> void:
	var links := Hirelings.links()
	var nxt := 0 if links >= GameState.MAX_LINKS else links * 5
	var title := "SKILLS  —  %d support link%s" % [links, "" if links == 1 else "s"]
	if nxt > 0:
		title += " (next at its level %d)" % nxt
	var sec := UIKit.section(self, title)
	var ids := Hirelings.skill_ids()
	for i in ids.size():
		sec.add_child(_skill_row(i, links))
	sec.add_child(UIKit.label(("Its skill gems came with it and level as it does (level %d now). Drag support gems from below onto its links." if GameState.gem_station
		else "Its skill gems came with it and level as it does (level %d now). 🔒 Link support gems to them at the stash in town.") % Hirelings.skill_rank(),
		12, UIKit.TEXT_DIM, true))


func _skill_row(i: int, links: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var sk := Hirelings.skill_def(i)
	var cell := DragSlot.new(Vector2(56, 56))
	if sk != null:
		cell.setup(IconFactory.gem_icon("skill:" + sk.id, sk.color, 3), sk.color, Color(sk.color).darkened(0.85), 0, "",
			"%s (Lv %d)\n%s" % [sk.get_effective_name(), Hirelings.skill_rank(), sk.description])
	row.add_child(cell)
	var name_l := UIKit.label(("⚔ " if i == 0 else "") + (sk.get_effective_name() if sk != null else "?"), 14,
		sk.get_effective_color().lightened(0.2) if sk != null else Color.WHITE)
	name_l.custom_minimum_size = Vector2(130, 0)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_l)
	var sup := Hirelings.supports(i)
	for j in GameState.MAX_LINKS:
		if j < links:
			row.add_child(_support_cell(String(sup[j]) if j < sup.size() else "", i, j))
		else:
			var locked := DragSlot.new(GEM_CELL)
			locked.setup(null, Color(0.18, 0.16, 0.20), Color(0.05, 0.05, 0.06), 0, "🔒", "Opens at its level %d" % (j * 5))
			row.add_child(locked)
	return row


## A support link of its skill i, or (i -1) a support in the shared pool.
func _support_cell(rune_id: String, i: int, idx: int) -> DragSlot:
	var cell := DragSlot.new(GEM_CELL)
	var r := RuneDef.DB.get_rune(rune_id) if rune_id != "" else null
	if r == null:
		cell.setup(null, Color(0.40, 0.36, 0.52), Color(0.06, 0.05, 0.09), 0, "◌" if i >= 0 else "",
			"Empty link: drop a support gem here" if i >= 0 else "")
	else:
		var border := r.rarity_color() if r.rarity > 0 else r.color
		cell.setup(r.get_icon(), border, r.color.darkened(0.8), GameState.rune_count(rune_id) if i < 0 else 0, "",
			"%s (Lv %d)\n%s" % [r.display_name, GameState.support_level(rune_id), r.description])
		if GameState.gem_station:
			cell.payload = {"kind": "rune", "from": "pool" if i < 0 else "hl_link", "slot": i, "idx": idx, "rune_id": rune_id}
	if not GameState.gem_station:
		return cell
	if i >= 0:
		cell.can_accept = func(d: Dictionary) -> bool:
			return d.get("kind", "") == "rune" and d.get("from", "") in ["pool", "hl_link"] \
				and not (d.get("from", "") == "hl_link" and int(d.slot) == i and int(d.idx) == idx)
		cell.on_drop = func(d: Dictionary) -> void:
			var ok: bool
			if d.get("from", "") == "hl_link":
				ok = Hirelings.move_support(int(d.slot), int(d.idx), i, idx)
			else:
				ok = Hirelings.socket_support(i, mini(idx, Hirelings.supports(i).size()), String(d.rune_id))
			if not ok:
				menu.feedback("Can't link that: one elemental support per skill, and no doubles.")
			menu.refresh()
	else:
		_accept_returns(cell)
	return cell


## The shared support gems, at the stash: drag them onto its links, and its links back here.
func _add_pool() -> void:
	var sec := UIKit.section(self, "SHARED SUPPORT GEMS")
	var grid := UIKit.grid(POOL_COLS)
	sec.add_child(grid)
	var ids := SkillGemsPanel.owned_supports()
	var total := maxi(POOL_COLS, int(ceil(float(ids.size() + 1) / POOL_COLS)) * POOL_COLS)
	for k in total:
		if k < ids.size():
			grid.add_child(_support_cell(ids[k], -1, -1))
		else:
			var empty := DragSlot.new(GEM_CELL)
			empty.setup(null, UIKit.EMPTY_BORDER)
			_accept_returns(empty)
			grid.add_child(empty)


func _accept_returns(cell: DragSlot) -> void:
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "rune" and d.get("from", "") == "hl_link"
	cell.on_drop = func(d: Dictionary) -> void:
		Hirelings.unsocket_support(int(d.slot), int(d.idx))
		menu.refresh()
