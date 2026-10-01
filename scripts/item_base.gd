class_name ItemBase
extends Resource
## A base item type (Rusty Sword, Chain Mail...). Rolled items reference one of these.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("weapon", "helmet", "chest", "gloves", "boots", "ring", "amulet") var slot: String = "weapon"
@export var implicit_stat: String = ""
@export var implicit_value: float = 0.0
## Placeholder colour until you assign real Kenney/itch.io art.
@export var color: Color = Color.WHITE
## Set this once you have art: res://assets/kenney/....png
@export var icon: Texture2D
