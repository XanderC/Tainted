class_name HudLayout
extends RefCounted
## Where the top-right of the screen's controls sit, so they don't fall over each other: the minimap in the
## corner (Minimap), and left of it one row of buttons: the bag and options as icons, then the passive tree,
## then the town portal scroll (or, in town, the character screen). The party list is on the left instead,
## under the hireling (PartyUI.dock). Put a control there with place(); anything else that sits at the top right
## starts under BELOW_MAP.

const MARGIN := 12.0
const MAP := 168.0  ## the minimap's side
const ROW_TOP := 12.0
const ROW_H := 48.0
const GAP := 6.0
const BELOW_MAP := ROW_TOP + MAP + 10.0  ## the top of what sits under the minimap, at the right
const BELOW_ROW := ROW_TOP + ROW_H + 8.0  ## where the minimap's whole-map view starts: under the row of buttons

## Left from the minimap, in this order, with each one's width.
const ORDER := ["bag", "options", "passives", "scroll"]
const WIDTH := {"bag": 48.0, "options": 48.0, "passives": 108.0, "scroll": 88.0}


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
