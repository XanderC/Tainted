class_name CharacterPanel
extends PanelContainer
## Right half of the GameMenu, laid out like Path of Exile's inventory: the header, the equipment
## paperdoll (each slot shaped like what it holds, the flasks in a row under the belt) and the bag
## grid under it. Everything is drag and drop:
##   bag <-> bag (rearrange/swap), bag -> equipment slot (equip), equipment -> bag (unequip),
##   stash -> bag (take), anything -> the drop box under the boots (drop on the ground), and
##   anything the current left panel accepts (e.g. buying a ware).
## Tapping an item selects it for the left panel (details, gems, blacksmith, merchant...).
## Currency and loose gems aren't carried: they are the account's, in the
## shared stash (StashPanel), whose Currency tab is where orbs are used.

## One cell of the bag grid (Player.BAG_COLS x BAG_ROWS, gear spanning several).
const GEAR_GRID_CELL := 46.0  # the 12 x 5 bag under the paperdoll on a 720p-tall screen
const DOLL_U := 40.0  # the paperdoll's unit: each slot is a whole number of these
const DOLL_GAP := Vector2(58, 6)  # between slots across (so the doll is as wide as the bag) and down
## Each slot's place on the paperdoll as [column, top, width, height]: the top is so many units plus
## so many gaps down ([units, gaps]), the size in units. Columns: 0 weapon and gloves, 1 a ring,
## 2 helmet / body / belt, 3 amulet and the other ring, 4 off hand and boots.
const DOLL := {
	"weapon": [0, [0, 0], 2, 4],
	"gloves": [0, [4, 2], 2, 2],  # level with the bottom of the belt
	"ring": [1, [3, 1], 1, 1],  # beside the middle of the body armour
	"helmet": [2, [0, 0], 2, 2],
	"chest": [2, [2, 1], 2, 3],
	"belt": [2, [5, 2], 2, 1],
	"amulet": [3, [1, 0], 1, 1],  # beside the bottom of the helmet
	"ring2": [3, [3, 1], 1, 1],
	"offhand": [4, [0, 0], 2, 4],
	"boots": [4, [4, 2], 2, 2],
}
const DOLL_COL_UNITS := [2, 1, 2, 1, 2]
const FLASK_TOP := [6, 3]  # the flask row, under the belt ([units, gaps])

var menu: GameMenu
var player: Player

var _level_lbl: Label
var _class_lbl: Label
var _doll: Control  # the equipment and flask slots, each placed at its spot (DOLL)
var _set_row: HBoxContainer  # the weapon set switch, in the header
var _bag_view: ItemGridView  # the bag, as a grid: all gear, flasks included
var _stats_btn: Button  # says how many attribute points there are to add


func _ready() -> void:
	clip_contents = true
	var sb := UIKit.window_box(20, Color.WHITE, true)
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
	header.custom_minimum_size = Vector2(0, UIKit.HEADER_ROW_H)
	v.add_child(header)
	v.add_child(UIKit.header_gap())
	_level_lbl = UIKit.label("1", 20, Color(1.0, 0.92, 0.6))
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_lbl.custom_minimum_size = Vector2(44, 44)
	var lvl_box := PanelContainer.new()
	lvl_box.add_theme_stylebox_override("panel", UIKit.box(Color(0.10, 0.08, 0.12), Color(0.95, 0.80, 0.40), 2, 23))
	lvl_box.add_child(_level_lbl)
	header.add_child(lvl_box)
	_class_lbl = UIKit.label("", 20, UIKit.GOLD)
	_class_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_class_lbl)
	_set_row = HBoxContainer.new()
	_set_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_set_row)
	_stats_btn = UIKit.button("📜 Stats", Color(0.16, 0.12, 0.10), Color(0.75, 0.58, 0.30), Vector2(100, 43), 16)
	_stats_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats_btn.pressed.connect(func(): menu.toggle_stats())
	header.add_child(_stats_btn)
	var close_btn := UIKit.close_button(1.0)
	close_btn.pressed.connect(func(): menu.close())
	header.add_child(close_btn)

	# The paperdoll, centred, then the bag under it
	_doll = Control.new()
	_doll.custom_minimum_size = doll_size()
	_doll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_doll)
	_bag_view = ItemGridView.new(player.bag, GEAR_GRID_CELL, "bag")
	_bag_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bag_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bag_view.can_accept_at = _bag_accepts
	_bag_view.on_drop_at = _bag_dropped
	_bag_view.item_clicked.connect(func(it: ItemInstance): menu.select(it))
	v.add_child(_bag_view)


## On the paperdoll under the boots, beside the flasks: drag gear here (from the bag, the paperdoll or
## a flask slot) to drop it on the ground. Replaces the Drop button the item panel used to have.
func _drop_box() -> DragSlot:
	var r := drop_box_rect()
	var box := DragSlot.new(r.size)
	box.position = r.position
	box.setup(null, Color(0.55, 0.22, 0.20), Color(0.13, 0.06, 0.06), 0, "", "Drag an item here to drop it on the ground")
	var lbl := UIKit.label("🗑\nDROP", 14, Color(0.85, 0.45, 0.40))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	box.can_accept = func(d: Dictionary) -> bool:
		return d.get("kind", "") == "item" and d.get("item") != null and d.get("from", "") in ["bag", "gear", "flask"]
	box.on_drop = func(d: Dictionary) -> void:
		var it: ItemInstance = d.get("item")
		player.drop_item(it)
		menu.feedback("Dropped %s." % it.display_name)
		if menu.selected == it:
			menu.select(null)
		else:
			menu.refresh()
	return box


func refresh() -> void:
	_level_lbl.text = str(GameState.level)
	_class_lbl.text = "%s   •   Level %d" % [player.class_def.display_name, GameState.level]
	# Unspent attribute points: the Stats button says so (they are added there)
	var pts := GameState.attr_points
	_stats_btn.text = "📜 Stats +%d" % pts if pts > 0 else "📜 Stats"
	_stats_btn.custom_minimum_size.x = 132 if pts > 0 else 100
	_stats_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if pts > 0 else Color(0.95, 0.90, 0.80))
	_stats_btn.tooltip_text = ("%d attribute point%s to add" % [pts, "" if pts == 1 else "s"]) if pts > 0 else "Character stats"

	UIKit.clear(_set_row)
	_set_row.add_child(_set_toggle())
	UIKit.clear(_doll)
	for slot in DOLL:
		var r := doll_rect(slot)
		var cell := _gear_cell(slot, r.size)
		cell.position = r.position
		_doll.add_child(cell)
	for i in Player.FLASK_SLOTS:
		var cell := _flask_cell(i)
		cell.position = flask_rect(i).position
		_doll.add_child(cell)
	_doll.add_child(_drop_box())

	_bag_view.selected = menu.selected
	_bag_view.refresh()



## The paperdoll's size: its five columns across, and down to the bottom of the flask row.
static func doll_size() -> Vector2:
	var units := 0
	for u in DOLL_COL_UNITS:
		units += u
	return Vector2(units * DOLL_U + DOLL_GAP.x * (DOLL_COL_UNITS.size() - 1), _down(FLASK_TOP) + DOLL_U * 2.0)


## A [units, gaps] distance down the paperdoll, in px.
static func _down(d: Array) -> float:
	return int(d[0]) * DOLL_U + int(d[1]) * DOLL_GAP.y


## The x of paperdoll column c.
static func _col_x(c: int) -> float:
	var x := 0.0
	for i in c:
		x += DOLL_COL_UNITS[i] * DOLL_U + DOLL_GAP.x
	return x


## The drop box: under the boots, level with the flasks.
static func drop_box_rect() -> Rect2:
	return Rect2(_col_x(4), _down(FLASK_TOP), DOLL_U * 2.0, DOLL_U * 2.0)


## Where equipment slot `slot` sits on the paperdoll.
static func doll_rect(slot: String) -> Rect2:
	var d: Array = DOLL[slot]
	# a slot narrower than its column is centred in it
	var x: float = _col_x(int(d[0])) + (int(DOLL_COL_UNITS[int(d[0])]) - int(d[2])) * DOLL_U * 0.5
	return Rect2(x, _down(d[1]), int(d[2]) * DOLL_U, int(d[3]) * DOLL_U)


## Flask slot i: the five in a row under the belt, centred on it.
static func flask_rect(i: int) -> Rect2:
	var belt := doll_rect("belt")
	var row_w := Player.FLASK_SLOTS * DOLL_U + (Player.FLASK_SLOTS - 1) * DOLL_GAP.y
	var x0 := belt.get_center().x - row_w * 0.5
	return Rect2(x0 + i * (DOLL_U + DOLL_GAP.y), _down(FLASK_TOP), DOLL_U, DOLL_U * 2.0)


func _gear_cell(slot: String, cell_size: Vector2) -> DragSlot:
	var it: ItemInstance = player.equipment.get(slot)
	var cell := UIKit.item_cell(it, it != null and it == menu.selected, cell_size)
	if it == null:
		# A one-unit slot shows its icon; a bigger one its name
		var cap: String = UIKit.SLOT_NAMES.get(slot, slot) if cell_size.x > DOLL_U else UIKit.SLOT_ICONS.get(slot, "")
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0, cap, UIKit.SLOT_NAMES.get(slot, slot))
		cell.set_placeholder(UIKit.slot_icon(slot))  # its silhouette, where the pack has one
	else:
		cell.payload = {"kind": "item", "from": "gear", "slot": slot, "item": it}
		cell.clicked.connect(menu.select.bind(it))
		if not player.gear_active(it):
			# Worn, but its requirements aren't met: it gives nothing until they are
			cell.modulate = Color(1.0, 0.45, 0.45)
			cell.tooltip_text = "%s\n%s: gives no stats until then" % [it.display_name,
				Attributes.block_reason(it.base, GameState.attribute_totals())]
	cell.can_accept = func(d: Dictionary) -> bool:
		var di: ItemInstance = d.get("item")
		return d.get("kind", "") == "item" and d.get("from", "") in ["bag", "gear"] and di != null \
			and player.valid_slots(di).has(slot)
	cell.on_drop = func(d: Dictionary) -> void:
		var di: ItemInstance = d.get("item")
		var why := player.slot_block_reason(di, slot)
		if why == "" and player.equip_to(di, slot):
			menu.select(di, false)
		else:
			menu.feedback(why if why != "" else "Not enough bag space to swap.")
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
			"hireling": return Hirelings.can_unequip_to(player, String(d.get("slot", "")), at)
			"hireling_flask": return Hirelings.can_unequip_flask_to(player, int(d.get("idx", -1)), at)
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
		"hireling": Hirelings.unequip_to(player, String(d.get("slot", "")), at)
		"hireling_flask": Hirelings.unequip_flask_to(player, int(d.get("idx", -1)), at)
	menu.refresh()


# ---------- flasks ----------

## Flask slot i, in the column down the left of the bag. The belt opens the first few (Player.flask_slot_count);
## the rest are locked, and a flask left in one can't be drunk until a bigger belt opens it.
## Drag a flask here from the bag (or another slot to swap), and back to the bag to take it off.
func _flask_cell(i: int) -> DragSlot:
	var it: ItemInstance = player.flasks[i]
	var open := i < player.flask_slot_count()
	var key: String = FlaskBar.KEYS[i]
	var cell := UIKit.item_cell(it, it != null and it == menu.selected, flask_rect(i).size)
	if it == null:
		cell.setup(null, Color(0.28, 0.24, 0.30), Color(0.09, 0.08, 0.11), 0,
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
			menu.select(di, false)
		else:
			menu.feedback("No room in the bag for the flask it replaces.")
			menu.refresh()
	return cell


## "I | II" switch in the header: shows which weapon set is active and swaps sets.
## The hand slots always show (and equip into) the active set.
func _set_toggle() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for i in 2:
		var active := player.active_set == i
		var b := UIKit.button(["I", "II"][i], Color(0.24, 0.18, 0.10) if active else Color(0.11, 0.10, 0.13),
			Color(0.95, 0.82, 0.40) if active else Color(0.35, 0.28, 0.20), Vector2(40, 40), 16)
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
