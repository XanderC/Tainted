class_name Breakables
extends RefCounted
## Barrels, crates and urns (Breakable) standing about a zone, and the odd chest (LootChest): where they go, and
## what they hold. Like the extra monster packs (PackSpots) they are the same every time for one map: a seed
## from the map's id, so a party's copies of a zone have the same ones, and each game rolls its own loot.
## A zone can say `"breakables": 0` (none), or a number to scale how many: ActDB.ZONES.

const CELLS_PER_CLUSTER := 28.0  # a cluster of one to three props for about this many floor cells
const CELLS_PER_CHEST := 450.0  # a chest for this many, at least one and at most MAX_CHESTS
const MAX_CHESTS := 5
const CLUSTER_SPACING := 260.0
const CHEST_SPACING := 900.0
const CHEST_FROM_START := 700.0
## What stays clear of each kind of map object (pixels): less than a pack's, so they stand close to where you arrive too.
const KEEP_CLEAR := {"start": 220.0, "portal": 200.0, "waypoint": 260.0, "npc": 220.0, "boss": 380.0,
	"quest_object": 200.0, "marker": 200.0, "vault": 200.0, "trap": 120.0}
const KIND_WEIGHTS := {"barrel": 45, "crate": 35, "urn": 20}


## Where things go in `maze`: {"props": [{"kind", "pos"}], "chests": [Vector2]}. `scale` 0 gives nothing.
static func spots(maze: MazeMap, scale := 1.0) -> Dictionary:
	var out := {"props": [], "chests": []}
	if scale <= 0.0:
		return out
	var cells := maze.floor_cells()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(maze.map_id + ":breakables")
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := cells[i]
		cells[i] = cells[j]
		cells[j] = t

	var clear: Array = []  # [position, distance]
	for o in maze.data.get("objects", []):
		var r: float = KEEP_CLEAR.get(String(o.get("type", "")), 0.0)
		if r > 0.0:
			clear.append([Vector2(float(o.get("x", 0)), float(o.get("y", 0))), r])
	clear.append([maze.start_pos, KEEP_CLEAR.start])
	for p in maze.portals:
		clear.append([Vector2(float(p.x), float(p.y)), KEEP_CLEAR.portal])

	var taken: Array[Vector2] = []
	var want := int(cells.size() / CELLS_PER_CLUSTER * scale)
	for c in cells:
		if taken.size() >= want:
			break
		var at := maze.cell_center(c)
		if _near(at, clear) or _closer_than(at, taken, CLUSTER_SPACING):
			continue
		taken.append(at)
		var n := rng.randi_range(1, 3)
		for k in n:
			var p := at + Vector2.from_angle(rng.randf() * TAU) * (0.0 if k == 0 else rng.randf_range(34.0, 62.0))
			if k > 0 and (maze.is_wall(maze.world_to_cell(p)) or _near(p, clear)):
				continue
			out.props.append({"kind": _kind(rng), "pos": p})

	var chests: Array[Vector2] = []
	var chest_want := clampi(int(cells.size() / CELLS_PER_CHEST * scale), 1, MAX_CHESTS)
	for c in cells:
		if chests.size() >= chest_want:
			break
		var at := maze.cell_center(c)
		if not _open(maze, c) or at.distance_to(maze.start_pos) < CHEST_FROM_START or _near(at, clear) or _closer_than(at, chests, CHEST_SPACING):
			continue
		chests.append(at)
	out.chests = chests
	return out


static func _kind(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in KIND_WEIGHTS:
		total += int(KIND_WEIGHTS[k])
	var r := rng.randi_range(1, total)
	for k in KIND_WEIGHTS:
		r -= int(KIND_WEIGHTS[k])
		if r <= 0:
			return k
	return "barrel"


## A cell with floor all round it (a chest needs room to be walked up to).
static func _open(maze: MazeMap, c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if maze.is_wall(c + Vector2i(dx, dy)):
				return false
	return true


static func _near(p: Vector2, clear: Array) -> bool:
	for c in clear:
		if p.distance_to(c[0]) < float(c[1]):
			return true
	return false


static func _closer_than(p: Vector2, taken: Array[Vector2], d: float) -> bool:
	for t in taken:
		if p.distance_squared_to(t) < d * d:
			return true
	return false


# ---------- what they hold ----------

## What a broken barrel, crate or urn (or an opened chest) at `at` in `zone` drops: its own pickups, each by itself.
## Needs the zone's `_drop_item` and its `area_level`.
static func drop_loot(zone: Node, at: Vector2, chest := false) -> void:
	var more := PartyScale.drops()  # a party: better odds
	var level: int = int(zone.get("area_level"))
	if chest:
		zone._drop_item(LootGenerator.roll_item(level + 1, ItemInstance.Rarity.MAGIC), at)
		if randf() < 0.35 * more:
			zone._drop_item(LootGenerator.roll_item(level + 2, ItemInstance.Rarity.RARE), at + Vector2(40, 10))
		for i in 2:
			_drop_currency(zone, at, CraftingDB.monster_drops(level))
		if randf() < 0.25 * more:
			CurrencyPickup.drop(zone, ["scroll", "town_portal", 1], at)
		return
	if randf() < 0.22 * more:
		_drop_currency(zone, at, CraftingDB.monster_drops(level))
	if randf() < 0.04 * more:
		var rarity := ItemInstance.Rarity.MAGIC if randf() < 0.3 else ItemInstance.Rarity.NORMAL
		zone._drop_item(LootGenerator.roll_item(level, rarity), at)
	if randf() < 0.015 * more:
		CurrencyPickup.drop(zone, ["scroll", "town_portal", 1], at)


## CraftingDB.monster_drops()'s {"shards": {id: n}, "orbs": {id: n}}, each entry its own pickup.
static func _drop_currency(zone: Node, at: Vector2, drops: Dictionary) -> void:
	for id in drops.shards:
		CurrencyPickup.drop(zone, ["shard", id, int(drops.shards[id])], at)
	for id in drops.orbs:
		CurrencyPickup.drop(zone, ["orb", id, int(drops.orbs[id])], at)
