class_name MazeLibrary
extends RefCounted
## Which maps the rifts use. The maps themselves are JSON files in res://maps/ (see MapData),
## made with the map editor (tools/map_editor). Rifts pick a random map of kind "rift".


## A random rift map id, different from `avoid` when there is a choice.
static func random_name(avoid := "") -> String:
	var ids := MapData.ids("rift")
	if ids.size() > 1:
		ids.erase(avoid)
	return ids.pick_random() if not ids.is_empty() else ""
