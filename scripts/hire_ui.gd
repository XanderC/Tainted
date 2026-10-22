class_name HireUI
extends CanvasLayer
## The Mercenary Captain in Ashfall: take on a hireling (Hirelings), revive a fallen one, or swap
## yours for another. A tab per type (HirelingDB.ORDER); types the story hasn't opened yet say what
## opens them. Each type has a few on offer, with the skill gems they come with and their price.

const CARD_W := 330.0

var player: Player
var _root: Control
var _body: VBoxContainer
var _feedback: Label
var _type := "sellsword"


func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _root.visible:
		close()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if Hirelings.has():
		_type = Hirelings.type_id()
	_feedback.visible = false
	_root.visible = true
	get_tree().paused = true
	_refresh()


func close() -> void:
	_root.visible = false
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.visible = false
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.window_box(20, Color.WHITE, true))
	margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	UIKit.window_header(v, "⚔ MERCENARY CAPTAIN  —  HIRELINGS", UIKit.GOLD, close, 22)
	_feedback = UIKit.label("", 15, Color(1.0, 0.85, 0.40), true)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.visible = false
	v.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)


func _say(msg: String) -> void:
	_feedback.text = msg
	_feedback.visible = true


func _refresh() -> void:
	UIKit.clear(_body)
	_add_current()
	_add_tabs()
	_add_offers()


## Who you have now: their level and life, or that they have fallen, with Revive.
func _add_current() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.inset_box(12))
	_body.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var text := UIKit.rich("", 16)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	if not Hirelings.has():
		text.text = "[color=#bdb6aa]You have no hireling. Pick one below: they follow you, fight beside you and level up with you. You can have one at a time.[/color]"
		return
	var h := GameState.hireling
	if Hirelings.alive():
		text.text = "[color=#ffd54a][b]%s[/b][/color]  [color=#bdb6aa]Level %d, at your side.[/color]\n[color=#8a7f6e]Hiring someone else sends them away: their gear comes back to your bag and their support gems to your stash.[/color]" % [
			Hirelings.title(), Hirelings.level()]
		return
	var price := Hirelings.revive_price()
	text.text = "[color=#f87171][b]%s has fallen.[/b][/color]  [color=#bdb6aa]Level %d. Their gear is safe with them.[/color]\n[color=#bdb6aa]Revive for %s, or hire someone new.[/color]" % [
		String(h.get("name", "")), Hirelings.level(), Currency.price_text(price)]
	var rv := UIKit.button("✚ Revive", Color(0.12, 0.26, 0.14), Color(0.45, 0.95, 0.55), Vector2(150, 56), 19)
	rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rv.disabled = not GameState.can_afford(price)
	rv.pressed.connect(func():
		if Hirelings.revive(player):
			_say("%s is back on their feet." % String(GameState.hireling.get("name", "")))
		_refresh())
	row.add_child(rv)


func _add_tabs() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for id in HirelingDB.ORDER:
		var t := HirelingDB.type_def(id)
		var open := HirelingDB.unlocked(id)
		var active: bool = id == _type
		var b := Button.new()
		b.text = ("" if open else "🔒 ") + String(t.name)
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		var face := UIKit.tab_box(active)
		UIKit.tab_font(b)
		b.add_theme_stylebox_override("normal", face)
		b.add_theme_stylebox_override("hover", face)
		b.add_theme_stylebox_override("pressed", UIKit.tab_box(true))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.70) if active else (Color(0.70, 0.65, 0.60) if open else Color(0.50, 0.46, 0.42)))
		b.tooltip_text = String(t.desc) if open else String(t.unlock_text)
		b.pressed.connect(func():
			_type = id
			_refresh())
		tabs.add_child(b)


func _add_offers() -> void:
	var t := HirelingDB.type_def(_type)
	_body.add_child(UIKit.label(String(t.desc), 15, Color(0.85, 0.80, 0.72), true))
	if not HirelingDB.unlocked(_type):
		_body.add_child(UIKit.label("🔒 Not for hire yet: %s." % String(t.unlock_text), 16, Color(0.95, 0.65, 0.40), true))
		return
	var gear := "Wears: %s.  Fights with: %s." % [
		", ".join(PackedStringArray((t.slots as Array).map(func(s): return String(UIKit.SLOT_NAMES.get(s, s))))),
		", ".join(PackedStringArray((t.weapons as Array).map(func(w): return String(ItemBase.TYPE_NAMES.get(w, w)).to_lower() + "s")))]
	if bool(t.get("one_handed", false)):
		gear += " One-handed only."
	_body.add_child(UIKit.label(gear, 13, UIKit.TEXT_DIM, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	for c in Hirelings.candidates(_type):
		row.add_child(_card(c))


## One hireling on offer: name, level, stats, its skill gems (main attack first) and price.
func _card(c: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(CARD_W, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", UIKit.inset_box(10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	var lvl := int(c.level)
	v.add_child(UIKit.label("%s  •  Level %d" % [String(c.name), lvl], 18, UIKit.GOLD))
	var st := HirelingDB.stats_at(String(c.type), lvl)
	v.add_child(UIKit.rich("[color=#bdb6aa]Life[/color] [b]%d[/b]   [color=#bdb6aa]Damage[/color] [b]%d[/b]   [color=#bdb6aa]Armour[/color] [b]%d[/b]" % [
		int(st.max_life), int(st.damage), int(st.armor)], 14))
	var attrs := HirelingDB.base_attributes(String(c.type))
	var pts := Attributes.POINTS_PER_LEVEL * (lvl - 1)
	v.add_child(UIKit.label("Str %d   Dex %d   Vit %d   (+%d points for you to add)" % [int(attrs.str), int(attrs.dex), int(attrs.vit), pts],
		13, UIKit.TEXT_DIM))
	var skills: Array = c.skills
	for i in skills.size():
		var sk := SkillTree.get_skill(String(skills[i]))
		if sk == null:
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		v.add_child(line)
		var icon := DragSlot.new(Vector2(36, 36))
		icon.setup(IconFactory.gem_icon("skill:" + sk.id, sk.color, 3), sk.color, Color(sk.color).darkened(0.85), 0, "", sk.description)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(icon)
		var name_l := UIKit.label(("⚔ " if i == 0 else "") + sk.display_name, 15, sk.color.lightened(0.25))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.tooltip_text = sk.description
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(name_l)
	var price := HirelingDB.hire_price(lvl)
	v.add_child(UIKit.rich("[color=#9a8f7e]Hire for[/color] " + Currency.price_text(price), 15))
	var why := Hirelings.hire_block_reason(c)
	var hire := UIKit.button("Hire %s" % String(c.name), Color(0.20, 0.15, 0.08), Color(0.95, 0.80, 0.40), Vector2(0, 50), 17)
	hire.disabled = why != ""
	hire.tooltip_text = why
	hire.pressed.connect(func():
		var old := Hirelings.title() if Hirelings.has() else ""
		if Hirelings.hire(player, c):
			_say(("%s joins you. %s went their way; their gear is in your bag." % [String(c.name), old]) if old != ""
				else "%s joins you." % String(c.name))
		_refresh())
	v.add_child(hire)
	return box
