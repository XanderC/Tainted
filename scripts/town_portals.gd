class_name TownPortals
extends Node
## Town portal scrolls. Reading one (the 🌀 button in a zone or a rift: add_button, or G) opens a
## portal where you stand: tap its label to go to town, where a portal back stands by the square
## until you go back through it. One open portal each: reading another closes the first. Your
## party sees yours and can use it both ways (Net shares it: the party's "tps").
## Going back into a rift carries on with it: a solo rift is saved going through (`save`), a party's
## by the last one out (Net.save_rift) while someone has a portal into it. A rift's portals close
## when it moves on to its next maze. What lay on the ground waits too (remember_loot).
## A portal (GameState.town_portal, and as the party sees it):
##   id      a random number: which portal it is
##   kind    "zone" or "rift"
##   zone    the zone's id (a zone's)
##   inst    the party instance it's in ("" for your own solo zone or rift)
##   key     the rift it's in (main.gd rift_key: a party rift's is its instance)
##   maze    which of the rift's mazes
##   level   the rift's level (for its label)
##   x, y    where it stands
##   save    a solo rift as you left it (main.gd snapshot), taken going through
## Add one to a scene (zone, rift, town) with `place` set and it shows the portals there, yours and
## your party's, kept up to date. A zone or rift scene gives portal_place() (its place, as a portal's
## fields) and portal_to_town() (go through one).

const SCROLL_KEY := KEY_G
const TOWN_SPOTS := [Vector2(0, 0), Vector2(-160, 40), Vector2(160, 40), Vector2(0, 150)]
const MINE := Color(0.55, 0.80, 1.0)
const THEIRS := Color(0.55, 1.0, 0.75)

var place := {}  ## {"kind": "town"}, or a zone's or rift's portal_place()
var town_at := Vector2.ZERO  ## in town: where the portals back stand
var _nodes := {}  # portal id -> TownPortal
var _shown := false  # shown once: portals appearing after that open (they were just read)


func _ready() -> void:
	Net.party_changed.connect(refresh)
	GameState.town_portal_changed.connect(refresh)
	refresh()


## The scene's place changed (a rift's next maze): show what's there.
func set_place(where: Dictionary) -> void:
	place = where
	refresh()


func refresh() -> void:
	if not is_inside_tree() or place.is_empty():
		return
	var town := String(place.kind) == "town"
	var list: Array = all().filter(func(e): return leads_back(e.tp) if town else is_in(e.tp, place))
	var ids := list.map(func(e): return int(e.tp.get("id", 0)))
	for id in _nodes.keys():
		if not ids.has(id) or not is_instance_valid(_nodes[id]):
			if is_instance_valid(_nodes[id]):
				_nodes[id].queue_free()
			_nodes.erase(id)
	var world := get_parent()
	for i in list.size():
		var e: Dictionary = list[i]
		var tp: Dictionary = e.tp
		var id := int(tp.get("id", 0))
		var at: Vector2 = town_at + TOWN_SPOTS[mini(i, TOWN_SPOTS.size() - 1)] if town else Vector2(float(tp.x), float(tp.y))
		if _nodes.has(id):
			_nodes[id].position = at
			continue
		var n := TownPortal.new()
		n.tp_id = id
		n.position = at
		n.opening = _shown
		n.label_color = MINE if e.mine else THEIRS
		var where := where_name(tp)
		if town:
			n.label = ("🌀 Portal: " + where) if e.mine else "🌀 %s's Portal: %s" % [e.by, where]
			n.on_enter = func(): go_back(get_tree(), tp, e.mine)
		else:
			n.label = "🌀 Town Portal" if e.mine else "🌀 %s's Town Portal" % e.by
			n.on_enter = func():
				if world.has_method("portal_to_town"):
					world.portal_to_town()
		world.add_child(n)
		_nodes[id] = n
	_shown = true


# ---------- reading a scroll ----------

## A 🌀 button (top right of the screen, left of the menu's) reading a scroll in `scene`, with how
## many you have. G reads one too.
static func add_button(layer: CanvasLayer, scene: Node) -> Button:
	var b := UIKit.stone_button("", Vector2(120, 56), 18)
	b.tooltip_text = "Read a Scroll of Town Portal (G): a portal to town opens where you stand, and your party can use it too"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): read_scroll(scene))
	layer.add_child(b)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -396.0
	b.offset_right = -276.0
	b.offset_top = 16.0
	b.offset_bottom = 72.0
	var count := func():
		b.text = "🌀 ×%d" % GameState.tp_scrolls
		b.modulate = Color.WHITE if GameState.tp_scrolls > 0 else Color(1, 1, 1, 0.55)
	count.call()
	GameState.scrolls_changed.connect(count)
	b.tree_exiting.connect(func(): GameState.scrolls_changed.disconnect(count))
	return b


## Read a scroll in `scene` (a zone or rift) where its player stands: its portal opens there (and
## any other of yours closes). False if you have none, or can't now.
static func read_scroll(scene: Node) -> bool:
	var p = scene.get("player")
	if GameState.tp_scrolls <= 0 or not is_instance_valid(p) or p.dead or scene.get_tree().paused \
			or not scene.has_method("portal_place"):
		return false
	var where: Dictionary = scene.portal_place()
	if where.is_empty():
		return false
	GameState.add_scrolls(-1)
	var tp := where.duplicate()
	tp["id"] = randi_range(1, 2000000000)
	tp["x"] = p.global_position.x
	tp["y"] = p.global_position.y
	open(tp)
	return true


## `tp` is your open portal now (the one before closes), and your party is told.
static func open(tp: Dictionary) -> void:
	var old_inst := String(GameState.town_portal.get("inst", ""))
	GameState.town_portal = tp
	if String(tp.get("inst", "")) != "":
		Net.share_town_portal(shared(tp))
	elif old_inst != "":
		Net.share_town_portal({})
	GameState.town_portal_changed.emit()
	GameState.save()


## Your portal closes (you went back through it, or the place it was in is gone).
static func close_mine() -> void:
	if GameState.town_portal.is_empty():
		return
	var had_inst := String(GameState.town_portal.get("inst", "")) != ""
	GameState.town_portal = {}
	if had_inst:
		Net.share_town_portal({})
	GameState.town_portal_changed.emit()
	GameState.save()


## What the party sees of `tp` (not a solo rift's save).
static func shared(tp: Dictionary) -> Dictionary:
	var d := tp.duplicate()
	d.erase("save")
	return d


# ---------- which portals, where ----------

## Every open portal you might see: yours first, then your party's: [{"tp", "mine", "by"}].
static func all() -> Array:
	var out: Array = []
	if not GameState.town_portal.is_empty():
		out.append({"tp": GameState.town_portal, "mine": true, "by": ""})
	if Net.in_party():
		var tps = Net.party.get("tps", {})
		if tps is Dictionary:
			for id in tps:
				if int(id) != Net.my_id() and tps[id] is Dictionary:
					out.append({"tp": tps[id], "mine": false, "by": String(tps[id].get("by_name", "?"))})
	return out


## Whether `tp` stands in `where` (a zone's or rift's place).
static func is_in(tp: Dictionary, where: Dictionary) -> bool:
	if String(tp.get("kind", "")) != String(where.get("kind", "")):
		return false
	match String(where.kind):
		"zone":
			return String(tp.get("zone", "")) == String(where.get("zone", ""))
		"rift":
			return String(tp.get("key", "")) == String(where.get("key", "")) and int(tp.get("maze", 0)) == int(where.get("maze", 0))
	return false


## Whether going through `tp` from town takes you somewhere: a zone always; a solo rift once it was
## saved going through; a party's rift while the party has it.
static func leads_back(tp: Dictionary) -> bool:
	match String(tp.get("kind", "")):
		"zone":
			return ActDB.ZONES.has(String(tp.get("zone", "")))
		"rift":
			var inst := String(tp.get("inst", ""))
			if inst == "":
				var save = tp.get("save", {})
				return save is Dictionary and not save.is_empty()
			return Net.in_party() and Net.party_of_instance(inst) == int(Net.party.get("id", 0)) \
				and String(Net.party.get("portal", {}).get("inst", "")) == inst
	return false


## "The Ashwood", "Rift 3".
static func where_name(tp: Dictionary) -> String:
	if String(tp.get("kind", "")) == "rift":
		return "Rift %d" % int(tp.get("level", 1))
	return ActDB.zone_name(String(tp.get("zone", "")))


## Through `tp` from town, back to where it stands (your own closes behind you).
static func go_back(tree: SceneTree, tp: Dictionary, mine: bool) -> void:
	if not leads_back(tp):
		return
	GameState.portal_arrival = {"kind": tp.kind, "zone": String(tp.get("zone", "")), "key": String(tp.get("key", "")),
		"maze": int(tp.get("maze", 0)), "x": float(tp.x), "y": float(tp.y)}
	if mine:
		close_mine()
	if tp.kind == "zone":
		ActDB.travel(tree, String(tp.zone), "portal")
	elif String(tp.get("inst", "")) == "":
		GameState.rift_resume = tp.save
		GameState.save()
		tree.paused = false
		tree.change_scene_to_file.call_deferred("res://scenes/main.tscn")
	else:
		Net.join_portal(Net.party.portal)


## Arriving in `where` back through a portal: where to stand (Vector2.INF if you didn't come that
## way, or not to here).
static func take_arrival(where: Dictionary) -> Vector2:
	var a: Dictionary = GameState.portal_arrival
	if a.is_empty() or not is_in(a, where):
		return Vector2.INF
	GameState.portal_arrival = {}
	return Vector2(float(a.x), float(a.y)) + Vector2(0, 40)  # just in front of it


# ---------- what's left on the ground ----------

## Going through a portal from `scene` (at `where`): what lies on the ground there waits till you
## come back (GameState.left_loot; each player's own, as loot is).
static func remember_loot(scene: Node, where: Dictionary) -> void:
	var items: Array = []
	var piles: Array = []
	for c in scene.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is LootPickup and c.item != null:
			items.append([c.item.to_dict(), c.position.x, c.position.y])
		elif c is CurrencyPickup:
			piles.append([c.kind, c.id, c.amount, c.position.x, c.position.y])
	GameState.left_loot = {} if items.is_empty() and piles.is_empty() else \
		{"where": _loot_place(where), "items": items, "piles": piles}


## Back in `where`: what you left lying here is again.
static func restore_loot(scene: Node, where: Dictionary) -> void:
	var l: Dictionary = GameState.left_loot
	if l.is_empty() or l.get("where", {}) != _loot_place(where):
		return
	GameState.left_loot = {}
	for it in l.get("items", []):
		var item := ItemInstance.from_dict(it[0])
		if item != null:
			var pk := LootPickup.new()
			pk.item = item
			pk.position = Vector2(float(it[1]), float(it[2]))
			scene.add_child(pk)
	for p in l.get("piles", []):
		var c := CurrencyPickup.new()
		c.kind = String(p[0])
		c.id = String(p[1])
		c.amount = int(p[2])
		c.position = Vector2(float(p[3]), float(p[4]))
		scene.add_child(c)


## The part of a place that says where loot lies (JSON keeps numbers as floats: so does this).
static func _loot_place(where: Dictionary) -> Dictionary:
	return {"kind": String(where.get("kind", "")), "zone": String(where.get("zone", "")),
		"key": String(where.get("key", "")), "maze": float(where.get("maze", 0))}
