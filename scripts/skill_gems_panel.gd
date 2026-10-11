class_name SkillGemsPanel
extends MenuPanel
## Skill gems, Path of Exile style. Six skill slots (one HUD button each; slot 1 is the main
## attack): each holds a skill gem plus support gems in its links. Links open as you level
## (GameState.links_unlocked). Loose gems live in the inventory's Skill Gems and Supports tabs
## (CharacterPanel, built with pouch_skill_cell / pouch_support_cell). Everything is drag and drop:
##   skill gem tab -> slot (socket it; a gem already there goes back to the tab)
##   slot -> slot (swap the two slots), slot / link -> its inventory tab (take it out)
##   supports tab -> link (link it; replaces what is there), link -> link (move / swap)
## Skill and support gems level up while socketed. Tap any gem to see its details beside the slots.

const CELL := Vector2(56, 56)
const SLOT_CELL := Vector2(60, 60)

var _sel := {}  # {"type": "skill" | "support", "id": String, "slot": int}


func panel_title() -> String:
	return "💠 Skills"


func refresh() -> void:
	UIKit.clear(self)
	var links := GameState.links_unlocked()
	var nxt := GameState.next_link_level()
	var title := "SKILL SLOTS  —  %d support link%s" % [links, "" if links == 1 else "s"]
	if nxt > 0:
		title += "  (next at level %d)" % nxt
	# slots on the left, the tapped gem's details beside them
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	var sec := UIKit.section(top, title)
	sec.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for i in GameState.SKILL_SLOTS:
		sec.add_child(_slot_row(i, links))
	sec.add_child(UIKit.label("Drag gems in from the Skill Gems and Supports tabs of your inventory.", 12, UIKit.TEXT_DIM, true))
	_add_details(top)


# ---------- slots ----------

func _slot_row(i: int, links: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var num := UIKit.label("⚔" if i == 0 else str(i), 16, UIKit.GOLD)
	num.custom_minimum_size = Vector2(22, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.tooltip_text = "Main attack" if i == 0 else "Skill %d" % i
	row.add_child(num)
	row.add_child(_skill_cell(GameState.slot_skill(i), i, SLOT_CELL))
	var chain := UIKit.label("═", 18, Color(0.75, 0.65, 0.45))
	row.add_child(chain)
	var sup := GameState.slot_supports(i)
	for j in GameState.MAX_LINKS:
		if j < links:
			row.add_child(_support_cell(String(sup[j]) if j < sup.size() else "", i, j, CELL))
		else:
			var locked := DragSlot.new(CELL)
			locked.setup(null, Color(0.18, 0.16, 0.20), Color(0.05, 0.05, 0.06), 0, "🔒", "Link opens at level %d" % (j * 5))
			row.add_child(locked)
	return row


## A skill gem cell: in slot `slot` (>= 0) or in the pouch (slot -1). skill_id "" = empty slot.
func _skill_cell(skill_id: String, slot: int, sz: Vector2) -> DragSlot:
	var cell := DragSlot.new(sz)
	var sk := SkillTree.get_skill(skill_id) if skill_id != "" else null
	if sk == null:
		cell.setup(null, Color(0.45, 0.40, 0.30), Color(0.07, 0.06, 0.08), 0, "◇", "Empty skill slot - drop a skill gem here")
	else:
		var sel: bool = _sel.get("type", "") == "skill" and _sel.get("id", "") == skill_id
		var ok := GameState.skill_gem_block_reason(skill_id) == ""
		cell.setup(IconFactory.gem_icon("skill:" + skill_id, sk.color, 3), Color.WHITE if sel else sk.color,
			Color(sk.color).darkened(0.85), GameState.skill_gem_count(skill_id) if slot < 0 else 0, "",
			"%s (Lv %d)" % [sk.display_name, GameState.gem_level(skill_id)])
		if not ok:
			cell.modulate = Color(1, 1, 1, 0.45)
		_overlay(cell, sk.icon, 22, Color.WHITE, VERTICAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
		_overlay(cell, "%d" % GameState.gem_level(skill_id), 11, Color(1.0, 0.9, 0.5), VERTICAL_ALIGNMENT_TOP, HORIZONTAL_ALIGNMENT_LEFT)
		cell.payload = {"kind": "skillgem", "from": "pouch" if slot < 0 else "slot", "slot": slot, "skill": skill_id}
		cell.clicked.connect(_select.bind({"type": "skill", "id": skill_id, "slot": slot}))
	if slot >= 0:
		cell.can_accept = func(d: Dictionary) -> bool:
			return d.get("kind", "") == "skillgem" and not (d.get("from", "") == "slot" and int(d.get("slot", -1)) == slot)
		cell.on_drop = func(d: Dictionary) -> void:
			if d.get("from", "") == "slot":
				GameState.swap_slots(int(d.slot), slot)
			else:
				var why := GameState.skill_gem_block_reason(d.skill)
				if why != "" or not GameState.set_slot_skill(slot, d.skill):
					menu.feedback(why if why != "" else "Can't socket that here.")
			menu.refresh()
	else:
		_accept_returns(cell)
	return cell


## A support gem cell: in link `idx` of slot `slot`, or in the pouch (slot -1). rune_id "" = empty link.
func _support_cell(rune_id: String, slot: int, idx: int, sz: Vector2) -> DragSlot:
	var cell := DragSlot.new(sz)
	var r := RuneDef.DB.get_rune(rune_id) if rune_id != "" else null
	if r == null:
		cell.setup(null, Color(0.40, 0.36, 0.52), Color(0.06, 0.05, 0.09), 0, "◌", "Empty link - drop a support gem here")
	else:
		var sel: bool = _sel.get("type", "") == "support" and _sel.get("id", "") == rune_id
		var border := r.rarity_color() if r.rarity > 0 else r.color
		cell.setup(r.get_icon(), Color.WHITE if sel else border, r.color.darkened(0.8),
			GameState.rune_count(rune_id) if slot < 0 else 0, "",
			"%s (Lv %d)\n%s" % [r.display_name, GameState.support_level(rune_id), r.description])
		_overlay(cell, "%d" % GameState.support_level(rune_id), 11, Color(1.0, 0.9, 0.5), VERTICAL_ALIGNMENT_TOP, HORIZONTAL_ALIGNMENT_LEFT)
		cell.payload = {"kind": "rune", "from": "pouch" if slot < 0 else "link", "slot": slot, "idx": idx, "rune_id": rune_id}
		cell.clicked.connect(_select.bind({"type": "support", "id": rune_id, "slot": slot}))
	if slot >= 0:
		cell.can_accept = func(d: Dictionary) -> bool:
			return d.get("kind", "") == "rune" and not (d.get("from", "") == "link" and int(d.slot) == slot and int(d.idx) == idx)
		cell.on_drop = func(d: Dictionary) -> void:
			var ok: bool
			if d.get("from", "") == "link":
				ok = GameState.move_support(int(d.slot), int(d.idx), slot, idx)
			else:
				ok = GameState.socket_support(slot, mini(idx, GameState.slot_supports(slot).size()), d.rune_id)
			if not ok:
				menu.feedback("Can't link that: one elemental support per skill, and no doubles.")
			menu.refresh()
	else:
		_accept_returns(cell)
	return cell


## Shows a gem's details here, switching the menu's left side to this panel if needed.
func _select(sel: Dictionary) -> void:
	_sel = sel
	if menu.current_panel() != self:
		menu.show_panel("skills")
	else:
		menu.refresh()


## Inventory tab cells (CharacterPanel): a loose skill gem, a loose support, or an empty cell
## (skill_id / rune_id ""). Each takes gems back out of slots and links.
func pouch_skill_cell(skill_id: String, sz: Vector2) -> DragSlot:
	if skill_id == "":
		return _empty_pouch_cell(sz)
	return _skill_cell(skill_id, -1, sz)


func pouch_support_cell(rune_id: String, sz: Vector2) -> DragSlot:
	if rune_id == "":
		return _empty_pouch_cell(sz)
	return _support_cell(rune_id, -1, -1, sz)


func _empty_pouch_cell(sz: Vector2) -> DragSlot:
	var empty := DragSlot.new(sz)
	empty.setup(null, UIKit.EMPTY_BORDER)
	_accept_returns(empty)
	return empty


## Owned skill gems / supports, in display order.
static func owned_skill_gems() -> Array[String]:
	var ids: Array[String] = []
	for sk in SkillTree.active_skills():
		if GameState.skill_gem_count(sk.id) > 0:
			ids.append(sk.id)
	return ids


## Inventory cells take gems back out of slots and links.
func _accept_returns(cell: DragSlot) -> void:
	cell.can_accept = func(d: Dictionary) -> bool:
		return (d.get("kind", "") == "skillgem" and d.get("from", "") == "slot") \
			or (d.get("kind", "") == "rune" and d.get("from", "") == "link")
	cell.on_drop = func(d: Dictionary) -> void:
		if d.kind == "skillgem":
			GameState.clear_slot_skill(int(d.slot))
		else:
			GameState.unsocket_support(int(d.slot), int(d.idx))
		menu.refresh()


static func owned_supports() -> Array[String]:
	var ids: Array[String] = []
	for r in RuneDef.DB.base_runes():
		for rar in [2, 1, 0]:
			var id := RuneDef.DB.make_id(r.id, rar)
			if GameState.rune_count(id) > 0:
				ids.append(id)
	return ids


func _overlay(cell: Control, text: String, size: int, col: Color, v: int, h: int) -> void:
	var l := UIKit.label(text, size, col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = v
	l.horizontal_alignment = h
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(l)


# ---------- details ----------

func _add_details(parent: Control) -> void:
	var d := UIKit.section(parent, "", true)
	d.get_parent().custom_minimum_size = Vector2(220, 0)
	if _sel.is_empty():
		d.add_child(UIKit.label("Tap a gem to see what it does.", 13, UIKit.TEXT_DIM, true))
		return
	if _sel.type == "skill":
		var id: String = _sel.id
		var slot := GameState.slot_of(id)
		var sk := GameState.get_slot_skill_def(slot) if slot >= 0 else SkillTree.get_skill(id)
		if sk == null:
			return
		var lvl := GameState.gem_level(id)
		d.add_child(UIKit.label("%s %s" % [sk.icon, sk.display_name], 18, sk.color.lightened(0.2)))
		var info := "Skill Gem  •  Level %d / %d" % [lvl, SkillTree.GEM_MAX_LEVEL]
		if lvl < SkillTree.GEM_MAX_LEVEL:
			info += "  •  XP %d / %d" % [int(GameState.gem_xp.get(id, 0.0)), int(GameState.gem_xp_to_next(lvl))]
		d.add_child(UIKit.label(info, 13, Color(0.38, 0.65, 0.98)))
		var why := GameState.skill_gem_block_reason(id)
		if why != "":
			d.add_child(UIKit.label("🔒 " + why, 13, Color(1.0, 0.45, 0.45)))
		d.add_child(UIKit.rich(sk.get_rank_description(GameState.get_skill_rank(id)), 14))
		if sk.resource_cost > 0.0:
			d.add_child(UIKit.rich("[color=#fb923c]With its supports this costs %d %s (base %d).[/color]" % [
				int(round(player.skill_cost(sk))), player.class_def.power_name, int(sk.resource_cost)], 13))
		d.add_child(UIKit.label("Socketed skill gems level up from the experience you earn.", 12, UIKit.TEXT_DIM, true))
		_add_gemcutter(d, id, false, lvl)
	else:
		var r := RuneDef.DB.get_rune(_sel.id)
		if r == null:
			return
		d.add_child(UIKit.label("%s  %s" % [r.icon, r.display_name], 18, r.rarity_color() if r.rarity > 0 else r.color))
		var slvl := GameState.support_level(r.id)
		var sinfo := "Support Gem  •  Level %d / %d" % [slvl, SkillTree.GEM_MAX_LEVEL]
		if slvl < SkillTree.GEM_MAX_LEVEL:
			sinfo += "  •  XP %d / %d" % [int(GameState.support_xp.get(r.id, 0.0)), int(GameState.gem_xp_to_next(slvl))]
		d.add_child(UIKit.label(sinfo, 13, Color(0.38, 0.65, 0.98), true))
		d.add_child(UIKit.label(r.description, 14, Color(0.9, 0.9, 0.95), true))
		d.add_child(UIKit.rich(r.stat_lines(slvl), 14))
		d.add_child(UIKit.label("Supports linked to a socketed skill level up from the experience you earn: +3% effects and +1% skill damage per level.", 12, UIKit.TEXT_DIM, true))
		_add_gemcutter(d, r.id, true, slvl)


## "Use Gemcutter's Prism" button: a level's worth of experience for this gem.
func _add_gemcutter(parent: Control, id: String, support: bool, lvl: int) -> void:
	var n := GameState.orb_count("gemcutter")
	if lvl >= SkillTree.GEM_MAX_LEVEL:
		return
	var b := UIKit.button("💎 Gemcutter's Prism: +1 level (have %d)" % n, Color(0.10, 0.22, 0.24), Color(0.60, 0.95, 0.95), Vector2(0, 44), 14)
	b.disabled = n <= 0
	b.pressed.connect(func():
		if GameState.use_gemcutter(id, support):
			menu.feedback("Gem levelled up!")
		menu.refresh()
	)
	parent.add_child(b)
