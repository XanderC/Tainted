class_name HirelingPanel
extends MenuPanel
## Your hireling's page (the inventory's Hireling tab, or tap its portrait), laid out like your
## equipment screen and made to fit without scrolling: its paperdoll (drag gear and flasks from your
## bag onto its slots, and back) and, where your bag is, its skill gems with the support gems you
## link to them (at the stash, where the shared supports show below). Its skill gems came with it.
## The Stats button swaps to its level, stats and attributes, where you add the points each level
## brings. Item cards are touch tooltips (ItemTip).

const GEM_CELL := Vector2(46, 46)
const SKILL_CELL := Vector2(48, 48)
const POOL_COLS := 4

var _sel_slot := ""  ## its gear tapped to inspect
var _item_tip: ItemTip = null
var _stats_mode := false  ## showing its stats instead of its gear


func panel_title() -> String:
	return "🛡 Hireling"


func _ready() -> void:
	visibility_changed.connect(func():
		if not visible and _item_tip != null and is_instance_valid(_item_tip):
			_item_tip.close())


func refresh() -> void:
	UIKit.clear(self)
	add_theme_constant_override("separation", 6)
	if not Hirelings.has():
		_add_bar()
		add_child(UIKit.rich("[center][color=#665c4f]\n\n◈ NO HIRELING ◈\n\nCaptain Rourke in Ashfall has fighters for hire. One follows you, fights beside you, levels up with you and wears gear you give it.[/color][/center]", 16))
		return
	_add_bar()
	if _stats_mode:
		_add_stats()
		return
	_add_gear()
	# Where your bag is on your own screen: its skills, and at the stash the shared supports beside them
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_add_skills(row)
	if GameState.gem_station:
		_add_pool(row)


## The one row over the page: back to where you were, and the swap between its gear and its stats.
func _add_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var back := UIKit.button("⬅ Back", Color(0.14, 0.11, 0.10), Color(0.70, 0.55, 0.35), Vector2(100, 40), 15)
	back.pressed.connect(func(): menu.back())
	bar.add_child(back)
	var who := UIKit.label("", 15, UIKit.GOLD)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if Hirelings.has() and not Hirelings.alive():
		who.text = "☠ %s has fallen: revive at Captain Rourke" % String(GameState.hireling.get("name", ""))
		who.add_theme_color_override("font_color", Color(0.95, 0.45, 0.40))
	bar.add_child(who)
	if not Hirelings.has():
		return
	var pts := Hirelings.attr_points()
	var label := "🛡 Gear" if _stats_mode else ("📜 Stats +%d" % pts if pts > 0 else "📜 Stats")
	var swap := UIKit.button(label, Color(0.16, 0.12, 0.10), Color(0.75, 0.58, 0.30), Vector2(130, 40), 15)
	if pts > 0 and not _stats_mode:
		swap.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	swap.tooltip_text = "Its gear and skills" if _stats_mode else "Its level, stats and attributes"
	swap.pressed.connect(func():
		_stats_mode = not _stats_mode
		if _item_tip != null and is_instance_valid(_item_tip):
			_item_tip.close()
		refresh())
	bar.add_child(swap)


## Its stats page: who it is, its level and experience, its combat stats, and its attributes with a
## + to add the points each level brings (taken back for free in town).
func _add_stats() -> void:
	var lvl := Hirelings.level()
	var sec := UIKit.section(self, "")
	sec.add_child(UIKit.label("%s   •   Level %d" % [Hirelings.title(), lvl], 20, UIKit.GOLD))
	var xp_txt := "Experience %d / %d" % [int(GameState.hireling.get("xp", 0.0)), int(GameState.xp_to_next(lvl))]
	if lvl >= GameState.level:
		xp_txt += "  (at your level: it levels when you do)"
	sec.add_child(UIKit.label(xp_txt, 13, Color(0.38, 0.65, 0.98)))
	sec.add_child(UIKit.label(String(Hirelings.type_def().desc), 13, UIKit.TEXT_DIM, true))
	var st: StatBlock = Hirelings.node.stats if is_instance_valid(Hirelings.node) else Hirelings.build_stats()
	var hp := (Hirelings.node.hp if is_instance_valid(Hirelings.node) else st.get_stat("max_life")) if Hirelings.alive() else 0.0
	sec.add_child(UIKit.rich(("[color=#bdb6aa]Life[/color] [b]%d / %d[/b]   [color=#bdb6aa]Damage[/color] [b]%.0f[/b]   " +
		"[color=#bdb6aa]Attack Speed[/color] [b]%.2f[/b]   [color=#bdb6aa]Armour[/color] [b]%d[/b]   [color=#bdb6aa]Crit[/color] [b]%.0f%%[/b]\n" +
		"[color=#bdb6aa]Skill gems[/color] [b]level %d[/b]   [color=#bdb6aa]Support links[/color] [b]%d[/b]") % [
		int(hp), int(st.get_stat("max_life")), st.get_stat("damage"), st.get_stat("attack_speed"),
		int(st.get_stat("armor")), st.get_stat("crit_chance") * 100.0, Hirelings.skill_rank(), Hirelings.links()], 14))

	var pts := Hirelings.attr_points()
	var asec := UIKit.section(self, "")
	var head := HBoxContainer.new()
	asec.add_child(head)
	var t := UIKit.label("ATTRIBUTES", 17, Color(0.79, 0.65, 0.36))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.label("%d point%s to add" % [pts, "" if pts == 1 else "s"], 15, Color(1.0, 0.85, 0.35) if pts > 0 else UIKit.TEXT_DIM))
	var base := HirelingDB.base_attributes(Hirelings.type_id())
	var have := Hirelings.attributes()
	var added: Dictionary = GameState.hireling.get("attributes", {})
	for k in HirelingDB.ATTR_KEYS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		asec.add_child(line)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(col)
		col.add_child(UIKit.label(Attributes.NAMES[k], 16, Attributes.COLORS[k]))
		col.add_child(UIKit.label(Attributes.bonus_text(k), 12, UIKit.TEXT_DIM, true))
		var val := UIKit.label("%d" % int(have[k]), 18, Color(0.95, 0.90, 0.77))
		val.tooltip_text = "%d to start + %d added" % [int(base.get(k, 0)), int(added.get(k, 0))]
		val.custom_minimum_size = Vector2(44, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(val)
		var plus := UIKit.button("+", Color(0.18, 0.14, 0.08), Color(0.95, 0.80, 0.40), Vector2(40, 40), 20)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.disabled = pts <= 0
		plus.pressed.connect(func():
			Hirelings.add_attribute(k)
			menu.refresh())
		line.add_child(plus)
	asec.add_child(UIKit.label("Its gear needs these, like yours. Each level brings %d points." % Attributes.POINTS_PER_LEVEL, 12, UIKit.TEXT_DIM, true))
	if Hirelings.attribute_points_spent() > 0:
		if not player.can_fight:  # in town
			var reset := UIKit.button("↺ Take back its attribute points (free in town)", Color(0.14, 0.11, 0.10),
				Color(0.70, 0.55, 0.35), Vector2(0, 40), 14)
			reset.pressed.connect(func():
				Hirelings.reset_attributes()
				menu.refresh())
			asec.add_child(reset)
		else:
			asec.add_child(UIKit.label("Its attribute points can be taken back for free in town.", 12, UIKit.TEXT_DIM, true))


## Its paperdoll, laid out like yours (CharacterPanel): the slots its kind has take gear from your
## bag (drag it back to take it off); the ones it hasn't are locked. Its two flasks sit under the belt.
func _add_gear() -> void:
	var doll := Control.new()
	doll.custom_minimum_size = CharacterPanel.doll_size()
	doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(doll)
	var own: Array = Hirelings.type_def().slots
	for slot in CharacterPanel.DOLL:
		var r := CharacterPanel.doll_rect(slot)
		var cell := _gear_cell(slot, r.size) if slot in own else _locked_cell(slot, r.size)
		cell.position = r.position
		doll.add_child(cell)
	for i in Hirelings.FLASK_SLOTS:
		var cell := _flask_cell(i)
		cell.position = _flask_rect(i).position
		doll.add_child(cell)


## Its flask slot i: two in the flask row, centred under the belt.
func _flask_rect(i: int) -> Rect2:
	var u := CharacterPanel.DOLL_U
	var gap := CharacterPanel.DOLL_GAP.y
	var belt := CharacterPanel.doll_rect("belt")
	var row_w := Hirelings.FLASK_SLOTS * u + (Hirelings.FLASK_SLOTS - 1) * gap
	var top := CharacterPanel.flask_rect(0).position.y
	return Rect2(belt.get_center().x - row_w * 0.5 + i * (u + gap), top, u, u * 2.0)


## A slot its kind doesn't have (a Sellsword wears no rings): shown, but locked.
func _locked_cell(slot: String, cell_size: Vector2) -> DragSlot:
	var cell := DragSlot.new(cell_size)
	var tname := String(Hirelings.type_def().name)
	cell.setup(null, Color(0.16, 0.14, 0.17), Color(0.05, 0.05, 0.06), 0, "🔒",
		"A %s has no %s slot" % [tname, String(UIKit.SLOT_NAMES.get(slot, slot)).to_lower()])
	cell.modulate = Color(1, 1, 1, 0.5)
	return cell


func _flask_cell(i: int) -> DragSlot:
	var it := Hirelings.flask(i)
	var cell := UIKit.item_cell(it, false, _flask_rect(i).size)
	if it == null:
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0, "🧪", "Its flask %d: drag a life or utility flask here from your bag.\nIt drinks a life flask below half its life, a utility flask as soon as it is fighting." % (i + 1))
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
	return cell


func _gear_cell(slot: String, cell_size: Vector2) -> DragSlot:
	var it: ItemInstance = GameState.hireling_gear.get(slot)
	var cell := UIKit.item_cell(it, it != null and _sel_slot == slot, cell_size)
	if it == null:
		# A one-unit slot shows its icon; a bigger one its name (as on your paperdoll)
		var cap: String = UIKit.SLOT_NAMES.get(slot, slot) if cell_size.x > CharacterPanel.DOLL_U else UIKit.SLOT_ICONS.get(slot, "")
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0, cap,
			"%s: drag gear here from your bag" % UIKit.SLOT_NAMES.get(slot, slot))
	else:
		cell.payload = {"kind": "item", "from": "hireling", "slot": slot, "item": it}
		cell.clicked.connect(func():
			_sel_slot = slot
			refresh()
			_show_gear_tip(slot))
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
	return cell


## Item cards here are tooltips (ItemTip), made for touch: tap its gear, or an item in your bag,
## and the card pops up beside your finger until you tap elsewhere.
func _tip() -> ItemTip:
	if _item_tip == null or not is_instance_valid(_item_tip):
		_item_tip = ItemTip.new()
		menu._root.add_child(_item_tip)  # over both halves; hidden with the menu
	return _item_tip


func _tap_point() -> Vector2:
	return get_viewport().get_mouse_position()


## Its gear's card, with Take it back.
func _show_gear_tip(slot: String) -> void:
	var it: ItemInstance = GameState.hireling_gear.get(slot)
	if it == null:
		return
	_tip().show_card(it, _tap_point(), Hirelings.attributes(), func(parent: VBoxContainer):
		parent.add_child(UIKit.label("Worn by %s" % String(GameState.hireling.get("name", "")), 13, UIKit.GOLD))
		var take := UIKit.button("⬇ Take it back", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 44), 15)
		take.disabled = not player.can_fit(it)
		take.pressed.connect(func():
			_tip().close()
			if Hirelings.unequip(player, slot):
				_sel_slot = ""
			menu.refresh())
		parent.add_child(take))


## An item in your bag tapped: its card, judged for your hireling (can it wear it, and where).
func on_item_tapped(sel: ItemInstance) -> void:
	if not Hirelings.has() or not player.bag.has(sel):
		return
	_tip().show_card(sel, _tap_point(), Hirelings.attributes(), func(parent: VBoxContainer):
		var slot := sel.base.slot
		var why := Hirelings.flask_block_reason(sel) if sel.is_flask() else Hirelings.slot_block_reason(sel, slot)
		var where := "a flask slot" if sel.is_flask() else "its %s slot" % String(UIKit.SLOT_NAMES.get(slot, slot)).to_lower()
		parent.add_child(UIKit.label(("✔ %s can use this: drag it onto %s." % [String(GameState.hireling.get("name", "")), where]) if why == ""
			else "⛔ " + why, 13, Color(0.45, 0.95, 0.55) if why == "" else Color(0.95, 0.45, 0.40), true)))


## Its skill gems (main attack first), each with its support links.
func _add_skills(parent: Control) -> void:
	var links := Hirelings.links()
	var nxt := 0 if links >= GameState.MAX_LINKS else links * 5
	var title := "SKILLS  —  %d support link%s" % [links, "" if links == 1 else "s"]
	if nxt > 0:
		title += " (next at its level %d)" % nxt
	if not GameState.gem_station:
		title += "  •  🔒 link supports at the stash"
	var sec := UIKit.section(parent, title)
	sec.add_theme_constant_override("separation", 4)
	(sec.get_child(0) as Label).add_theme_font_size_override("font_size", 14)
	sec.tooltip_text = "Its skill gems came with it and level as it does (level %d now). Link your support gems to them at the stash." % Hirelings.skill_rank()
	var ids := Hirelings.skill_ids()
	for i in ids.size():
		sec.add_child(_skill_row(i, links))


func _skill_row(i: int, links: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var sk := Hirelings.skill_def(i)
	var cell := DragSlot.new(SKILL_CELL)
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
func _add_pool(parent: Control) -> void:
	var sec := UIKit.section(parent, "SHARED SUPPORTS")
	(sec.get_child(0) as Label).add_theme_font_size_override("font_size", 14)
	sec.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_END
	# As tall as its skills: more supports than fit scroll inside it, not the page
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(POOL_COLS * (GEM_CELL.x + 5.0) + 14.0, 3 * (SKILL_CELL.y + 4.0))
	sec.add_child(scroll)
	var grid := UIKit.grid(POOL_COLS)
	scroll.add_child(grid)
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
