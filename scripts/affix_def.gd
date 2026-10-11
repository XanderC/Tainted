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
## Flask modifiers ("flask" in slots) work differently: they change what drinking it does, and
## a flask takes at most one prefix and one suffix when Magic, two of each when Rare.
## Slots it can roll on; empty means any gear but a flask.
@export var slots: Array[String] = []
## Flasks: the kinds it suits ("life", "power", "utility"); empty means all.
@export var flask_kinds: Array[String] = []
@export var prefix := true
## The word it adds to a Magic flask's name: "Ample" (prefix) or "of Haste" (suffix).
@export var word := ""


## Whether it can roll on this base.
func fits(b: ItemBase) -> bool:
	if b.slot == "flask":
		return slots.has("flask") and (flask_kinds.is_empty() or flask_kinds.has(String(b.flask.get("kind", ""))))
	return slots.is_empty() or slots.has(b.slot)
