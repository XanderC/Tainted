class_name HudLayout
extends RefCounted
## Where the top-right of the screen's controls sit, so they don't fall over each other: the minimap in the
## corner (Minimap), and left of it one row of icon buttons, all the same size (ICON): the bag, options and the
## passive tree, then (in town) the character screen. The town portal scroll is not in it: it sits just right of the
## mana globe (place_by_mana). The party list is on the left instead, under the hireling (PartyUI.dock). Put a
## control in the row with place(); anything else that sits at the top right starts under BELOW_MAP.

const MARGIN := 12.0
const MAP := 168.0  ## the minimap's side
const ROW_TOP := 12.0
const ICON := 48.0  ## every icon button's side
const ROW_H := ICON
const GAP := 6.0
const BELOW_MAP := ROW_TOP + MAP + 10.0  ## the top of what sits under the minimap, at the right
const BELOW_ROW := ROW_TOP + ROW_H + 8.0  ## where the minimap's whole-map view starts: under the row of buttons

## Left from the minimap, in this order, with each one's width.
const ORDER := ["bag", "options", "passives", "characters"]
const WIDTH := {"bag": ICON, "options": ICON, "passives": ICON, "characters": ICON}


## An icon button for the row or the mana globe: ICON square whatever the glyph is (the glyph can't grow it, as it
## did a stone button with its margins), so they all match.
static func icon_button(glyph: String, font := 26) -> Button:
	var b := UIKit.stone_button(glyph, Vector2(ICON, ICON), font)
	b.clip_text = true
	for st in ["normal", "hover", "pressed", "disabled"]:
		(b.get_theme_stylebox(st) as StyleBoxTexture).set_content_margin_all(1.0)
	return b


## Puts `c` in its slot of the row (anchored to the top right).
static func place(c: Control, slot: String) -> void:
	var right := MARGIN + MAP + 8.0
	for s in ORDER:
		if s == slot:
			break
		right += float(WIDTH[s]) + GAP
	var w: float = WIDTH[slot]
	c.custom_minimum_size = Vector2(w, ROW_H)
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_right = -right
	c.offset_left = -(right + w)
	c.offset_top = ROW_TOP
	c.offset_bottom = ROW_TOP + ROW_H


## Puts `c` just right of the mana globe (the right one of the bottom bar: HudBars), level with its widest part,
## anchored to the bottom of the screen like the globe. The skill buttons start further right.
static func place_by_mana(c: Control) -> void:
	var left := HudBars.row_width() * 0.5 + HudBars.ORB_R * 2.0 + 4.0 + 10.0  # from the screen's middle: the flask row, the globe, a gap
	c.custom_minimum_size = Vector2(ICON, ICON)
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = left
	c.offset_right = left + ICON
	# Level with the globe's middle (its centre is ORB_R * (1 - ORB_DROP) above the bottom edge)
	var mid := HudBars.ORB_R * (1.0 - HudBars.ORB_DROP)
	c.offset_top = -(mid + ICON * 0.5)
	c.offset_bottom = -(mid - ICON * 0.5)
