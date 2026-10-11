class_name ItemBase
extends Resource
## A base item type (Rusty Sword, Chain Mail...). Rolled items reference one of these.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("weapon", "offhand", "helmet", "chest", "gloves", "boots", "ring", "amulet", "belt", "flask") var slot: String = "weapon"
## Weapons and shields: "sword", "axe", "mace", "dagger", "staff", "bow", "shield". "" for armour.
## Each class lists the types it may use (ClassDef.weapon_types).
@export var weapon_type: String = ""
@export var two_handed: bool = false
@export var implicit_stat: String = ""
@export var implicit_value: float = 0.0
## Placeholder colour until you assign real Kenney/itch.io art.
@export var color: Color = Color.WHITE
## Set this once you have art: res://assets/kenney/....png
@export var icon: Texture2D
## Cells it takes in the bag and stash (columns x rows). Zero means the usual size for its kind,
## from bag_size().
@export var grid_size := Vector2i.ZERO
## How often it drops, against other bases (100 = usual).
@export var weight := 100
## Belts: how many flask slots wearing it opens (Player.FLASK_SLOTS at most).
@export var flask_slots := 0
## Flasks: what drinking it does. Keys:
##   kind      - "life" | "power" | "utility"
##   amount    - life: fraction of max life; power: resource; utility: the buff's value
##   duration  - seconds the recovery takes / the buff lasts
##   cooldown  - seconds before it can be used again
##   stat, mod - utility: the stat buffed and how (StatBlock.ModType)
##   text      - utility: the buff, with {v} for its value
##   tier      - 1..3, for the icon
@export var flask := {}


const TYPE_NAMES := {
	"sword": "Sword", "axe": "Axe", "mace": "Mace", "dagger": "Dagger",
	"staff": "Staff", "bow": "Bow", "shield": "Shield",
}


## Bag footprint by kind of item, Diablo II style: jewellery is one cell, a dagger two, swords
## and axes a long column, two-handers and body armour a big block.
const WEAPON_SIZES := {
	"dagger": Vector2i(1, 2),
	"sword": Vector2i(1, 3), "axe": Vector2i(1, 3), "mace": Vector2i(1, 3),
	"staff": Vector2i(1, 4), "bow": Vector2i(2, 3),
	"shield": Vector2i(2, 2),
}
const TWO_HANDED_SIZES := {
	"sword": Vector2i(2, 4), "axe": Vector2i(2, 3), "mace": Vector2i(2, 4),
}
const SLOT_SIZES := {
	"helmet": Vector2i(2, 2), "chest": Vector2i(2, 3), "gloves": Vector2i(2, 2),
	"boots": Vector2i(2, 2), "ring": Vector2i(1, 1), "amulet": Vector2i(1, 1),
	"belt": Vector2i(2, 1), "flask": Vector2i(1, 2),
	"weapon": Vector2i(1, 3), "offhand": Vector2i(2, 2),
}


## Cells this base takes in the bag: its own grid_size if set, otherwise the size for its kind.
func bag_size() -> Vector2i:
	if grid_size.x > 0 and grid_size.y > 0:
		return grid_size
	if weapon_type != "":
		if two_handed and TWO_HANDED_SIZES.has(weapon_type):
			return TWO_HANDED_SIZES[weapon_type]
		if WEAPON_SIZES.has(weapon_type):
			return WEAPON_SIZES[weapon_type]
	return SLOT_SIZES.get(slot, Vector2i.ONE)


## e.g. "Two-Handed Axe", "One-Handed Sword", "Shield", or "" for armour.
func type_label() -> String:
	if weapon_type == "":
		return ""
	var n: String = TYPE_NAMES.get(weapon_type, weapon_type.capitalize())
	if weapon_type == "shield":
		return n
	return ("Two-Handed " if two_handed else "One-Handed ") + n
