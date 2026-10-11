class_name CharacterPanel
extends PanelContainer
## Right half of the GameMenu: character header, equipment paperdoll, summary stats, the bag grid
## and currencies. Everything is drag and drop:
##   bag <-> bag (rearrange/swap), bag -> equipment slot (equip), equipment -> bag (unequip),
##   stash -> bag (take), and anything the current left panel accepts (e.g. buying a ware).
## Tapping an item selects it for the left panel (details, gems, blacksmith, merchant...).
## Currency, crafting materials and loose gems aren't carried: they are the account's, in the
## shared stash (StashPanel). Orbs dragged from its Currency tab can be dropped on worn gear.

## One cell of the bag grid (Player.BAG_COLS x BAG_ROWS, gear spanning several).
const GEAR_GRID_CELL := 36.0  # 10 x 6 cells fit under the paperdoll on a 720p screen
const GEAR_CELL := Vector2(66, 66)
const FLASK_CELL := Vector2(42, 66)  # flasks stand tall, as in the bag
const LEFT_SLOTS := ["helmet", "chest", "gloves", "boots"]
const RIGHT_SLOTS := ["amulet", "ring", "weapon", "offhand"]

var menu: GameMenu
var player: Player

var _level_lbl: Label
var _class_lbl: Label
var _left_col: VBoxContainer
var _right_col: VBoxContainer
var _summary: RichTextLabel
var _flask_row: HBoxContainer  # the flask slots, under the character
var _portrait: SubViewportContainer
var _rig: RigSprite
var _bag_view: ItemGridView  # the bag, as a grid: all gear, flasks included


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
	_flask_row = HBoxContainer.new()
	_flask_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_flask_row.add_theme_constant_override("separation", 6)
	mid_v.add_child(_flask_row)
	_right_col = VBoxContainer.new()
	_right_col.add_theme_constant_override("separation", 6)
	doll.add_child(_right_col)

	# The bag
	var bag_row := HBoxContainer.new()
	bag_row.add_theme_constant_override("separation", 10)
	v.add_child(bag_row)
	_bag_view = ItemGridView.new(player.bag, GEAR_GRID_CELL, "bag")
	_bag_view.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	_bag_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bag_view.can_accept_at = _bag_accepts
	_bag_view.on_drop_at = _bag_dropped
	_bag_view.item_clicked.connect(func(it: ItemInstance): menu.select(it))
	bag_row.add_child(_bag_view)


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
	_left_col.add_child(_gear_cell("belt"))
	UIKit.clear(_flask_row)
	for i in Player.FLASK_SLOTS:
		_flask_row.add_child(_flask_cell(i))

	_bag_view.selected = menu.selected
	_bag_view.refresh()



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


## Whether something dragged over the bag may land with its top-left cell at `at`: gear from the
## bag itself, the paperdoll or the stash (into space, or swapping with one item), or anything the
## open panel takes (a merchant's ware).
func _bag_accepts(d: Dictionary, at: Vector2i) -> bool:
	if d.get("kind", "") == "item":
		var it: ItemInstance = d.get("item")
		if it == null:
			return false
		match d.get("from", ""):
			"bag": return player.bag.has(it) and not player.bag.plan_drop(it, at, player.bag).is_empty()
			"gear": return player.can_unequip_to(String(d.get("slot", "")), at)
			"flask": return player.can_unequip_flask_to(int(d.get("idx", -1)), at)
			"stash": return GameState.can_stash_to_bag(it, at)
		return false
	var p := menu.current_panel()
	return p != null and p.accepts_bag_drop(d)


func _bag_dropped(d: Dictionary, at: Vector2i) -> void:
	if d.get("kind", "") != "item":
		menu.current_panel().on_bag_drop(d, at)
		return
	var it: ItemInstance = d.get("item")
	match d.get("from", ""):
		"bag": player.move_in_bag(it, at)
		"gear": player.unequip_to(String(d.get("slot", "")), at)
		"flask": player.unequip_flask_to(int(d.get("idx", -1)), at)
		"stash": GameState.stash_to_bag(it, at)
	menu.refresh()


# ---------- flasks ----------

## Flask slot i, under the character. The belt opens the first few (Player.flask_slot_count);
## the rest are locked, and a flask left in one can't be drunk until a bigger belt opens it.
## Drag a flask here from the bag (or another slot to swap), and back to the bag to take it off.
func _flask_cell(i: int) -> DragSlot:
	var it: ItemInstance = player.flasks[i]
	var open := i < player.flask_slot_count()
	var key: String = FlaskBar.KEYS[i]
	var cell := UIKit.item_cell(it, it != null and it == menu.selected, FLASK_CELL)
	if it == null:
		cell.setup(null, Color(0.32, 0.26, 0.30) if open else Color(0.16, 0.14, 0.18), Color(0.09, 0.08, 0.11), 0,
			("🧪\n%s" % key) if open else "🔒",
			("Flask slot %d (%s) - drag a flask here" % [i + 1, key]) if open else "Wear a belt with more flask slots to open this one")
	else:
		cell.payload = {"kind": "item", "from": "flask", "idx": i, "item": it}
		cell.clicked.connect(menu.select.bind(it))
		cell.tooltip_text = "%s\n%s\n%s" % [it.display_name, it.flask_text(player.class_def.power_name),
			"Drink with %s" % key if open else "Locked: your belt doesn't open this slot"]
		if not open:
			cell.modulate = Color(1, 1, 1, 0.45)
	cell.can_accept = func(d: Dictionary) -> bool:
		var di: ItemInstance = d.get("item")
		return d.get("kind", "") == "item" and di != null and di.is_flask() and d.get("from", "") in ["bag", "flask"] \
			and not (d.get("from", "") == "flask" and int(d.get("idx", -1)) == i)
	cell.on_drop = func(d: Dictionary) -> void:
		var di: ItemInstance = d.get("item")
		if player.equip_flask(di, i):
			menu.select(di)
		else:
			menu.feedback("No room in the bag for the flask it replaces.")
			menu.refresh()
	return cell


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
