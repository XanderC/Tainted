class_name HermitBench
extends CanvasLayer
## The Hermit's Sanctum's abandoned crafting bench (MiniDungeon): once, a free modification or socket reroll on any piece of gear you
## carry or wear. Pick the item, then what to do to it: its modifiers are rerolled with the orb that suits its rarity (Alchemy on a Normal
## item, Regal on a Magic one, Chaos on a Rare one, Divine on a Legendary, Set or runeword item), or its sockets with a
## Jeweller's Orb: none spent. `done` is called with a message once it has been used.

var player: Player
var done: Callable
var _sel: ItemInstance
var _list: VBoxContainer
var _info: Label
var _mods: Button
var _socks: Button
var _root: Control


static func open(zone: Node, p: Player, on_done: Callable) -> HermitBench:
	var b := HermitBench.new()
	b.player = p
	b.done = on_done
	zone.add_child(b)
	return b


func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UIKit.window_box(22, Color.WHITE, true))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	UIKit.window_header(v, "Abandoned bench", UIKit.GOLD, close, 22)
	v.add_child(UIKit.label("The hermit's tools, still sharp. One free reroll: choose a piece of gear.", 15, UIKit.TEXT_DIM, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_info = UIKit.label("", 15, Color(0.9, 0.85, 0.6), true)
	v.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_mods = UIKit.button("Reroll modifiers", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 46), 16)
	_mods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mods.disabled = true
	_mods.pressed.connect(func(): _use(false))
	row.add_child(_mods)
	_socks = UIKit.button("Reroll sockets", Color(0.20, 0.16, 0.08), Color(0.85, 0.70, 0.30), Vector2(0, 46), 16)
	_socks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_socks.disabled = true
	_socks.pressed.connect(func(): _use(true))
	row.add_child(_socks)
	_fill()


## The gear: worn first, then the bag.
func gear() -> Array:
	var out: Array = []
	for slot in player.equipment:
		if player.equipment[slot] != null:
			out.append(player.equipment[slot])
	for it in player.inventory:
		if it != null and not out.has(it):
			out.append(it)
	return out


## The orb that rerolls an item's modifiers, by its rarity.
static func mod_orb(item: ItemInstance) -> String:
	if item.is_unique():
		return "divine"
	match item.rarity:
		ItemInstance.Rarity.NORMAL:
			return "alchemy"
		ItemInstance.Rarity.MAGIC:
			return "regal"
	return "chaos"


func _fill() -> void:
	for item in gear():
		var b := UIKit.button(item.display_name if item.identified else "Unidentified " + item.base.display_name, Color(0.12, 0.10, 0.08), Color(0.4, 0.35, 0.25), Vector2(0, 38), 15)
		b.add_theme_color_override("font_color", ItemInstance.RARITY_COLORS.get(item.rarity, Color.WHITE))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var worn: bool = player.equipment.values().has(item)
		if worn:
			b.text += "   (worn)"
		b.pressed.connect(func(): _select(item))
		_list.add_child(b)
	if _list.get_child_count() == 0:
		_list.add_child(UIKit.label("You carry nothing to work on.", 15, UIKit.TEXT_DIM))


func _reason(item: ItemInstance, orb: String) -> String:
	if item.corrupted:
		return "Corrupted items can't be changed"
	if item.mirrored:
		return "Mirrored items can't be changed"
	var probe := item.identified
	item.identified = true  # (the bench reads it for you)
	var why := Crafting.orb_block_reason(item, orb)
	item.identified = probe
	return why


func _select(item: ItemInstance) -> void:
	_sel = item
	var why_m := _reason(item, mod_orb(item))
	var why_s := _reason(item, "jeweller")
	_mods.disabled = why_m != ""
	_socks.disabled = why_s != ""
	_info.text = "%s: %s" % [item.display_name, why_m if why_m != "" and why_s != "" else "choose what to do"]


func _use(sockets: bool) -> void:
	if _sel == null:
		return
	if not _sel.identified:
		_sel.identify()
	var res := Crafting.apply_orb(player, _sel, "jeweller" if sockets else mod_orb(_sel), true)
	if not res.ok:
		_info.text = String(res.msg)
		return
	var msg := "The bench works its old magic. %s" % String(res.msg)
	close()
	if done.is_valid():
		done.call(msg)


func close() -> void:
	get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
