class_name ClassDef
extends Resource
## A playable class: starting stats plus its skill list.

@export var id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var base_stats: Dictionary = {}
## Index 0 = basic auto-attack. Indexes 1+ = tappable skill buttons.
@export var skills: Array[SkillDef] = []
