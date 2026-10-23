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
	"ring2": "Finger Ring",
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
	"ring2": "💍",
	"amulet": "📿",
	"belt": "🎗",
	"flask": "🧪",
}

const GOLD := Color(0.95, 0.82, 0.45)
## Windows, panels, buttons, tabs and slots: the CraftPix RPG & MMO UI pack (tools/import_mmo_ui.py)
const MMO := "res://assets/ui/mmo/"
static var _mmo := {}


## The silhouette of what goes in an equipment slot (both ring slots share one), or null.
static func slot_icon(slot: String) -> Texture2D:
	var path := MMO + "slot_icons/" + ("ring" if slot.begins_with("ring") else slot) + ".png"
	return mmo("slot_icons/" + ("ring" if slot.begins_with("ring") else slot)) if ResourceLoader.exists(path) else null


## Fonts (assets/fonts, SIL Open Font License): Lora, a serif made for reading on screens, for all text;
## Cinzel, Roman capitals, for window titles and tabs.
## A ▲ / ▼ in rich text goes through ARROW_FONT: Cinzel has none, so they always come from the system's
## fallback font at a normal size (whatever the text's own font draws for them).
const FONTS := "res://assets/fonts/"
const ARROW_FONT := "res://assets/fonts/Cinzel.ttf"
static var _fonts := {}


## Lora at `weight` (400 regular, 500 medium, 600 semi-bold, 700 bold), upright or italic.
static func body_font(weight := 500, italic := false) -> Font:
	return _font("Lora-Italic" if italic else "Lora", weight)


## Cinzel, bold: window titles and tabs (its "1" looks like an "I", so not for text with numbers).
static func title_font() -> Font:
	return _font("Cinzel", 700)


static func _font(file: String, weight: int) -> Font:
	var key := "%s@%d" % [file, weight]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load(FONTS + file + ".ttf")
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]


## A texture from assets/ui/mmo by name ("window", "slot", ...).
static func mmo(name: String) -> Texture2D:
	if not _mmo.has(name):
		_mmo[name] = load(MMO + name + ".png")
	return _mmo[name]

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
	# Bevel plate, coloured by the accent the caller chose (green for allocate, red for close, ...)
	var tint := Color(0.36, 0.38, 0.42).lerp(Color(border.r, border.g, border.b), 0.5)
	b.add_theme_stylebox_override("normal", stone_box("menu_btn", tint))
	b.add_theme_stylebox_override("hover", stone_box("menu_btn", tint.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", stone_box("menu_btn_pressed", tint))
	b.add_theme_stylebox_override("disabled", stone_box("menu_btn", tint.darkened(0.45)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.45))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 3)
	return b


## A plain button: the pack's bevel plate in dark slate, stretched with its corners kept.
static func stone_button(text: String, min_size := Vector2(0, 46), font := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_color", Color(0.95, 0.88, 0.70))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 3)
	var slate := Color(0.36, 0.38, 0.42)
	b.add_theme_stylebox_override("normal", stone_box("menu_btn", slate))
	b.add_theme_stylebox_override("hover", stone_box("menu_btn", slate.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", stone_box("menu_btn_pressed", slate))
	b.add_theme_stylebox_override("disabled", stone_box("menu_btn", slate.darkened(0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.45))
	return b


## A button face (`art` "menu_btn", or "menu_btn_pressed" for held down): the pack's greyscale
## bevel plate, coloured by `tint`.
static func stone_box(art: String, tint := Color(0.36, 0.38, 0.42)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = mmo("button")
	s.set_texture_margin_all(10.0)
	s.set_content_margin_all(8.0)
	s.modulate_color = tint.darkened(0.25) if art == "menu_btn_pressed" else tint
	return s


## A tab's face: the open one glows with a bright rule along its foot, the others are bare.
static func tab_box(active: bool) -> StyleBox:
	if not active:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(6.0)
		return e
	var s := StyleBoxTexture.new()
	s.texture = mmo("tab_active")
	s.set_texture_margin_all(6.0)
	s.set_content_margin_all(6.0)
	return s


## A tab button's label in the title font (with tab_box for its face).
static func tab_font(b: Button) -> void:
	b.add_theme_font_override("font", title_font())


## Text colour of a tab's label.
static func tab_font_color(active: bool) -> Color:
	return Color(0.96, 0.93, 0.85) if active else Color(0.62, 0.62, 0.64)


## The card frame of a tooltip (ItemTip).
static func tooltip_box() -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = mmo("tooltip")
	s.set_texture_margin_all(10.0)
	s.set_content_margin_all(14.0)
	return s


## A window: dark, with a thin gold edge, stretched with its border kept. `tint` recolours it (a
## rift's purple, say). `header` gives it the title band along the top, scrollwork in its corners and
## a gold rule beneath, which a row of tabs or a title and close button sit on (the content starts
## inside the band, so put that row first).
static func window_box(content := 20.0, tint := Color.WHITE, header := false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.set_content_margin_all(content)
	if header:
		s.texture = mmo("window_header")
		s.texture_margin_left = 190.0  # the scrollwork in each corner keeps its shape
		s.texture_margin_right = 190.0
		s.texture_margin_top = 83.0
		s.texture_margin_bottom = 12.0
		s.content_margin_top = 19.0  # centres the header row on the band
	else:
		s.texture = mmo("window")
		s.set_texture_margin_all(12.0)
	s.modulate_color = tint
	return s


## The height of a window's header row, which sits on the title band, and the gap under it that
## keeps the body clear of the band.
const HEADER_ROW_H := 50.0
const HEADER_GAP := 14.0


static func header_gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, HEADER_GAP)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A window's header row, on its title band: the title, then a close button when `on_close` is
## given, then the gap that clears the band. Returns the row, to add more to it (its title
## label is the child named "Title").
static func window_header(parent: Control, title: String, col := Color(0.95, 0.80, 0.40), on_close := Callable(),
		font := 22) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, HEADER_ROW_H)
	parent.add_child(row)
	# The title in the middle of the band (a spacer the close button's width keeps it centred)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(44, 0) if on_close.is_valid() else Vector2.ZERO
	row.add_child(pad)
	var l := label(title.to_upper(), font, col)
	l.name = "Title"  # found by name: a spacer comes before it
	l.add_theme_font_override("font", title_font())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if on_close.is_valid():
		var c := close_button(1.0)
		c.pressed.connect(on_close)
		row.add_child(c)
	parent.add_child(header_gap())
	return row


## The game's theme, set on the root window (GameState does): its fonts for all text (rich text gets
## bold and italic Lora), and scrollbars in the pack's style for every ScrollContainer.
## Text drawn by hand (the HUD, names over heads) uses ThemeDB.fallback_font, set to the same font.
static func ui_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()  # the engine's own theme uses Lora too (project.godot gui/theme/custom_font)
	t.set_font("bold_font", "RichTextLabel", body_font(700))
	t.set_font("italics_font", "RichTextLabel", body_font(500, true))
	t.set_font("bold_italics_font", "RichTextLabel", body_font(700, true))
	ThemeDB.fallback_font = body_font()
	var track := StyleBoxTexture.new()
	track.texture = HudArt.tex("scroll_bar")
	track.texture_margin_top = 12.0
	track.texture_margin_bottom = 12.0
	track.content_margin_left = 6.0
	track.content_margin_right = 6.0
	var grab := StyleBoxTexture.new()
	grab.texture = HudArt.tex("scroll_handle")
	grab.texture_margin_top = 10.0
	grab.texture_margin_bottom = 10.0
	var grab_lit := grab.duplicate() as StyleBoxTexture
	grab_lit.modulate_color = Color(1.25, 1.15, 1.0)
	for k in ["scroll", "scroll_focus"]:
		t.set_stylebox(k, "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_lit)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_lit)
	return t


## The pack's square close button, for a window's header.
static func close_button(scale := 1.2) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = mmo("close")
	b.texture_hover = mmo("close_hover")
	b.texture_pressed = mmo("close_pressed")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(46, 46) * scale
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A section inside a window (the pack's list row: a faint lighter panel with a dark edge).
static func inset_box(content := 10.0, tint := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = mmo("inset")
	s.set_texture_margin_all(4.0)  # small, so a one-line banner keeps its corners
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
		var h := label(title, 15, GOLD)
		h.add_theme_font_override("font", body_font(700))
		v.add_child(h)
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
		cell.setup(item.base.icon, col, item.base.color.darkened(0.72), 0, item.display_name)  # tapping shows its card (GameMenu.show_item_tip)
		if item.dye != "":
			cell.set_dye(item.dye, item.base.icon)
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
		return " [color=#4ade80][font=%s]▲[/font][/color]" % ARROW_FONT
	if d < -eps:
		return " [color=#f87171][font=%s]▼[/font][/color]" % ARROW_FONT
	return ""


## `have`: the attributes to judge its requirements by (red where short); empty means the player's.
static func item_card(parent: Node, item: ItemInstance, compact := false, deltas := {}, have := {}) -> void:
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
	if have.is_empty() and is_instance_valid(GameState.player):
		have = GameState.attribute_totals()
	var req := Attributes.requirement_bbcode(item.base, have)
	if req != "":
		txt += req + "\n"
	if item.is_flask():
		# What drinking it does, modifiers included, then the modifiers themselves below
		var e := item.flask_effect()
		txt += "[color=#f3e6c4]%s[/color]\n[color=#9ca3af]Cooldown %.1fs[/color]\n" % [item.flask_text("Mana"), float(e.cooldown)]
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
	# Main attributes first, in their own colours (Diablo III's primary stat), then the other modifiers
	var shown: Array = item.affixes if item.identified else []
	for a in shown.filter(func(x): return LootGenerator.is_main_attribute(x)):
		txt += "[color=#%s][b]%s[/b][/color]%s\n" % [Attributes.COLORS.get(String(a.stat), Color.WHITE).lightened(0.2).to_html(false),
			a.text, stat_arrow(a.stat, deltas)]
	for a in shown.filter(func(x): return not LootGenerator.is_main_attribute(x)):
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
	if DyeDB.dyed(item):
		txt += "[color=#%s]🎨 Dyed %s[/color]\n" % [DyeDB.color(item.dye).lightened(0.25).to_html(false), DyeDB.dye_name(item.dye)]
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
		t += "[color=#%s]  [font=%s]%s[/font] %s %s[/color]\n" % [col, ARROW_FONT, "▲" if d > 0.0 else "▼", txt, STAT_LABELS[k]]
	if t == "":
		t = "[color=#777777]  No changes to core combat stats[/color]\n"
	return t
