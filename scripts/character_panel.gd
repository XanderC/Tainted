class_name CharacterPanel
extends PanelContainer
## Right half of the GameMenu: character header, equipment paperdoll, summary stats, the bag grid
## and currencies. Everything is drag and drop:
##   bag <-> bag (rearrange/swap), bag -> equipment slot (equip), equipment -> bag (unequip),
##   stash -> bag (take), and anything the current left panel accepts (e.g. buying a ware).
## Tapping an item selects it for the left panel (details, gems, blacksmith, merchant...).
## Orbs from the Currency tab can be dropped onto worn gear to use them.

const BAG_COLS := 8
const BAG_CELL := Vector2(58, 58)
const GEAR_CELL := Vector2(66, 66)
const LEFT_SLOTS := ["helmet", "chest", "gloves", "boots"]
const RIGHT_SLOTS := ["amulet", "ring", "weapon", "offhand"]

var menu: GameMenu
var player: Player

var _level_lbl: Label
var _class_lbl: Label
var _left_col: VBoxContainer
var _right_col: VBoxContainer
var _summary: RichTextLabel
var _portrait: SubViewportContainer
var _rig: RigSprite
var _mats: VBoxContainer
var _bag_grid: GridContainer
var bag_tab := "equipment"  # "equipment" | "skillgems" | "supports" | "gems" | "consumables" | "currency"
var _tab_row: HBoxContainer


func _ready() -> void:
	clip_contents = true
	var sb := UIKit.box(Color(0.07, 0.06, 0.09, 0.97), Color(0.48, 0.38, 0.22), 2, 10)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	# Header: level, class, Stats popup, Close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	v.add_child(header)
	_level_lbl = UIKit.label("1", 20, Color(1.0, 0.92, 0.6))
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_lbl.custom_minimum_size = Vector2(46, 46)
	var lvl_box := PanelContainer.new()
	lvl_box.add_theme_stylebox_override("panel", UIKit.box(Color(0.10, 0.08, 0.12), Color(0.95, 0.80, 0.40), 2, 23))
	lvl_box.add_child(_level_lbl)
	header.add_child(lvl_box)
	_class_lbl = UIKit.label("", 20, UIKit.GOLD)
	_class_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_class_lbl)
	var stats_btn := UIKit.button("📜 Stats", Color(0.16, 0.12, 0.10), Color(0.75, 0.58, 0.30), Vector2(110, 48), 17)
	stats_btn.pressed.connect(func(): menu.toggle_stats())
	header.add_child(stats_btn)
	var close_btn := UIKit.button("✕ Close", Color(0.22, 0.10, 0.10), Color(0.75, 0.30, 0.30), Vector2(120, 48), 18)
	close_btn.pressed.connect(func(): menu.close())
	header.add_child(close_btn)

	# Paperdoll: armour on the left, jewellery & weapon on the right, summary stats in the middle
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 10)
	v.add_child(doll)
	_left_col = VBoxContainer.new()
	_left_col.add_theme_constant_override("separation", 6)
	doll.add_child(_left_col)
	var mid := PanelContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var msb := UIKit.box(Color(0.10, 0.07, 0.08, 0.9), Color(0.30, 0.22, 0.16), 1, 8)
	msb.set_content_margin_all(10)
	mid.add_theme_stylebox_override("panel", msb)
	doll.add_child(mid)
	var mid_v := VBoxContainer.new()
	mid_v.add_theme_constant_override("separation", 4)
	mid.add_child(mid_v)

	# Character figure wearing the current gear (an idle rig rendered in its own viewport)
	_portrait = SubViewportContainer.new()
	_portrait.stretch = true
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.custom_minimum_size = Vector2(160, 200)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid_v.add_child(_portrait)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	_portrait.add_child(vp)
	_rig = RigSprite.new()
	_rig.base_scale = 0.42
	_rig.weapon_from_gear = true
	vp.add_child(_rig)
	_rig.play_loop("Idle")
	_portrait.resized.connect(func(): _rig.position = Vector2(_portrait.size.x * 0.5, _portrait.size.y * 0.97))

	_summary = UIKit.rich("", 15)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_v.add_child(_summary)
	_right_col = VBoxContainer.new()
	_right_col.add_theme_constant_override("separation", 6)
	doll.add_child(_right_col)

	# Bag tabs (Equipment, gems, consumables, currency), then crafting materials down the left
	# side of the grid
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	v.add_child(_tab_row)
	var bag_row := HBoxContainer.new()
	bag_row.add_theme_constant_override("separation", 10)
	v.add_child(bag_row)
	_mats = VBoxContainer.new()
	_mats.add_theme_constant_override("separation", 6)
	_mats.custom_minimum_size = Vector2(150, 0)
	bag_row.add_child(_mats)
	_bag_grid = UIKit.grid(BAG_COLS, 5)
	_bag_grid.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	bag_row.add_child(_bag_grid)


func refresh() -> void:
	_level_lbl.text = str(GameState.level)
	_class_lbl.text = "%s   •   Level %d" % [player.class_def.display_name, GameState.level]

	var s := player.stats
	_summary.text = ("[center][color=#bdb6aa]Damage[/color] [color=#f3e6c4][b]%.0f[/b][/color]     " +
		"[color=#bdb6aa]Armor[/color] [color=#f3e6c4][b]%d[/b][/color]     " +
		"[color=#bdb6aa]Life[/color] [color=#f3e6c4][b]%d[/b][/color][/center]") % [
		s.get_stat("damage"), int(s.get_stat("armor")), int(s.get_stat("max_life"))]
	Player.dress_rig(_rig, player.equipment)

	UIKit.clear(_left_col)
	UIKit.clear(_right_col)
	for slot in LEFT_SLOTS:
		_left_col.add_child(_gear_cell(slot))
	for slot in RIGHT_SLOTS:
		if slot == "weapon":
			_right_col.add_child(_set_toggle())
		_right_col.add_child(_gear_cell(slot))
	_left_col.add_child(_potion_slot_cell())

	UIKit.clear(_tab_row)
	for t in [["equipment", "Equipment"], ["skillgems", "Skill Gems"], ["supports", "Supports"], ["gems", "Gems"],
			["consumables", "Consumables"], ["currency", "Currency"]]:
		var active: bool = bag_tab == t[0]
		var b := UIKit.button(t[1], Color(0.24, 0.18, 0.10) if active else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.82, 0.40) if active else Color(0.35, 0.28, 0.20), Vector2(0, 36), 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = t[0]
		b.pressed.connect(func():
			bag_tab = id
			# gems go into the skill slots, so show those on the left (unless a vendor is open)
			if id in ["skillgems", "supports"] and not menu.vendor_open() and not menu.current_panel() is SkillGemsPanel:
				menu.show_panel("skills")
			elif id == "gems" and not menu.vendor_open() and not menu.current_panel() is GemsPanel:
				menu.show_panel("gems")  # item gems go into sockets shown there
			else:
				refresh()
		)
		_tab_row.add_child(b)

	UIKit.clear(_bag_grid)
	if bag_tab == "consumables":
		_fill_consumables()
	elif bag_tab == "currency":
		_fill_currency()
	elif bag_tab == "skillgems":
		_fill_gems(SkillGemsPanel.owned_skill_gems(), true)
	elif bag_tab == "supports":
		_fill_gems(SkillGemsPanel.owned_supports(), false)
	elif bag_tab == "gems":
		_fill_item_gems()
	else:
		for i in Player.BAG_SIZE:
			_bag_grid.add_child(_bag_cell(i))

	# Crafting materials, one per line down the left of the grid
	UIKit.clear(_mats)
	_mats.add_child(UIKit.label("MATERIALS", 12, UIKit.TEXT_DIM))
	for k in CraftingDB.MATERIALS:
		var m: Dictionary = CraftingDB.MATERIALS[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = IconFactory.material_icon(k, m.color)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name_l := UIKit.label(m.name, 13, m.color)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(UIKit.label(str(GameState.material_count(k)), 14, Color(0.95, 0.92, 0.85)))
		_mats.add_child(row)


func _gear_cell(slot: String) -> DragSlot:
	var it: ItemInstance = player.equipment.get(slot)
	var cell := UIKit.item_cell(it, it != null and it == menu.selected, GEAR_CELL)
	if it == null:
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0,
			"%s\n%s" % [UIKit.SLOT_ICONS.get(slot, ""), UIKit.SLOT_NAMES.get(slot, slot)], UIKit.SLOT_NAMES.get(slot, slot))
	else:
		cell.payload = {"kind": "item", "from": "gear", "slot": slot, "item": it}
		cell.clicked.connect(menu.select.bind(it))
	cell.can_accept = func(d: Dictionary) -> bool:
		if d.get("kind", "") == "orb":  # use currency on worn gear
			return it != null and Crafting.orb_block_reason(it, String(d.id)) == ""
		var di: ItemInstance = d.get("item")
		return d.get("kind", "") == "item" and d.get("from", "") in ["bag", "gear"] and di != null \
			and player.valid_slots(di).has(slot)
	cell.on_drop = func(d: Dictionary) -> void:
		if d.get("kind", "") == "orb":
			menu.feedback(Crafting.apply_orb(player, it, String(d.id)).msg)
			menu.select(it)
			return
		var di: ItemInstance = d.get("item")
		if player.equip_to(di, slot):
			menu.select(di)
		else:
			menu.feedback(player.equip_block_reason(di) if not player.can_equip(di) else "Not enough bag space to swap.")
			menu.refresh()
	return cell


func _bag_cell(i: int) -> DragSlot:
	var it: ItemInstance = player.inventory[i] if i < player.inventory.size() else null
	var cell := UIKit.item_cell(it, it != null and it == menu.selected, BAG_CELL)
	if it != null:
		cell.payload = {"kind": "item", "from": "bag", "idx": i, "item": it}
		cell.clicked.connect(menu.select.bind(it))
	cell.can_accept = func(d: Dictionary) -> bool:
		if d.get("kind", "") == "item":
			match d.get("from", ""):
				"bag": return int(d.get("idx", -1)) != i
				"gear": return it == null or player.valid_slots(it).has(d.get("slot", ""))
				"stash": return true
			return false
		var p := menu.current_panel()
		return p != null and p.accepts_bag_drop(d)
	cell.on_drop = func(d: Dictionary) -> void:
		if d.get("kind", "") == "item":
			match d.get("from", ""):
				"bag": player.swap_bag_slots(int(d.get("idx", -1)), i)
				"gear": player.unequip_gear_to_bag_slot(d.get("slot", ""), i)
				"stash": GameState.stash_to_bag_slot(int(d.get("idx", -1)), i)
			menu.refresh()
		else:
			menu.current_panel().on_bag_drop(d, i)
	return cell


# ---------- potions ----------

func _potion_tip(id: String) -> String:
	var p := PotionDef.info(id, player.class_def.power_name)
	return "%s\n%s" % [p.get("name", id), p.get("desc", "")]


## Potion slot under the armour: drag a potion stack here to drink it with the HUD button.
func _potion_slot_cell() -> DragSlot:
	var cell := DragSlot.new(GEAR_CELL)
	var id := GameState.potion_slot
	if id != "" and GameState.potion_count(id) > 0:
		var p := PotionDef.info(id, player.class_def.power_name)
		cell.setup(PotionDef.icon(id), p.color, Color(p.color).darkened(0.8), GameState.potion_count(id), "",
			_potion_tip(id) + "\n(drink with the HUD potion button or Q)")
		cell.payload = {"kind": "potion", "from": "slot", "id": id}
	else:
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0, "🧪\nPotion",
			"Potion slot - drag a potion here from Consumables")
	cell.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "potion" and d.get("from", "") == "pouch"
	cell.on_drop = func(d: Dictionary) -> void:
		GameState.set_potion_slot(d.get("id", ""))
	return cell


## Consumables tab: one cell per potion type owned. Tap or drag one onto the potion slot.
func _fill_consumables() -> void:
	var owned: Array[String] = []
	for id in PotionDef.all_ids():
		if GameState.potion_count(id) > 0:
			owned.append(id)
	for i in Player.BAG_SIZE:
		var cell := DragSlot.new(BAG_CELL)
		if i < owned.size():
			var id := owned[i]
			var p := PotionDef.info(id, player.class_def.power_name)
			var slotted := id == GameState.potion_slot
			cell.setup(PotionDef.icon(id), Color.WHITE if slotted else Color(p.color), Color(p.color).darkened(0.8),
				GameState.potion_count(id), "", _potion_tip(id) + ("\n(in the potion slot)" if slotted else "\nTap or drag to the potion slot"))
			cell.payload = {"kind": "potion", "from": "pouch", "id": id}
			cell.clicked.connect(func(): GameState.set_potion_slot(id))
		else:
			cell.setup(null, UIKit.EMPTY_BORDER)
		# Dragging the slotted potion back here empties the slot
		cell.can_accept = func(d: Dictionary) -> bool:
			return d.get("kind", "") == "potion" and d.get("from", "") == "slot"
		cell.on_drop = func(_d: Dictionary) -> void:
			GameState.set_potion_slot("")
		_bag_grid.add_child(cell)


## Currency tab: every orb with its count and shard progress. Drag one onto worn gear to use it.
func _fill_currency() -> void:
	for id in CraftingDB.ORB_ORDER:
		var o: Dictionary = CraftingDB.ORBS[id]
		var n := GameState.orb_count(id)
		var sh := GameState.shard_count(id)
		var cell := DragSlot.new(BAG_CELL)
		var tip := "%s\n%s" % [o.name, o.desc]
		if sh > 0:
			tip += "\nShards: %d / %d" % [sh, Currency.SHARDS_PER_ORB]
		cell.setup(CraftingDB.orb_icon(id), Color(o.color) if n > 0 else UIKit.EMPTY_BORDER, Color(0.08, 0.07, 0.10), n, "", tip)
		if n <= 0:
			cell.modulate = Color(1, 1, 1, 0.4)
		else:
			cell.payload = {"kind": "orb", "id": id}
		if sh > 0:
			var l := UIKit.label("%d/%d" % [sh, Currency.SHARDS_PER_ORB], 10, Color(0.85, 0.85, 0.95))
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 4)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.offset_left = 3
			cell.add_child(l)
		cell.clicked.connect(func(): menu.feedback("%s: %s" % [o.name, o.desc]))
		_bag_grid.add_child(cell)


## Skill Gems / Supports tabs: one cell per gem type owned (with its count and level), drag them
## onto the Skills panel's slots and links; drop socketed gems back here to take them out.
func _fill_gems(ids: Array[String], skills: bool) -> void:
	var sp := menu.skills_panel()
	var total := maxi(Player.BAG_SIZE, int(ceil(float(ids.size() + 1) / BAG_COLS)) * BAG_COLS)
	for i in total:
		var id: String = ids[i] if i < ids.size() else ""
		_bag_grid.add_child(sp.pouch_skill_cell(id, BAG_CELL) if skills else sp.pouch_support_cell(id, BAG_CELL))


## Gems tab: the item gem pouch. Drag gems onto an item's sockets in the Gems / Jeweler panel.
func _fill_item_gems() -> void:
	var ids := GemsPanel.owned_gems()
	var total := maxi(Player.BAG_SIZE, int(ceil(float(ids.size() + 1) / BAG_COLS)) * BAG_COLS)
	for i in total:
		_bag_grid.add_child(GemsPanel.pouch_cell(menu, ids[i] if i < ids.size() else "", BAG_CELL))


## "1 | 2" switch above the hand slots: shows which weapon set is active and swaps sets.
## The hand slots always show (and equip into) the active set.
func _set_toggle() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for i in 2:
		var active := player.active_set == i
		var b := UIKit.button(str(i + 1), Color(0.24, 0.18, 0.10) if active else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.82, 0.40) if active else Color(0.35, 0.28, 0.20), Vector2(32, 30), 14)
		var alt_names := []
		for s in player.alt_set:
			alt_names.append(player.alt_set[s].display_name)
		b.tooltip_text = "Weapon Set %d%s" % [i + 1, "" if active else (": " + (", ".join(alt_names) if not alt_names.is_empty() else "empty"))]
		if not active:
			b.pressed.connect(func():
				player.swap_weapon_set()
				menu.refresh()
			)
		row.add_child(b)
	return row
