class_name SkillGemsPanel
extends MenuPanel
## Skill gems, Path of Exile style. Six skill slots (one HUD button each; slot 1 is the main
## attack): each holds a skill gem plus support gems in its links. Links open as you level
## (GameState.links_unlocked). Loose gems are the account's, kept in the shared stash: gems can only
## be socketed or swapped at the Jeweler (GameState.gem_station). There, tap a slot or a link and a
## dropdown opens where you tapped (the menu's ItemTip): the skill gems (or supports) you have that
## can go there, what the one there does, and taking it out. Tapping a gem in it shows its card
## beside the dropdown; tapping it again equips it. Slots also drag onto slots (swap) and
## links onto links (move / swap). Elsewhere the slots are view-only: tapping a gem shows its card.
## Skill and support gems level up while socketed. A gem's card: what it does, its level, and
## Gemcutter's Prism.

const CELL := Vector2(56, 56)
const SLOT_CELL := Vector2(60, 60)
const PICK_ROW_H := 50.0  # a dropdown's rows
const PICK_MAX_H := 380.0  # its list scrolls past this

var _sel := {}  # {"type": "skill" | "support", "id": String, "slot": int}
var _pick_rows: Array = []  # the open dropdown's rows: {button, id, sub, note}
var _chosen := ""  # the gem tapped once in the open dropdown (its card shows beside it)
## Shown inside another panel (the stash's Gems tab): tapping a gem doesn't switch panels.
var embedded := false


func panel_title() -> String:
	return "💠 Skills"


func refresh() -> void:
	UIKit.clear(self)
	var links := GameState.links_unlocked()
	var nxt := GameState.next_link_level()
	var title := "SKILL SLOTS  —  %d support link%s" % [links, "" if links == 1 else "s"]
	if nxt > 0:
		title += "  (next at level %d)" % nxt
	var sec := UIKit.section(self, title)
	for i in GameState.SKILL_SLOTS:
		sec.add_child(_slot_row(i, links))
	if GameState.gem_station:
		sec.add_child(UIKit.label("Tap a slot or a link to choose its gem.", 12, UIKit.TEXT_DIM, true))
	else:
		sec.add_child(UIKit.label("🔒 Change skill and support gems at the Jeweler in town. Tap a gem to see what it does.",
			13, UIKit.TEXT_DIM, true))


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
		cell.setup(null, Color(0.45, 0.40, 0.30), Color(0.07, 0.06, 0.08), 0, "◇", "Empty skill slot - tap to choose a skill gem")
	else:
		var sel: bool = _sel.get("type", "") == "skill" and _sel.get("id", "") == skill_id
		var ok := GameState.skill_gem_block_reason(skill_id) == ""
		cell.setup(IconFactory.gem_icon("skill:" + skill_id, sk.color, 3), Color.WHITE if sel else sk.color,
			Color(sk.color).darkened(0.85), GameState.skill_gem_count(skill_id) if slot < 0 else 0)  # tap: its card
		if not ok:
			cell.modulate = Color(1, 1, 1, 0.45)
		if SkillIcons.texture(skill_id) == null:  # the drawn gem carries the skill's symbol
			_overlay(cell, sk.icon, 22, Color.WHITE, VERTICAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
		_overlay(cell, "%d" % GameState.gem_level(skill_id), 11, Color(1.0, 0.9, 0.5), VERTICAL_ALIGNMENT_TOP, HORIZONTAL_ALIGNMENT_LEFT)
		cell.payload = {"kind": "skillgem", "from": "slot", "slot": slot, "skill": skill_id}
		if not GameState.gem_station:
			cell.clicked.connect(_select.bind({"type": "skill", "id": skill_id, "slot": slot}))
	if not GameState.gem_station:
		cell.payload = {}  # view-only away from the Jeweler
		return cell
	cell.clicked.connect(func(): _pick_skill(slot, get_viewport().get_mouse_position()))
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "skillgem" and d.get("from", "") == "slot" and int(d.get("slot", -1)) != slot
	cell.on_drop = func(d: Dictionary) -> void:
		GameState.swap_slots(int(d.slot), slot)
		menu.refresh()
	return cell


## A support gem cell: in link `idx` of slot `slot`, or in the pouch (slot -1). rune_id "" = empty link.
func _support_cell(rune_id: String, slot: int, idx: int, sz: Vector2) -> DragSlot:
	var cell := DragSlot.new(sz)
	var r := RuneDef.DB.get_rune(rune_id) if rune_id != "" else null
	if r == null:
		cell.setup(null, Color(0.40, 0.36, 0.52), Color(0.06, 0.05, 0.09), 0, "◌", "Empty link - tap to choose a support gem")
	else:
		var sel: bool = _sel.get("type", "") == "support" and _sel.get("id", "") == rune_id
		var border := r.rarity_color() if r.rarity > 0 else r.color
		cell.setup(r.get_icon(), Color.WHITE if sel else border, r.color.darkened(0.8),
			GameState.rune_count(rune_id) if slot < 0 else 0)  # tap: its card
		_overlay(cell, "%d" % GameState.support_level(rune_id), 11, Color(1.0, 0.9, 0.5), VERTICAL_ALIGNMENT_TOP, HORIZONTAL_ALIGNMENT_LEFT)
		cell.payload = {"kind": "rune", "from": "link", "slot": slot, "idx": idx, "rune_id": rune_id}
		if not GameState.gem_station:
			cell.clicked.connect(_select.bind({"type": "support", "id": rune_id, "slot": slot}))
	if not GameState.gem_station:
		cell.payload = {}  # view-only away from the Jeweler
		return cell
	cell.clicked.connect(func(): _pick_support(slot, idx, get_viewport().get_mouse_position()))
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "rune" and d.get("from", "") == "link" and not (int(d.slot) == slot and int(d.idx) == idx)
	cell.on_drop = func(d: Dictionary) -> void:
		if not GameState.move_support(int(d.slot), int(d.idx), slot, idx):
			menu.feedback("Can't link that: one elemental support per skill, and no doubles.")
		menu.refresh()
	return cell


## Picks a gem and shows its card where it was tapped (switching the menu's left side to this
## panel first if needed).
func _select(sel: Dictionary, at = null) -> void:
	_sel = sel
	if not at is Vector2:
		at = get_viewport().get_mouse_position()
	if not embedded and menu.current_panel() != self:
		menu.show_panel("skills")
	else:
		menu.refresh()
	_show_tip(at)


func _show_tip(at: Vector2) -> void:
	if _sel.is_empty():
		return
	menu.item_tip().show_content(at, func(d: VBoxContainer):
		_add_details(d, at))


## Owned skill gems / supports, in display order.
static func owned_skill_gems() -> Array[String]:
	var ids: Array[String] = []
	for sk in SkillTree.active_skills():
		if GameState.skill_gem_count(sk.id) > 0:
			ids.append(sk.id)
	return ids


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


# ---------- dropdowns ----------

## The skill gems slot `slot` can take, in a dropdown at `at`: yours not in a slot, and those in
## other slots (picking one swaps the two); what the one there does, and taking it out.
func _pick_skill(slot: int, at: Vector2) -> void:
	var here := GameState.slot_skill(slot)
	var rows: Array = []  # [icon, text, enabled, Callable]
	for sk in SkillTree.active_skills():
		var other := GameState.slot_of(sk.id)
		if sk.id == here or (other < 0 and GameState.skill_gem_count(sk.id) <= 0):
			continue
		var why := GameState.skill_gem_block_reason(sk.id)
		var text := "%s   Lv %d" % [sk.display_name, GameState.gem_level(sk.id)]
		if other >= 0:
			text += "\n[color]swaps with %s" % ("the main attack" if other == 0 else "skill %d" % other)
		elif why != "":
			text += "\n[color]" + why
		var id: String = sk.id
		rows.append([IconFactory.gem_icon("skill:" + id, sk.color, 3), text, why == "", func():
			if not GameState.set_slot_skill(slot, id):
				menu.feedback("Can't socket that here.")
			_close_pick(), id])
	var title := "MAIN ATTACK" if slot == 0 else "SKILL %d" % slot
	_show_pick(at, title, "Choose a skill gem", rows, "skill", here, func():
		GameState.clear_slot_skill(slot)
		_close_pick(), "You have no other skill gems. Find them in rifts, or buy them from the Merchant.")


## The supports link `idx` of slot `slot` can take, in a dropdown at `at`: yours not linked, each
## greyed out if it can't go with the slot's others; what the one there does, and taking it out.
func _pick_support(slot: int, idx: int, at: Vector2) -> void:
	var list: Array = GameState.slot_supports(slot)
	var here: String = String(list[idx]) if idx < list.size() else ""
	var rows: Array = []
	for rid in owned_supports():
		if rid == here:
			continue  # (another of the one there)
		var r := RuneDef.DB.get_rune(rid)
		var trial: Array = list.duplicate()
		if idx < trial.size():
			trial[idx] = rid
		else:
			trial.append(rid)
		var fits := SkillDef.supports_valid(trial)
		var text := "%s   Lv %d   ×%d" % [r.display_name, GameState.support_level(rid), GameState.rune_count(rid)]
		if not fits:
			text += "\n[color]one elemental support per skill, and no doubles"
		var id: String = rid
		rows.append([r.get_icon(), text, fits, func():
			if not GameState.socket_support(slot, mini(idx, GameState.slot_supports(slot).size()), id):
				menu.feedback("Can't link that: one elemental support per skill, and no doubles.")
			_close_pick(), id])
	var sk := GameState.get_slot_skill_def(slot)
	var title := "SUPPORT FOR %s" % (sk.display_name.to_upper() if sk != null else ("THE MAIN ATTACK" if slot == 0 else "SKILL %d" % slot))
	_show_pick(at, title, "Choose a support gem", rows, "support", here, func():
		GameState.unsocket_support(slot, idx)
		_close_pick(), "You have no loose support gems. Find them in rifts.")


## A dropdown at `at`: its title, the gem there now (what it does, Take it out) and the rows to pick
## from ([icon, text (a second line after "\n[color]" is dimmed), enabled, Callable, gem id]).
func _show_pick(at: Vector2, title: String, prompt: String, rows: Array, type: String, here: String,
		take_out: Callable, none: String) -> void:
	_pick_rows.clear()
	_chosen = ""
	menu.item_tip().show_content(at, func(d: VBoxContainer):
		var head := UIKit.label(title, 15, UIKit.GOLD)
		head.custom_minimum_size.x = 260  # clear of the close button
		d.add_child(head)
		if here != "":
			var bar := HBoxContainer.new()
			bar.add_theme_constant_override("separation", 6)
			d.add_child(bar)
			var info := UIKit.button("ℹ What it does", Color(0.12, 0.12, 0.18), Color(0.55, 0.60, 0.80), Vector2(0, 40), 13)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.pressed.connect(func(): _select({"type": type, "id": here, "slot": -1}, at))
			bar.add_child(info)
			var out := UIKit.button("✖ Take it out", Color(0.20, 0.10, 0.10), Color(0.90, 0.45, 0.40), Vector2(0, 40), 13)
			out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			out.pressed.connect(take_out)
			bar.add_child(out)
		d.add_child(UIKit.label(prompt + ": tap to see it, again to equip", 12, UIKit.TEXT_DIM, true))
		if rows.is_empty():
			d.add_child(UIKit.label(none, 13, UIKit.TEXT_DIM, true))
			return
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, minf(rows.size() * (PICK_ROW_H + 4.0), PICK_MAX_H))
		d.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 4)
		scroll.add_child(list)
		for r in rows:
			list.add_child(_pick_row(r[0], String(r[1]), bool(r[2]), r[3], String(r[4]), type)))


## One row of a dropdown: the gem's icon, its name (and a dim second line). The first tap shows its
## card beside the dropdown; tapping it again picks it (if it can go there).
func _pick_row(icon: Texture2D, text: String, enabled: bool, pick: Callable, id: String, type: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, PICK_ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	_style_row(b, false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	var ic := TextureRect.new()
	ic.texture = icon
	ic.custom_minimum_size = Vector2(PICK_ROW_H - 10.0, PICK_ROW_H - 10.0)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var lines := text.split("\n[color]")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var main := UIKit.label(lines[0], 14, Color(0.92, 0.90, 0.84) if enabled else Color(0.55, 0.53, 0.50))
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(main)
	var note: String = lines[1] if lines.size() > 1 else ""
	var sub := UIKit.label(note, 11, Color(0.95, 0.55, 0.45) if not enabled else UIKit.TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.visible = note != ""
	col.add_child(sub)
	_pick_rows.append({"button": b, "id": id, "sub": sub, "note": note, "enabled": enabled})
	b.pressed.connect(func():
		if _chosen == id and enabled:
			pick.call()
			return
		_choose(id, type))
	return b


## A gem tapped once in the dropdown: its row lit (and told to tap again), its card beside it.
func _choose(id: String, type: String) -> void:
	_chosen = id
	for r in _pick_rows:
		var on: bool = r.id == id
		_style_row(r.button, on)
		var sub: Label = r.sub
		if on and r.enabled:
			sub.text = "Tap again to equip"
			sub.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
		else:
			sub.text = r.note
			sub.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45) if not r.enabled else UIKit.TEXT_DIM)
		sub.visible = sub.text != ""
	_sel = {"type": type, "id": id, "slot": -1}
	menu.item_tip().show_beside(func(d: VBoxContainer): _add_details(d, Vector2.ZERO, false))


func _style_row(b: Button, on: bool) -> void:
	var border := Color(0.95, 0.80, 0.40) if on else Color(0.32, 0.30, 0.40)
	for st in ["normal", "hover", "pressed"]:
		var bg := Color(0.20, 0.17, 0.10) if on else (Color(0.18, 0.16, 0.24) if st == "hover" else Color(0.10, 0.09, 0.13))
		b.add_theme_stylebox_override(st, UIKit.box(bg, border, 2 if on else 1, 5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _close_pick() -> void:
	menu.item_tip().close()
	menu.refresh()


# ---------- details ----------

## The picked gem's card (in the tooltip at `at`); `prism`: with the Gemcutter's Prism button (not in
## a dropdown's side card).
func _add_details(d: VBoxContainer, at: Vector2, prism := true) -> void:
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
		var need := SkillTree.gem_attr_req(id)
		var parts: Array[String] = []
		for k in need:
			var short := GameState.attribute_total(k) < int(need[k])
			parts.append("[color=#%s]%d %s[/color]" % ["f87171" if short else "d8cdb8", int(need[k]), Attributes.NAMES[k]])
		d.add_child(UIKit.rich("[color=#%s]● %s gem[/color]  [color=#9a8f7e]Requires[/color] %s" % [sk.gem_color().to_html(false),
			"/".join(PackedStringArray(sk.attributes.map(func(a): return String(Attributes.GEM_COLOR_NAMES.get(a, a)).capitalize()))),
			", ".join(PackedStringArray(parts))], 13))
		var why := GameState.skill_gem_block_reason(id)
		if why != "":
			d.add_child(UIKit.label("🔒 " + why, 13, Color(1.0, 0.45, 0.45)))
		d.add_child(UIKit.rich(sk.get_rank_description(GameState.get_skill_rank(id)), 14))
		if sk.resource_cost > 0.0:
			d.add_child(UIKit.rich("[color=#%s]With its supports this costs %d %s (base %d).[/color]" % [
				"60a5fa" if sk.uses_mana() else "fb923c", int(round(player.skill_cost(sk))), sk.resource_name(), int(sk.resource_cost)], 13))
		d.add_child(UIKit.label("Socketed skill gems level up from the experience you earn.", 12, UIKit.TEXT_DIM, true))
		if prism:
			_add_gemcutter(d, id, false, lvl, at)
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
		if prism:
			_add_gemcutter(d, r.id, true, slvl, at)


## "Use Gemcutter's Prism" button: a level's worth of experience for this gem (its card shows again).
func _add_gemcutter(parent: Control, id: String, support: bool, lvl: int, at: Vector2) -> void:
	var n := GameState.orb_count("gemcutter")
	if lvl >= SkillTree.GEM_MAX_LEVEL:
		return
	var b := UIKit.button("💎 Gemcutter's Prism: +1 level (have %d)" % n, Color(0.10, 0.22, 0.24), Color(0.60, 0.95, 0.95), Vector2(0, 44), 14)
	b.disabled = n <= 0
	b.pressed.connect(func():
		if GameState.use_gemcutter(id, support):
			menu.feedback("Gem levelled up!")
		menu.refresh()
		_show_tip(at)
	)
	parent.add_child(b)
