class_name Hirelings
extends RefCounted
## Your hireling (Diablo II's mercenary): one at a time, hired from the Mercenary Captain in
## Ashfall (HirelingDB has the types). It follows you and fights (Hireling), levels up with the
## experience you earn (never past your level), wears its own gear and fights with skill gems it
## came with. Its skill gems are its own, but you link your support gems to them, at the stash
## like your own. If it falls it stays down until the Captain revives it, or you hire another.
##
## Its state is GameState.hireling (saved with the character):
##   {type, name, level, xp, skills: [skill ids, main attack first], supports: [[rune ids] per skill],
##    look (Appearance) or skin, dead}
## its gear GameState.hireling_gear: slot -> ItemInstance, and its two flasks
## GameState.hireling_flasks (ItemInstance or null each), which it drinks itself (Hireling).

const FLASK_SLOTS := 2

static var node: Hireling = null  ## the hireling in the current scene, if any
static var _candidates := {}  ## type id -> [candidate dicts] on offer (rolled again as you level)
static var _candidates_level := 0


static func has() -> bool:
	return not GameState.hireling.is_empty()


static func alive() -> bool:
	return has() and not bool(GameState.hireling.get("dead", false))


static func type_id() -> String:
	return String(GameState.hireling.get("type", ""))


static func type_def() -> Dictionary:
	return HirelingDB.type_def(type_id())


static func level() -> int:
	return int(GameState.hireling.get("level", 1))


## "Bryn, Sellsword"
static func title(h: Dictionary = GameState.hireling) -> String:
	return "%s, %s" % [String(h.get("name", "?")), String(HirelingDB.type_def(String(h.get("type", ""))).get("name", ""))]


## Its attributes: its type's start plus the points you added (gear requirements are judged by these).
static func attributes() -> Dictionary:
	var out := HirelingDB.base_attributes(type_id())
	var added: Dictionary = GameState.hireling.get("attributes", {})
	for k in added:
		out[k] = int(out.get(k, 0)) + int(added[k])
	return out


## Points it has to add (Attributes.POINTS_PER_LEVEL a level), and adding them.
static func attr_points() -> int:
	return int(GameState.hireling.get("attr_points", 0))


static func add_attribute(key: String, n := 1) -> bool:
	if not has() or not key in HirelingDB.ATTR_KEYS or n <= 0 or attr_points() < n:
		return false
	var added: Dictionary = GameState.hireling.get("attributes", {})
	added[key] = int(added.get(key, 0)) + n
	GameState.hireling["attributes"] = added
	GameState.hireling["attr_points"] = attr_points() - n
	_skills_changed()
	return true


## Take all its added points back (free, in town).
static func reset_attributes() -> void:
	if not has():
		return
	GameState.hireling["attributes"] = {}
	fix_attribute_points()
	_skills_changed()


static func attribute_points_spent() -> int:
	var n := 0
	var added: Dictionary = GameState.hireling.get("attributes", {})
	for k in added:
		n += int(added[k])
	return n


## Exactly Attributes.POINTS_PER_LEVEL per level gained: one saved before points (or holding more
## than its level allows) gets them all back to add.
static func fix_attribute_points() -> void:
	if not has():
		return
	var budget := Attributes.POINTS_PER_LEVEL * (level() - 1)
	var clean := {}
	var added: Dictionary = GameState.hireling.get("attributes", {})
	for k in HirelingDB.ATTR_KEYS:
		if int(added.get(k, 0)) > 0:
			clean[k] = int(added[k])
	GameState.hireling["attributes"] = clean
	if attribute_points_spent() > budget:
		GameState.hireling["attributes"] = {}
	GameState.hireling["attr_points"] = budget - attribute_points_spent()


static func links() -> int:
	return HirelingDB.links_at(level())


static func skill_ids() -> Array:
	return GameState.hireling.get("skills", [])


static func supports(i: int) -> Array:
	var all: Array = GameState.hireling.get("supports", [])
	return all[i] if i >= 0 and i < all.size() else []


## Skill i with its linked supports, as the hireling uses it.
static func skill_def(i: int) -> SkillDef:
	var ids := skill_ids()
	if i < 0 or i >= ids.size():
		return null
	var sk := SkillTree.get_skill(String(ids[i]))
	if sk == null:
		return null
	sk.for_hireling = true
	sk.socketed_runes.clear()
	for rid in supports(i):
		sk.socketed_runes.append(String(rid))
	for r in sk.get_runes():
		sk.duration *= r.duration_mult
	return sk


static func skill_rank() -> int:
	return HirelingDB.skill_rank(level())


# ---------- stats and gear ----------

## Whether a piece of its gear meets its requirements (if not, it gives nothing).
static func gear_active(item: ItemInstance) -> bool:
	return item != null and Attributes.meets(item.base, attributes())


## Its stats: the type's at its level, plus its gear that meets requirements.
static func build_stats() -> StatBlock:
	var st := StatBlock.new()
	var base := HirelingDB.stats_at(type_id(), level())
	for k in base:
		st.set_base(String(k), float(base[k]))
	Attributes.apply(st, GameState.hireling.get("attributes", {}), "attributes", true)
	for slot in GameState.hireling_gear:
		var it: ItemInstance = GameState.hireling_gear[slot]
		if gear_active(it):
			it.apply_to(st)
	return st


## "" if `item` can go in its `slot`, otherwise why not.
static func slot_block_reason(item: ItemInstance, slot: String) -> String:
	var t := type_def()
	if item == null or t.is_empty():
		return "Nothing to equip"
	var tname := String(t.name)
	if not slot in (t.slots as Array):
		return "A %s has no %s slot" % [tname, String(UIKit.SLOT_NAMES.get(slot, slot)).to_lower()]
	if item.is_flask() or item.base.slot != slot:
		return "That doesn't go there"
	if not item.identified:
		return "Identify it first"
	var wt := item.base.weapon_type
	if wt != "" and not wt in (t.weapons as Array):
		return "%ss can't use %ss" % [tname, String(ItemBase.TYPE_NAMES.get(wt, wt)).to_lower()]
	if bool(t.get("one_handed", false)) and item.base.two_handed:
		return "%ss fight one-handed, with a shield" % tname
	return Attributes.block_reason(item.base, attributes(), "they have")


## Put `item` from the player's bag on the hireling. What it was wearing there goes into the bag,
## where the item was if it fits. False (and nothing changes) if it can't.
static func equip_from_bag(player: Player, item: ItemInstance, slot: String) -> bool:
	if not has() or not player.bag.has(item) or slot_block_reason(item, slot) != "":
		return false
	var old: ItemInstance = GameState.hireling_gear.get(slot)
	var at := player.bag.position_of(item)
	if old != null:
		var trial := player.bag.duplicate_grid()
		trial.remove(item)
		var spot := at if trial.fits(old, at) else trial.find_free(old)
		if spot == ItemGrid.NONE:
			return false
		player.bag.remove(item)
		player.bag.place(old, spot)
	else:
		player.bag.remove(item)
	GameState.hireling_gear[slot] = item
	_gear_changed(player)
	return true


## Whether its gear in `slot` could be dropped at `at` in the bag: into space, or swapping with
## one bag item it could wear there.
static func can_unequip_to(player: Player, slot: String, at: Vector2i) -> bool:
	var it: ItemInstance = GameState.hireling_gear.get(slot)
	if it == null:
		return false
	var plan := player.bag.plan_drop(it, at, null)
	if plan.is_empty():
		return false
	var b: ItemInstance = plan.get("swap")
	return b == null or slot_block_reason(b, slot) == ""


static func unequip_to(player: Player, slot: String, at: Vector2i) -> bool:
	if not can_unequip_to(player, slot, at):
		return false
	var it: ItemInstance = GameState.hireling_gear[slot]
	var b: ItemInstance = player.bag.plan_drop(it, at, null).get("swap")
	if b != null:
		player.bag.remove(b)
	GameState.hireling_gear.erase(slot)
	player.bag.place(it, at)
	if b != null:
		GameState.hireling_gear[slot] = b
	_gear_changed(player)
	return true


## Take its gear in `slot` off into the first space in the bag it fits.
static func unequip(player: Player, slot: String) -> bool:
	var it: ItemInstance = GameState.hireling_gear.get(slot)
	if it == null:
		return false
	var at := player.bag.find_free(it)
	return at != ItemGrid.NONE and unequip_to(player, slot, at)


# ---------- its flasks (it drinks them itself: life when hurt, utility when fighting) ----------

## "" if `item` can go in one of its flask slots, otherwise why not.
static func flask_block_reason(item: ItemInstance) -> String:
	if item == null or not item.is_flask():
		return "Only flasks go there"
	if String(item.flask_effect().kind) == "power":
		return "Hirelings have no Mana to restore"
	return ""


static func flask(i: int) -> ItemInstance:
	return GameState.hireling_flasks[i] if i >= 0 and i < GameState.hireling_flasks.size() else null


## Put a flask from your bag in its flask slot i; one already there goes back to your bag.
static func equip_flask_from_bag(player: Player, item: ItemInstance, i: int) -> bool:
	if not has() or i < 0 or i >= FLASK_SLOTS or not player.bag.has(item) or flask_block_reason(item) != "":
		return false
	var old := flask(i)
	var at := player.bag.position_of(item)
	if old != null:
		var trial := player.bag.duplicate_grid()
		trial.remove(item)
		var spot := at if trial.fits(old, at) else trial.find_free(old)
		if spot == ItemGrid.NONE:
			return false
		player.bag.remove(item)
		player.bag.place(old, spot)
	else:
		player.bag.remove(item)
	GameState.hireling_flasks[i] = item
	_gear_changed(player)
	return true


## Whether its flask i could be dropped at `at` in your bag (into space, or swapping with a flask it can use).
static func can_unequip_flask_to(player: Player, i: int, at: Vector2i) -> bool:
	var it := flask(i)
	if it == null:
		return false
	var plan := player.bag.plan_drop(it, at, null)
	if plan.is_empty():
		return false
	var b: ItemInstance = plan.get("swap")
	return b == null or flask_block_reason(b) == ""


static func unequip_flask_to(player: Player, i: int, at: Vector2i) -> bool:
	if not can_unequip_flask_to(player, i, at):
		return false
	var it := flask(i)
	var b: ItemInstance = player.bag.plan_drop(it, at, null).get("swap")
	if b != null:
		player.bag.remove(b)
	GameState.hireling_flasks[i] = b
	player.bag.place(it, at)
	_gear_changed(player)
	return true


static func _gear_changed(player: Player) -> void:
	if is_instance_valid(node):
		node.refresh()
	if player != null:
		player.inventory_changed.emit()
	GameState.save_soon()


# ---------- support gems (at the stash, like your own) ----------

## Put a support from the shared pool into link `idx` of skill i (replacing what is there).
static func socket_support(i: int, idx: int, rune_id: String) -> bool:
	if not has() or GameState.rune_count(rune_id) <= 0 or i < 0 or i >= skill_ids().size() or idx >= links():
		return false
	var list: Array = supports(i).duplicate()
	var old := ""
	if idx < list.size():
		old = String(list[idx])
		list[idx] = rune_id
	else:
		list.append(rune_id)
	if not SkillDef.supports_valid(list):
		return false
	_set_supports(i, list)
	GameState.runes[rune_id] = GameState.rune_count(rune_id) - 1
	if old != "":
		GameState.runes[old] = GameState.rune_count(old) + 1
	_skills_changed()
	return true


static func unsocket_support(i: int, idx: int) -> bool:
	var list: Array = supports(i).duplicate()
	if idx < 0 or idx >= list.size():
		return false
	var rid := String(list[idx])
	list.remove_at(idx)
	_set_supports(i, list)
	GameState.runes[rid] = GameState.rune_count(rid) + 1
	_skills_changed()
	return true


## Move a linked support to another link of its skills; swaps if that link is filled.
static func move_support(from_i: int, from_idx: int, to_i: int, to_idx: int) -> bool:
	var a: Array = supports(from_i).duplicate()
	if from_idx < 0 or from_idx >= a.size() or to_idx >= links() or to_i < 0 or to_i >= skill_ids().size():
		return false
	var rid = a[from_idx]
	if from_i == to_i:
		if to_idx >= a.size():
			return false
		a[from_idx] = a[to_idx]
		a[to_idx] = rid
		_set_supports(from_i, a)
		_skills_changed()
		return true
	var b: Array = supports(to_i).duplicate()
	if to_idx < b.size():
		a[from_idx] = b[to_idx]
		b[to_idx] = rid
	else:
		a.remove_at(from_idx)
		b.append(rid)
	if not SkillDef.supports_valid(a) or not SkillDef.supports_valid(b):
		return false
	_set_supports(from_i, a)
	_set_supports(to_i, b)
	_skills_changed()
	return true


static func _set_supports(i: int, list: Array) -> void:
	var all: Array = GameState.hireling.get("supports", [])
	while all.size() < skill_ids().size():
		all.append([])
	all[i] = list
	GameState.hireling["supports"] = all


static func _skills_changed() -> void:
	if is_instance_valid(node):
		node.refresh()
	GameState.save_soon()


## Supports beyond the open links go back to the shared pool (after loading; links only grow).
static func fix_supports() -> void:
	if not has():
		return
	var all: Array = GameState.hireling.get("supports", [])
	while all.size() < skill_ids().size():
		all.append([])
	for i in all.size():
		var list: Array = all[i]
		while list.size() > links():
			var rid := String(list.pop_back())
			GameState.runes[rid] = GameState.rune_count(rid) + 1
	GameState.hireling["supports"] = all


# ---------- hiring, reviving, levelling ----------

## A fresh character (or another one picked): the Captain's offers are rolled again.
static func reset_offers() -> void:
	_candidates.clear()
	_candidates_level = 0


## Hirelings on offer of a type, as many as HirelingDB.CANDIDATES. They change as you level.
static func candidates(id: String) -> Array:
	if _candidates_level != GameState.level:
		_candidates.clear()
		_candidates_level = GameState.level
	if not _candidates.has(id):
		var taken: Array = []  # every name on offer (and yours), so no two share one
		for other in _candidates.values():
			for c in other:
				taken.append(String(c.name))
		if has():
			taken.append(String(GameState.hireling.get("name", "")))
		var list: Array = []
		for i in HirelingDB.CANDIDATES:
			var c := HirelingDB.roll_candidate(id, GameState.level, taken)
			taken.append(String(c.name))
			list.append(c)
		_candidates[id] = list
	return _candidates[id]


## "" if this candidate can be hired now, otherwise why not.
static func hire_block_reason(c: Dictionary) -> String:
	var id := String(c.get("type", ""))
	if not HirelingDB.unlocked(id):
		return String(HirelingDB.type_def(id).get("unlock_text", "Not yet"))
	if not GameState.can_afford(HirelingDB.hire_price(int(c.get("level", 1)))):
		return "You can't afford it"
	return ""


## Take on `c`. The one you had leaves: its gear comes back to your bag (the stash if it is full)
## and its supports to the shared pool. False if it can't be hired (see hire_block_reason).
static func hire(player: Player, c: Dictionary) -> bool:
	if hire_block_reason(c) != "" or not GameState.pay(HirelingDB.hire_price(int(c.get("level", 1)))):
		return false
	dismiss(player)
	var h := c.duplicate(true)
	h["dead"] = false
	h["xp"] = 0.0
	h["attributes"] = {}
	GameState.hireling = h
	GameState.hireling_gear = {}
	GameState.hireling_flasks = [null, null]
	fix_attribute_points()  # every point its level brought, to add
	var list: Array = _candidates.get(String(c.type), [])
	list.erase(c)
	GameState.save_soon()
	spawn(player)
	return true


## The current hireling leaves: gear back to you, supports back to the pool.
static func dismiss(player: Player) -> void:
	if not has():
		return
	var items: Array[ItemInstance] = []
	for slot in GameState.hireling_gear:
		items.append(GameState.hireling_gear[slot])
	for f in GameState.hireling_flasks:
		if f != null:
			items.append(f)
	GameState.hireling_gear = {}
	GameState.hireling_flasks = [null, null]
	var homeless: Array[ItemInstance] = []
	for it in items:
		if player == null or not player.bag.add(it):
			homeless.append(it)
	if not homeless.is_empty():
		GameState.store_items(homeless)
	for list in GameState.hireling.get("supports", []):
		for rid in list:
			GameState.runes[String(rid)] = GameState.rune_count(String(rid)) + 1
	GameState.hireling = {}
	if is_instance_valid(node):
		node.queue_free()
	node = null
	if player != null:
		player.inventory_changed.emit()


## What it would cost to revive the fallen hireling.
static func revive_price() -> Dictionary:
	return HirelingDB.revive_price(level())


## Bring the fallen hireling back (at the Captain). False if it isn't fallen or you can't pay.
static func revive(player: Player) -> bool:
	if not has() or alive() or not GameState.pay(revive_price()):
		return false
	GameState.hireling["dead"] = false
	GameState.save_soon()
	spawn(player)
	return true


## It fell in battle: it stays down until revived.
static func on_died() -> void:
	if has():
		GameState.hireling["dead"] = true
		GameState.save_soon()


## It shares the experience you earn while it lives, up to your level.
static func add_xp(amount: float) -> void:
	if not alive():
		return
	var h := GameState.hireling
	var lvl := int(h.get("level", 1))
	var x := float(h.get("xp", 0.0)) + amount
	var up := false
	while lvl < GameState.level and x >= GameState.xp_to_next(lvl):
		x -= GameState.xp_to_next(lvl)
		lvl += 1
		up = true
	# At your level it keeps what it earns, and levels as soon as you do
	h["xp"] = minf(x, GameState.xp_to_next(lvl))
	h["attr_points"] = int(h.get("attr_points", 0)) + Attributes.POINTS_PER_LEVEL * (lvl - int(h.get("level", 1)))
	h["level"] = lvl
	if up:
		fix_supports()
		if is_instance_valid(node):
			node.on_level_up()


## Puts the hireling in the player's scene (beside them), if it is alive. Not in the tutorial.
static func spawn(player: Player) -> void:
	if is_instance_valid(node):
		node.queue_free()
	node = null
	if player == null or not alive() or GameState.tutorial_stage != GameState.TUTORIAL_DONE:
		return
	var parent := player.get_parent()
	if parent == null:
		return
	var h := Hireling.new()
	h.owner_player = player
	h.position = player.position + Vector2(-70, 40)
	node = h
	parent.add_child.call_deferred(h)
