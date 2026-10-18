class_name MapData
extends RefCounted
## Maps are JSON files in res://maps/ (made with the map editor in tools/map_editor). One file per
## map, plus maps/index.json listing them all. A map:
## {
##   "format": 1, "id": "tutorial", "name": "Tutorial", "kind": "rift" | "story" | "special",
##   "theme": "desert", "cell": 128, "auto_decorate": true,
##   "grid": ["#####", "#...#", ...],          # "#" wall, "." floor; every row the same width
##   "objects": [                               # x, y in world pixels
##     {"type": "start", "x", "y"},             # where the player appears
##     {"type": "portal", "x", "y", "target"},  # rift: "" = next random maze; story: a map id or "town"
##     {"type": "pack", "x", "y", "min", "max"},          # a monster group (rifts use some of them)
##     {"type": "marker", "x", "y", "id"},                # a named spot scripts can look up
##     {"type": "prop", "x", "y", "sprite", "scale", "solid"},  # a picture from assets/tiles/<theme>
##     {"type": "tile", "x", "y", "sprite", "scale"},  # flat ground piece (land_ / road_), x, y = top-left
##     {"type": "npc", "x", "y", "id", "name", "dialogue"},
##     {"type": "trigger", "x", "y", "radius", "id", "text"},   # a story event when the player walks in
##     {"type": "waypoint", "x", "y"},                           # story zones: the zone's waypoint
##     {"type": "boss", "x", "y", "id", "name", "kind", "skin", "hp", "size"},  # a quest boss
##     {"type": "quest_object", "x", "y", "id", "sprite", "scale", "prompt", "text"}  # used for a quest
##   ]
## }

const DIR := "res://maps/"
const FORMAT := 1
const KINDS := ["rift", "story", "special"]
const OBJECT_TYPES := ["start", "portal", "pack", "marker", "prop", "tile", "npc", "trigger", "waypoint", "boss", "quest_object"]

static var _cache := {}


## The map with this id ({} if missing).
static func load_map(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := DIR + id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Map not found: " + path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Bad map file: " + path)
		return {}
	_cache[id] = data
	return data


## Map ids of one kind ("" = all), from maps/index.json.
static func ids(kind := "") -> Array[String]:
	var out: Array[String] = []
	var idx = JSON.parse_string(FileAccess.get_file_as_string(DIR + "index.json")) if FileAccess.file_exists(DIR + "index.json") else null
	if typeof(idx) == TYPE_DICTIONARY:
		for id in idx.get("maps", {}):
			if kind == "" or String(idx.maps[id].get("kind", "")) == kind:
				out.append(String(id))
	return out


static func objects_of(map: Dictionary, type: String) -> Array:
	return map.get("objects", []).filter(func(o): return String(o.get("type", "")) == type)
