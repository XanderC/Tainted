class_name DropZone
extends Control
## The empty screen behind the GameMenu's windows: gear dragged out of the bag, off the paperdoll or
## out of a flask slot and let go here is dropped on the ground. (Replaces the drop box the
## paperdoll used to have.)

var menu: GameMenu


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind", "") == "item" and data.get("item") != null \
		and data.get("from", "") in ["bag", "gear", "flask"]


func _drop_data(_at: Vector2, data: Variant) -> void:
	var it: ItemInstance = data.get("item")
	menu.player.drop_item(it)
	menu.feedback("Dropped %s." % it.display_name)
	if menu.selected == it:
		menu.select(null)
	else:
		menu.refresh()
