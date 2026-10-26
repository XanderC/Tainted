class_name ActDB
extends RefCounted
## The story's zones: open areas played between towns (the Zone scene), each a map file (MapData)
## with an area level that sets its monsters' strength and loot. Exits between zones are the map's
## "portal" objects (target: a zone id or "town").

const TOWN := "town"
const TOWN_NAME := "Ashfall Outpost"

## id: name, act, map (MapData id), area_level
const ZONES := {
	"dune_wastes": {"name": "The Ashwood", "act": 1, "map": "dune_wastes", "area_level": 2},
}


static func zone(id: String) -> Dictionary:
	return ZONES.get(id, {})


static func zone_name(id: String) -> String:
	return TOWN_NAME if id == TOWN else String(ZONES.get(id, {}).get("name", id.capitalize()))


## Go to `zone` (a zone id or TOWN), arriving at `entry` (see GameState.zone_entry). Saves first.
static func travel(tree: SceneTree, zone: String, entry := "start") -> void:
	GameState.save()
	tree.paused = false
	GameState.zone_entry = entry  # the town reads it too: arrive at its waypoint, exit or portal
	if zone == TOWN:
		GameState.current_zone = ""
		tree.change_scene_to_file.call_deferred("res://scenes/town.tscn")
		return
	GameState.current_zone = zone
	GameState.zone_entry = entry
	tree.change_scene_to_file.call_deferred("res://scenes/zone.tscn")


## Zones with a waypoint you've touched, in story order.
static func known_waypoints() -> Array:
	var out: Array = []
	for id in ZONES:
		if id in GameState.waypoints:
			out.append(id)
	return out
