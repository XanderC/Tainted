class_name TradeUI
extends Node
## An open trade (Net.trade_changed): what you offer and what they offer side by side, your bag below
## to pick from (tap an item to offer it, tap again to take it back), Ready on each side (any change
## resets both) and Cancel. Tapping an offered item shows its card (theirs beside what you wear in
## that slot). When it goes through (Net.trade_finished) what you got is in your stash.

const CELL := Vector2(58, 58)

var _layer: CanvasLayer
var _win: PanelContainer
var _tip: ItemTip
var _state := {}
var _offer: Array = []  # the ids you offer


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 31
	add_child(_layer)
	_tip = ItemTip.new()
	_tip.z_index = 60
	Net.trade_changed.connect(_on_state)
	Net.trade_finished.connect(func(items: Array):
		if Net.party_ui != null:
			Net.party_ui.say("Trade done: %d item%s put in your stash." % [items.size(), "" if items.size() == 1 else "s"]))


func _on_state(state: Dictionary) -> void:
	_state = state
	if state.is_empty():
		_offer.clear()
		_close()
		return
	_offer = state.get("mine", []).map(func(d): return String(d.get("uid", "")))
	_build()


func _close() -> void:
	if _win != null:
		_win.queue_free()
		_win = null
	if _tip.get_parent() != null:
		_tip.close()


func _build() -> void:
	_close()
	_win = PanelContainer.new()
	_win.add_theme_stylebox_override("panel", UIKit.window_box(18, Color.WHITE, true))
	_win.custom_minimum_size = Vector2(760, 0)
	_win.set_anchors_preset(Control.PRESET_CENTER)
	_win.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_win.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_win)
	if _tip.get_parent() == null:
		_layer.add_child(_tip)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_win.add_child(v)
	var head := UIKit.window_header(v, "TRADE WITH %s" % String(_state.get("name", "?")).to_upper(), Color(0.65, 0.95, 0.70), Net.trade_cancel, 20)
	(head.get_node("Title") as Label).add_theme_font_override("font", UIKit.body_font(700))

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 16)
	v.add_child(sides)
	_side(sides, "YOU OFFER", _state.get("mine", []), bool(_state.get("ready_me", false)), false)
	_side(sides, "%s OFFERS" % String(_state.get("name", "")).to_upper(), _state.get("theirs", []), bool(_state.get("ready_them", false)), true)

	# Your bag: tap to offer / take back
	var bag := UIKit.section(v, "YOUR BAG  (tap to offer, up to %d)" % Net.TRADE_MAX_ITEMS)
	var grid := GridContainer.new()
	grid.columns = 11
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	bag.add_child(grid)
	var p = GameState.player
	var items: Array = p.inventory.filter(func(it): return it != null) if is_instance_valid(p) else []
	if items.is_empty():
		bag.add_child(UIKit.label("Your bag is empty.", 14, UIKit.TEXT_DIM))
	for it in items:
		var uid: String = it.to_dict().uid  # gives it its id if it has none yet
		var cell := UIKit.item_cell(it, uid in _offer, CELL)
		cell.clicked.connect(func():
			if uid in _offer:
				_offer.erase(uid)
			elif _offer.size() < Net.TRADE_MAX_ITEMS:
				_offer.append(uid)
			Net.trade_offer(_offer))
		grid.add_child(cell)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var ready_me := bool(_state.get("ready_me", false))
	var ready := UIKit.button("✔  Ready" if not ready_me else "Not ready", Color(0.14, 0.34, 0.18) if not ready_me else Color(0.22, 0.20, 0.10),
		Color(0.40, 1.0, 0.55) if not ready_me else Color(0.90, 0.80, 0.40), Vector2(0, 50), 17)
	ready.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready.pressed.connect(func(): Net.trade_ready(not ready_me))
	row.add_child(ready)
	var cancel := UIKit.button("Cancel", Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30), Vector2(160, 50), 17)
	cancel.pressed.connect(Net.trade_cancel)
	row.add_child(cancel)
	v.add_child(UIKit.label("The trade happens when you are both ready; anything changed makes you both look again. What you get goes to your stash.",
		12, UIKit.TEXT_DIM, true))


func _side(parent: Control, title: String, offer: Array, ready: bool, theirs: bool) -> void:
	var sec := UIKit.section(parent, title + ("   ✔ READY" if ready else ""))
	sec.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	sec.add_child(grid)
	for i in Net.TRADE_MAX_ITEMS:
		var it: ItemInstance = ItemInstance.from_dict(offer[i]) if i < offer.size() and offer[i] is Dictionary else null
		var cell := UIKit.item_cell(it, false, CELL)
		if it != null:
			cell.clicked.connect(func():
				var p = GameState.player
				var mine: ItemInstance = p.equipment.get(p.equip_slot_for(it)) if theirs and is_instance_valid(p) else null
				var deltas := UIKit.equip_deltas(p, it) if mine != null else {}
				_tip.show_card(it, _win.get_viewport().get_mouse_position(), {}, Callable(), mine, deltas))
		grid.add_child(cell)
