class_name MenuPanel
extends VBoxContainer
## Base for the content shown on the left half of the GameMenu (item details, runes, gems,
## stash, merchant, blacksmith...). The right half is always the CharacterPanel.

var menu: GameMenu
var player: Player


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


## Title shown above the panel and on its tab.
func panel_title() -> String:
	return ""


## Rebuild from current game state. Called whenever anything changes while the panel is shown.
func refresh() -> void:
	pass


## Lets the panel take drops onto the character's bag (e.g. buying a merchant ware).
func accepts_bag_drop(_d: Dictionary) -> bool:
	return false


func on_bag_drop(_d: Dictionary, _bag_idx: int) -> void:
	pass
