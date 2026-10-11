class_name ItemBase
extends Resource
## A base item type (Rusty Sword, Chain Mail...). Rolled items reference one of these.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("weapon", "offhand", "helmet", "chest", "gloves", "boots", "ring", "amulet") var slot: String = "weapon"
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


const TYPE_NAMES := {
	"sword": "Sword", "axe": "Axe", "mace": "Mace", "dagger": "Dagger",
	"staff": "Staff", "bow": "Bow", "shield": "Shield",
}


## e.g. "Two-Handed Axe", "One-Handed Sword", "Shield", or "" for armour.
func type_label() -> String:
	if weapon_type == "":
		return ""
	var n: String = TYPE_NAMES.get(weapon_type, weapon_type.capitalize())
	if weapon_type == "shield":
		return n
	return ("Two-Handed " if two_handed else "One-Handed ") + n
