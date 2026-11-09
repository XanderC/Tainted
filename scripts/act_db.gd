class_name ActDB
extends RefCounted
## The story's zones: open areas played between towns (the Zone scene), each a map file (MapData)
## with an area level that sets its monsters' strength and loot. Exits between zones are the map's
## "portal" objects (target: a zone id or "town").

const TOWN := "town"
const TOWN_NAME := "Oakhaven Outpost"

## id: name, act, map (MapData id), area_level, and kinds (the MonsterKinds a zone's packs are made of; without it,
## whatever its area level allows). Act I is The Bleeding Veil (ACT1_DESIGN.md). The first zone keeps its old id
## "dune_wastes" (saved waypoints and zone ids use it): it is the Blackroot Wilds.
## `xp_scale`: the experience of its monsters as a share of what their life works out to. Act I is paced so that a new character ends it
## on levels 12 to 17: its quests and bosses (BossDB "xp") give about 13,000 experience, and its monsters 8,000 more if you clear them
## (scratch/measure_xp.tscn adds it up).
const ZONES := {
	"dune_wastes": {"name": "Blackroot Wilds", "act": 1, "map": "dune_wastes", "area_level": 2, "xp_scale": 0.097,
		"kinds": ["briarwolf", "villager", "ghoul", "zombie", "skeleton"]},
	"weeping_hollow": {"name": "The Weeping Hollow", "act": 1, "map": "weeping_hollow", "area_level": 4, "xp_scale": 0.145,
		"kinds": ["cave_skitterer", "blind_crawler", "ghoul", "skeleton"]},
	"sunken_fen": {"name": "Sunken Fen", "act": 1, "map": "sunken_fen", "area_level": 4, "xp_scale": 0.078,
		"kinds": ["rot_bloat", "leechfiend", "fen_crawler", "villager", "zombie"]},
	"ashen_verge": {"name": "Ashen Verge", "act": 1, "map": "ashen_verge", "area_level": 6, "xp_scale": 0.076,
		"kinds": ["skeleton", "skeleton_warrior", "zombie", "ghoul", "bleed_fiend"]},
	"grand_ossuary_1": {"name": "Grand Ossuary", "act": 1, "map": "grand_ossuary_1", "area_level": 7, "xp_scale": 0.099,
		"kinds": ["skeleton", "skeleton_warrior", "skeleton_vanguard", "skeleton_archer", "ghoul", "veil_cultist"]},
	"grand_ossuary_2": {"name": "Lower Ossuary", "act": 1, "map": "grand_ossuary_2", "area_level": 8, "xp_scale": 0.07,
		"kinds": ["skeleton_warrior", "skeleton_vanguard", "skeleton_hunter", "ghoul", "veil_cultist", "bleed_fiend"]},
	# The spawning mini-dungeons (MiniDungeons: an entrance in an open zone, now and then, leads to one; "mini" names what happens in it
	# (MiniDungeon), "packs" false: no ordinary monsters, "density": more of them)
	"mini_cellar": {"name": "Rot-Damp Cellar", "act": 1, "map": "mini_cellar", "area_level": 3, "xp_scale": 0.08, "mini": "cellar", "density": 1.8, "kinds": ["blood_maggot", "ghoul"]},
	"mini_bonepit": {"name": "Forgotten Bone Pit", "act": 1, "map": "mini_bonepit", "area_level": 3, "xp_scale": 0.1, "mini": "bonepit",
		"kinds": ["skeleton", "skeleton_warrior", "skeleton_archer"]},
	"mini_sanctum": {"name": "Hermit's Sanctum", "act": 1, "map": "mini_sanctum", "area_level": 3, "xp_scale": 0.1, "mini": "sanctum", "packs": false, "kinds": ["skeleton"]},
	"mini_fissure": {"name": "Weeping Fissure", "act": 1, "map": "mini_fissure", "area_level": 3, "xp_scale": 0.06, "mini": "fissure", "density": 2.4,
		"kinds": ["bleed_fiend", "ghoul", "veil_cultist", "blind_crawler"]},
	"sepulcher_of_mourning": {"name": "Sepulcher of Mourning", "act": 1, "map": "sepulcher_of_mourning", "area_level": 9, "xp_scale": 0.071,
		"kinds": ["skeleton_vanguard", "veil_cultist", "bleed_fiend", "skeleton_hunter", "ghoul"]},
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
