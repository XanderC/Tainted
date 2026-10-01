class_name AffixDef
extends Resource
## One possible random modifier an item can roll.

@export var id: String = ""
## Text with a {v} placeholder, e.g. "+{v} Max Life" or "{v}% Increased Damage".
@export var display: String = ""
@export var stat: String = ""
@export_enum("FLAT", "INCREASED", "MORE") var mod_type: int = 0
@export var min_value: float = 1.0
@export var max_value: float = 1.0
## Minimum item level for this affix to appear (higher = better tiers later).
@export var min_ilvl: int = 1
## If true, values are fractions shown as percent (0.10 -> "10").
@export var is_percent: bool = false
@export var weight: int = 100
