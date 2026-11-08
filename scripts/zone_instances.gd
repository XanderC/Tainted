class_name ZoneInstances
extends RefCounted
## The story zones you have left, kept as you left them until you leave the game. Going through an exit,
## a waypoint or a town portal takes the Zone scene out of the game with its monsters, loot, bosses and
## quest objects still in it (stash_current); coming back puts the same one in (resume), or asks first
## whether to carry on or start it over (InstanceChoice). Only what is yours is taken away and made again: the
## player, their hireling and pet, the screen's buttons and windows (Zone.suspend, Zone.resume).
## Kept in memory only, so closing the game, picking another character or signing out starts every zone
## afresh (GameState clears them). A party's zone is the party's, run by its host (Coop), and is never kept.

static var _stored := {}  # zone id -> Zone


static func has(id: String) -> bool:
	return _stored.has(id) and is_instance_valid(_stored[id])


## Starts `id` over: the kept one is thrown away.
static func discard(id: String) -> void:
	if _stored.has(id):
		var z = _stored[id]
		_stored.erase(id)
		if is_instance_valid(z):
			z.free()  # (not in the tree: nothing else holds it)


## Every kept zone goes: you left the game.
static func clear() -> void:
	for id in _stored.keys():
		discard(id)


## If the scene you are in is a solo zone, takes it out of the game and keeps it. A party's, or
## any other scene, is left for the scene change to free as it always did.
static func stash_current(tree: SceneTree) -> void:
	var cur := tree.current_scene
	if not cur is Zone or cur.coop != null:
		return
	var z: Zone = cur
	discard(z.zone_id)  # (never two of one zone)
	z.suspend()
	z.get_parent().remove_child(z)
	tree.current_scene = null
	_stored[z.zone_id] = z


## Puts the kept zone `id` back as the scene (what was there is freed, as a scene change does), and you arrive
## in it by `entry` (GameState.zone_entry's values).
static func resume(tree: SceneTree, id: String, entry: String) -> void:
	if not has(id):
		tree.change_scene_to_file(Zone.SCENE)  # (it has gone: a new one)
		return
	var z: Zone = _stored[id]
	_stored.erase(id)
	var old := tree.current_scene
	if old != null and is_instance_valid(old):
		old.queue_free()
	tree.root.add_child(z)
	tree.current_scene = z
	z.resume(entry)


## What is left in the kept zone `id`, for the question of whether to carry on.
static func describe(id: String) -> String:
	if not has(id):
		return ""
	var z: Zone = _stored[id]
	var left := 0
	var boss := ""
	for c in z.get_children():
		if c is Enemy and not c._dead and not c.is_queued_for_deletion():
			if c.is_boss:
				boss = c.display_name
			else:
				left += 1
	var parts: Array[String] = []
	if left > 0:
		parts.append("about %d monsters are left" % (int(round(left / 5.0)) * 5 if left > 10 else left))
	else:
		parts.append("its monsters are cleared")
	if boss != "":
		parts.append("%s still lives" % boss)
	return "You have been here already: " + " and ".join(parts) + "."
