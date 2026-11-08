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
## A zone you left is kept as you left it until you leave the game (ZoneInstances): going to one that is
## kept asks whether to carry on or start it over (InstanceChoice), unless you come back through a town
## portal, which always goes to the zone it was opened in. `on_cancel` is called if you back out of that
## question; `mode` ("continue" or "reset") answers it ahead.
static func travel(tree: SceneTree, zone: String, entry := "start", on_cancel := Callable(), mode := "") -> void:
	var keeps := zone != TOWN and ZONES.has(zone) and not Net.in_party()  # (a party's zone is its host's)
	var cur := tree.current_scene
	var same: bool = cur is Zone and cur.zone_id == zone  # died here: back to the waypoint, the zone as it is
	if keeps and mode == "" and entry != "portal" and not same and ZoneInstances.has(zone):
		InstanceChoice.ask(tree, zone_name(zone), ZoneInstances.describe(zone) + "\nCarry on where you left off, or start the area over?",
			func(m: String): travel(tree, zone, entry, on_cancel, m), on_cancel,
			"Continue", "Reset area", "Resetting brings back its monsters, its boss and what lay on the ground.")
		return
	GameState.save()
	tree.paused = false
	GameState.zone_entry = entry  # the town reads it too: arrive at its waypoint, exit or portal
	if not Net.in_party():
		ZoneInstances.stash_current(tree)  # the zone you are leaving, if it is a zone, is kept
	if zone == TOWN:
		GameState.current_zone = ""
		tree.change_scene_to_file.call_deferred("res://scenes/town.tscn")
		return
	GameState.current_zone = zone
	GameState.zone_entry = entry
	if keeps and mode == "reset":
		ZoneInstances.discard(zone)
	if keeps and ZoneInstances.has(zone):
		ZoneInstances.resume.call_deferred(tree, zone, entry)
		return
	tree.change_scene_to_file.call_deferred("res://scenes/zone.tscn")


## Zones with a waypoint you've touched, in story order.
static func known_waypoints() -> Array:
	var out: Array = []
	for id in ZONES:
		if id in GameState.waypoints:
			out.append(id)
	return out
