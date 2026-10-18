class_name UIKit
extends RefCounted
## Shared look and building blocks for the menu screens (GameMenu and its panels):
## colours, panels, labels, item cards and stat comparison text.

const STAT_LABELS := {
	"max_life": "Max Life",
	"damage": "Damage",
	"attack_speed": "Attack Speed",
	"armor": "Armor",
	"crit_chance": "Critical Strike",
	"move_speed": "Movement Speed",
}

const SLOT_NAMES := {
	"helmet": "Helmet",
	"chest": "Body Armor",
	"weapon": "Main Hand",
	"offhand": "Off Hand",
	"gloves": "Gloves",
	"boots": "Boots",
	"ring": "Finger Ring",
	"amulet": "Amulet",
	"belt": "Belt",
	"flask": "Flask",
}

const SLOT_ICONS := {
	"helmet": "⛑",
	"chest": "🛡",
	"weapon": "⚔",
	"offhand": "🛡",
	"gloves": "🧤",
	"boots": "👢",
	"ring": "💍",
	"amulet": "📿",
	"belt": "🎗",
	"flask": "🧪",
}

const GOLD := Color(0.95, 0.82, 0.45)
const TEXT_DIM := Color(0.65, 0.58, 0.48)
const EMPTY_BORDER := Color(0.20, 0.18, 0.24)


static func box(bg: Color, border: Color, width := 1, corner := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(corner)
	return sb


static func label(text: String, size := 14, col := Color(0.9, 0.88, 0.82), wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rich(text: String, size := 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.text = text
	return r


static func button(text: String, bg: Color, border: Color, min_size := Vector2(0, 46), font := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font)
	# Stone face, coloured by the accent the caller chose (green for allocate, red for close, ...)
	var tint := Color(1, 1, 1).lerp(Color(border.r, border.g, border.b), 0.7)
	b.add_theme_stylebox_override("normal", stone_box("menu_btn", tint))
	b.add_theme_stylebox_override("hover", stone_box("menu_btn", tint.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", stone_box("menu_btn_pressed", tint))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 3)
	return b


## A button in the HUD's stone style (the pack's menu button, stretched with its corners kept).
static func stone_button(text: String, min_size := Vector2(0, 46), font := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 3)
	var normal := _stone_box("menu_btn")
	var pressed := _stone_box("menu_btn_pressed")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func _stone_box(art: String) -> StyleBoxTexture:
	return stone_box(art, Color.WHITE)


## The stone button face (`art` is "menu_btn" or "menu_btn_pressed"), recoloured by `tint`.
static func stone_box(art: String, tint := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = HudArt.tex(art)
	s.set_texture_margin_all(14.0)
	s.set_content_margin_all(8.0)
	s.modulate_color = tint
	return s


## The stone window frame, stretched with its border kept. `tint` recolours it (a rift's purple, say).
## `header` gives it the pack's title band along the top, which a row of tabs or a title and close
## button sit on (the content starts inside the band, so put that row first).
static func window_box(content := 20.0, tint := Color.WHITE, header := false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.set_content_margin_all(content)
	if header:
		s.texture = HudArt.tex("window_header")
		s.texture_margin_left = 24.0
		s.texture_margin_right = 24.0
		s.texture_margin_top = 80.0
		s.texture_margin_bottom = 24.0
		s.content_margin_top = 14.0
	else:
		s.texture = HudArt.tex("window_frame")
		s.set_texture_margin_all(24.0)
	s.modulate_color = tint
	return s


## The pack's stone close button, for a window's header.
static func close_button(scale := 1.2) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = HudArt.tex("close")
	b.texture_hover = HudArt.tex("close_hover")
	b.texture_pressed = HudArt.tex("close_pressed")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(47, 43) * scale
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A recessed dark panel (the pack's inner container), for cards and sections inside a window.
static func inset_box(content := 10.0, tint := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = HudArt.tex("panel_inset")
	s.set_texture_margin_all(8.0)  # small, so a one-line banner keeps its corners
	s.set_content_margin_all(content)
	s.modulate_color = tint
	return s


## A bordered section with a title; returns the inner VBox to fill.
static func section(parent: Control, title: String, expand := false) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand:
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := inset_box(10)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	if title != "":
		v.add_child(label(title, 16, GOLD))
	return v


static func grid(cols: int, sep := 5) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	return g


## Empties a container. Children are hidden (so layouts skip them at once) and freed at the end
## of the frame, which is safe even when called from one of those children's own signals.
static func clear(c: Node) -> void:
	for ch in c.get_children():
		if ch is CanvasItem:
			ch.visible = false
		ch.queue_free()


## Grid cell showing an item (or an empty slot when item is null). Payload / drop are set by the caller.
static func item_cell(item: ItemInstance, selected: bool, size := Vector2(60, 60)) -> DragSlot:
	var cell := DragSlot.new(size)
	if item != null:
		var col: Color = Color.WHITE if selected else ItemInstance.RARITY_COLORS[item.rarity]
		cell.setup(item.base.icon, col, item.base.color.darkened(0.72), 0, item.display_name, item.display_name)
	else:
		cell.setup(null, EMPTY_BORDER)
	return cell


static func gem_tip(gid: String) -> String:
	var g := GemDef.info(gid)
	return "%s\n%s" % [g.get("name", gid), g.get("text", "")]


# ---------- item cards & comparison ----------

## Stat changes (stat -> delta) if `item` replaced what is worn in its slot.
static func equip_deltas(player: Player, item: ItemInstance) -> Dictionary:
	var cmp := player.preview_equip(item)
	var d := {}
	for k in STAT_LABELS:
		d[k] = float(cmp["after"][k]) - float(cmp["before"][k])
	return d


## Green ▲ if equipping the selected item raises this stat, red ▼ if it lowers it.
static func stat_arrow(stat: String, deltas: Dictionary) -> String:
	if not deltas.has(stat):
		return ""
	var d: float = deltas[stat]
	var eps := 0.005 if stat in ["crit_chance", "attack_speed"] else 0.5
	if d > eps:
		return " [color=#4ade80]▲[/color]"
	if d < -eps:
		return " [color=#f87171]▼[/color]"
	return ""


static func item_card(parent: Node, item: ItemInstance, compact := false, deltas := {}) -> void:
	var rar_col: Color = ItemInstance.RARITY_COLORS[item.rarity]
	var hdr := PanelContainer.new()
	var hdr_sb := inset_box(8, Color(1, 1, 1).lerp(rar_col, 0.55))
	hdr.add_theme_stylebox_override("panel", hdr_sb)
	parent.add_child(hdr)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hdr.add_child(hv)
	var name_lbl := label(item.display_name, 16 if compact else 19, rar_col, true)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(name_lbl)
	var kind := item.base.type_label()
	if kind == "":
		kind = SLOT_NAMES.get(item.base.slot, item.base.slot.capitalize())
	if item.is_unique():
		kind = "%s %s" % ["Legendary" if item.rarity == ItemInstance.Rarity.LEGENDARY else "Set", kind]
	elif item.is_runeword():
		kind = "Runeword %s" % kind
	var base_lbl := label("%s  •  Item Level %d" % [kind, item.ilvl],
		13, Color(0.75, 0.70, 0.65), true)
	base_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(base_lbl)

	var txt := ""
	if item.is_flask():
		# What drinking it does, modifiers included, then the modifiers themselves below
		var e := item.flask_effect()
		var pn: String = GameState.player.class_def.power_name if is_instance_valid(GameState.player) else "Power"
		txt += "[color=#f3e6c4]%s[/color]\n[color=#9ca3af]Cooldown %.1fs[/color]\n" % [item.flask_text(pn), float(e.cooldown)]
	if item.base.flask_slots > 0:
		txt += "[color=#f3e6c4]Opens %d flask slot%s[/color]\n" % [item.base.flask_slots, "" if item.base.flask_slots == 1 else "s"]
	if item.quality > 0:
		txt += "[color=#9ab0d0]Quality: +%d%%[/color]\n" % item.quality
	if item.base.implicit_stat != "":
		txt += "[color=#ffffff]+%d %s[/color]%s [color=#777777](implicit)[/color]\n" % [
			int(item.implicit_value()), item.base.implicit_stat.replace("_", " ").capitalize(),
			stat_arrow(item.base.implicit_stat, deltas)]
	if not item.identified:
		txt += "[color=#e04848][b]Unidentified[/b][/color]\n[color=#8a7f6e]Its modifiers are hidden. Use a Scroll of Identify, or the Sage in town identifies everything for free.[/color]\n"
	for a in (item.affixes if item.identified else []):
		txt += "[color=#7ba6ff]• %s[/color]%s\n" % [a.text, stat_arrow(a.stat, deltas)]
	if item.is_unique() and item.identified:
		var worn: Array = GameState.player.equipment.values() if is_instance_valid(GameState.player) else []
		txt += UniqueItems.card_bbcode(item, worn)
	txt += Runewords.card_bbcode(item)
	for i in item.sockets:
		if i < item.gems.size():
			var g := item.socket_info(item.gems[i])
			var rune_name := "%s: " % g.get("short", "") if g.get("rune", false) else ""
			txt += "[color=#%s]◆ %s%s[/color]%s\n" % [Color(g.get("color", Color.WHITE)).to_html(false),
				rune_name, g.get("text", "?"), stat_arrow(g.get("stat", ""), deltas)]
		else:
			txt += "[color=#666677]◇ Empty Socket[/color]\n"
	if item.affixes.is_empty() and item.base.implicit_stat == "" and item.sockets == 0:
		txt += "[color=#555555]No magical properties[/color]\n"
	if item.corrupted:
		txt += "[color=#e04848][b]Corrupted[/b][/color]\n"
	if item.mirrored:
		txt += "[color=#a8e6ff][b]Mirrored[/b][/color]\n"
	parent.add_child(rich(txt))


## "▲ +5 Damage" style list of what equipping `item` changes.
static func delta_bbcode(player: Player, item: ItemInstance) -> String:
	var deltas := equip_deltas(player, item)
	var t := ""
	for k in STAT_LABELS:
		var d: float = deltas[k]
		var txt := ""
		match k:
			"crit_chance":
				var pct := int(round(d * 100.0))
				if pct == 0:
					continue
				txt = "%+d%%" % pct
			"attack_speed":
				if absf(d) < 0.005:
					continue
				txt = "%+.2f /s" % d
			_:
				var whole := int(round(d))
				if whole == 0:
					continue
				txt = "%+d" % whole
		var col := "4ade80" if d > 0.0 else "f87171"
		t += "[color=#%s]  %s %s %s[/color]\n" % [col, "▲" if d > 0.0 else "▼", txt, STAT_LABELS[k]]
	if t == "":
		t = "[color=#777777]  No changes to core combat stats[/color]\n"
	return t
