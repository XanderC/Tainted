extends Node
## Autoload "GameState": everything that persists between dungeon runs
## (orbs - which are also the money - materials, recipes, player's items, skill tree and runes). Saved to user://.
## Each character has its own save (CHAR_DIR/<id>.json); the account file lists the characters
## and holds the stash, which all characters share.

signal changed
signal skills_changed
signal leveled_up(level: int)

const SAVE_PATH := "user://tainted_save.json"  # the single save from before characters existed
const ACCOUNT_PATH := "user://tainted_account.json"
const CHAR_DIR := "user://characters"
const MAX_CHARACTERS := 8
const NAME_MAX_LEN := 16

var characters: Array = []  # [{"id", "name", "class", "level"}], in creation order
var last_character := ""    # id of the character played last (preselected on the select screen)
var char_id := ""           # character being played; "" before one is picked
var char_name := ""
var char_class := "warrior"
## Tutorial progress of the character being played (TutorialMap.Stage); TUTORIAL_DONE once finished.
const TUTORIAL_DONE := 99
var tutorial_stage := TUTORIAL_DONE
var show_hub_intro := false
## Set by the map editor's "Test in Game" (command line --test-map=<id>): rifts use only this map.
var test_map := ""  # set when the tutorial ends: the town shows its welcome once

# Shared by every character (saved in the account, shown in the stash's Currency, Materials and
# Gems tabs): orbs, shards, crafting materials and loose gems. See SHARED_KEYS.
var orbs := {}
var shards := {}  # orb id -> shards (Currency.SHARDS_PER_ORB join into one orb)
var materials := {}
var known_recipes: Array[String] = []
var runs_cleared := 0
var rift_unlocked := 1  # highest rift level the player may enter (beat a level on time to unlock the next)
var rift_level := 1     # level chosen at the rift gate for the next run
var player: Player
## The shared stash is a grid like the bag (ItemGrid), bigger.
const STASH_COLS := 12
const STASH_ROWS := 10
const STASH_SIZE := STASH_COLS * STASH_ROWS  # cells
var stash := ItemGrid.new(STASH_COLS, STASH_ROWS)  # shared storage, account-wide
## Items that had nowhere to go when an older save was loaded (it counted items, not cells, so a
## full bag or stash of big gear can't all fit the grids). Moved into the stash as room is made.
var stash_overflow: Array[ItemInstance] = []

# Skill gems (Path of Exile style) and the passive tree
const SKILL_SLOTS := 6     # skill gem slots (one HUD button each)
const MAX_LINKS := 5       # support links per slot, unlocked as you level (see links_unlocked)
var skill_points := 3      # spent in the passive tree
var level := 1
var xp := 0.0
var passive_nodes := {}    # class_id -> Array of allocated PassiveTree node ids (start not included)
var skill_gems := {}       # skill_id -> count of loose skill gems in the gem pouch
var gem_levels := {}       # skill_id -> gem level (1..SkillTree.GEM_MAX_LEVEL)
var gem_xp := {}           # skill_id -> experience towards the next gem level
var support_levels := {}   # support (rune) id -> level (1..SkillTree.GEM_MAX_LEVEL)
var support_xp := {}       # support (rune) id -> experience towards the next level
var skill_slots: Array = []  # SKILL_SLOTS x {"skill": skill_id or "", "supports": [rune ids]}
var runes := {}            # support gems: rune_id -> count (int)  [shared]
var gems := {}             # gem_id -> count (int), see GemDef     [shared]
## Pools every character shares, saved in the account rather than each character. Loose skill
## gems are shared too, but what is socketed in a character's skill slots and the gems' levels
## stay that character's.
const SHARED_KEYS := ["orbs", "shards", "materials", "skill_gems", "runes", "gems"]
## Open while the stash or the Jeweler is: gems can only be socketed or swapped then.
var gem_station := false
## Flasks in the character's flask slots (Player.flasks), as saved: item dicts or null.
var _pending_flasks: Array = []
## Flasks made from an older save's potions that weren't put in a slot: they go in the bag.
var _pending_loose_flasks: Array[ItemInstance] = []

var _pending_inventory: Array = []
var _pending_equipment := {}
var _pending_alt_set := {}      # inactive weapon set: slot -> item dict
var _pending_active_set := 0
var _restoring := false
var _save_queued := false


func _ready() -> void:
	SkillTree.init_skills()
	RuneDef.DB.init_catalog()
	_new_game()  # defaults until a character is picked on the select screen
	_load_account()


func _new_game() -> void:
	known_recipes.clear()
	for id in CraftingDB.RECIPES:
		if CraftingDB.RECIPES[id].source == "start":
			known_recipes.append(id)
	runs_cleared = 0
	rift_unlocked = 1
	rift_level = 1
	_pending_inventory.clear()
	_pending_equipment.clear()
	_pending_alt_set.clear()
	_pending_active_set = 0

	# Every character starts with a Small Life Flask in the first flask slot
	_pending_flasks = [_new_flask("small_life_flask").to_dict()]
	_pending_loose_flasks.clear()

	# Starting skill gems & points (one passive point per level gained, 99 at level 100)
	skill_points = 0
	level = 1
	xp = 0.0
	passive_nodes = {}
	gem_levels = {}
	gem_xp = {}
	support_levels = {}
	support_xp = {}
	give_starter_skills()
	tutorial_stage = TUTORIAL_DONE


## What a brand-new account starts with in the shared pools. Given once, not per character, so
## making characters is no way to farm orbs.
func _starter_pools() -> void:
	orbs = CraftingDB.STARTING_CURRENCY.duplicate()
	shards = {}
	materials = CraftingDB.STARTING_MATERIALS.duplicate()
	gems = {"ruby_1": 2, "topaz_1": 1, "sapphire_1": 1}
	runes = STARTER_RUNES.duplicate()
	skill_gems = {}


const STARTER_RUNES := {
	"rune_frost": 1, "rune_fire": 2, "rune_lightning": 2, "rune_echo": 1,
	"rune_vampiric": 1, "rune_nova": 1, "rune_brutality": 1,
}


## The usual starting skill setup (new characters who skip the tutorial get this too; gems
## already owned are kept).
func give_starter_skills() -> void:
	skill_gems["frenzy"] = maxi(skill_gem_count("frenzy"), 1)
	skill_slots = _empty_slots()
	for i in 4:
		skill_slots[i].skill = ["cleave", "whirlwind", "leap_slam", "battle_cry"][i]
	skill_slots[0].supports = ["rune_frost"]
	_on_skills_modified()


## Item level used by crafting recipes; grows as you clear dungeons.
func craft_ilvl() -> int:
	return mini(3 + runs_cleared * 2, 40)


# ---------- counts ----------

func orb_count(id: String) -> int:
	return int(orbs.get(id, 0))


func material_count(id: String) -> int:
	return int(materials.get(id, 0))


func add_orb(id: String, n: int) -> void:
	orbs[id] = maxi(orb_count(id) + n, 0)
	_changed()


func add_material(id: String, n: int) -> void:
	materials[id] = maxi(material_count(id) + n, 0)
	_changed()


## Adds orb shards; every Currency.SHARDS_PER_ORB of one kind become an orb.
func add_shards(id: String, n: int) -> void:
	var total := int(shards.get(id, 0)) + n
	if total >= Currency.SHARDS_PER_ORB:
		orbs[id] = orb_count(id) + int(total / Currency.SHARDS_PER_ORB)
		total = total % Currency.SHARDS_PER_ORB
	shards[id] = total
	_changed()


func shard_count(id: String) -> int:
	return int(shards.get(id, 0))


## Orbs are the money: can you pay this price ({orb id: count})?
func can_afford(price: Dictionary) -> bool:
	for id in price:
		if orb_count(id) < int(price[id]):
			return false
	return true


## Pays a price in orbs. False (and nothing spent) if you can't afford it.
func pay(price: Dictionary) -> bool:
	if not can_afford(price):
		return false
	for id in price:
		orbs[id] = orb_count(id) - int(price[id])
	_changed()
	return true


## Gives orbs and shards ({"orbs": {...}, "shards": {...}}, e.g. Currency.sell_value).
func grant_currency(r: Dictionary) -> void:
	for id in r.get("orbs", {}):
		orbs[id] = orb_count(id) + int(r.orbs[id])
	for id in r.get("shards", {}):
		add_shards(id, int(r.shards[id]))
	_changed()


func can_afford_materials(cost: Dictionary) -> bool:
	for k in cost:
		if material_count(k) < int(cost[k]):
			return false
	return true


func spend_materials(cost: Dictionary) -> void:
	for k in cost:
		materials[k] = material_count(k) - int(cost[k])
	_changed()


## Applies a drops dictionary ({"shards", "materials", "orbs"}).
func grant(drops: Dictionary) -> void:
	for k in drops.get("shards", {}):
		add_shards(k, int(drops.shards[k]))
	for k in drops.get("materials", {}):
		materials[k] = material_count(k) + int(drops.materials[k])
	for k in drops.get("orbs", {}):
		orbs[k] = orb_count(k) + int(drops.orbs[k])
	_changed()


# ---------- recipes ----------

func knows_recipe(id: String) -> bool:
	return known_recipes.has(id)


func learn_recipe(id: String) -> bool:
	if knows_recipe(id) or not CraftingDB.RECIPES.has(id):
		return false
	known_recipes.append(id)
	_changed()
	return true


func random_unknown_recipe(source: String) -> String:
	var pool: Array = []
	for id in CraftingDB.RECIPES:
		if CraftingDB.RECIPES[id].source == source and not knows_recipe(id):
			pool.append(id)
	return "" if pool.is_empty() else String(pool.pick_random())


func buy_recipe(id: String) -> bool:
	if knows_recipe(id) or not pay(CraftingDB.RECIPES[id].get("price", {})):
		return false
	return learn_recipe(id)


## Currency exchange at the Merchant (see Currency.VENDOR_ORBS).
func buy_orb(id: String) -> bool:
	var price := Currency.orb_price(id)
	if price.is_empty() or not pay(price):
		return false
	add_orb(id, 1)
	return true


## Materials come in bundles (CraftingDB.MATERIALS[id].bundle = [amount, price]).
func buy_material(id: String) -> bool:
	var b: Array = CraftingDB.MATERIALS[id].get("bundle", [])
	if b.is_empty() or not pay(b[1]):
		return false
	add_material(id, int(b[0]))
	return true


# ---------- stash ----------

func stash_count() -> int:
	return stash.count()


## Move a bag item into the first space in the stash it fits.
func stash_item(item: ItemInstance) -> bool:
	if not is_instance_valid(player) or not player.bag.has(item) or not stash.can_fit(item):
		return false
	player.bag.remove(item)
	stash.add(item)
	player.inventory_changed.emit()
	_changed()
	return true


func put_in_stash(item: ItemInstance) -> bool:
	return stash_item(item)


## Move a stash item into the first space in the bag it fits.
func take_from_stash(item: ItemInstance) -> bool:
	if not stash.has(item) or not is_instance_valid(player) or not player.can_fit(item):
		return false
	stash.remove(item)
	player.bag.add(item)
	_settle_overflow()
	player.inventory_changed.emit()
	_changed()
	return true


## Drag within the stash: `item` to top-left cell `at`, swapping with one item it lands on.
func move_in_stash(item: ItemInstance, at: Vector2i) -> bool:
	var plan := stash.plan_drop(item, at, stash)
	if not stash.has(item) or plan.is_empty():
		return false
	stash.apply_drop(item, at, stash, plan)
	_changed()
	return true


## Whether a bag item may be dropped at `at` in the stash (into space, or swapping with one item
## that then fits in the bag).
func can_bag_to_stash(item: ItemInstance, at: Vector2i) -> bool:
	return is_instance_valid(player) and player.bag.has(item) and not stash.plan_drop(item, at, player.bag).is_empty()


func bag_to_stash(item: ItemInstance, at: Vector2i) -> bool:
	if not can_bag_to_stash(item, at):
		return false
	stash.apply_drop(item, at, player.bag, stash.plan_drop(item, at, player.bag))
	player.inventory_changed.emit()
	_changed()
	return true


## Whether a stash item may be dropped at `at` in the bag (into space, or swapping with one item
## that then fits in the stash).
func can_stash_to_bag(item: ItemInstance, at: Vector2i) -> bool:
	return is_instance_valid(player) and stash.has(item) and not player.bag.plan_drop(item, at, stash).is_empty()


func stash_to_bag(item: ItemInstance, at: Vector2i) -> bool:
	if not can_stash_to_bag(item, at):
		return false
	player.bag.apply_drop(item, at, stash, player.bag.plan_drop(item, at, stash))
	_settle_overflow()
	player.inventory_changed.emit()
	_changed()
	return true


## Move overflow items into the stash where they now fit. True if any moved.
func _settle_overflow() -> bool:
	var moved := false
	for it in stash_overflow.duplicate():
		if stash.add(it):
			stash_overflow.erase(it)
			moved = true
	return moved


## Anything that couldn't be placed goes to the stash, or waits in the overflow for room.
func _keep(items: Array[ItemInstance]) -> void:
	for it in items:
		if not stash.add(it):
			stash_overflow.append(it)


## Sells a bag item to the Merchant for orbs and shards. Returns what was paid ({} if it couldn't).
func sell_item(item: ItemInstance) -> Dictionary:
	if not is_instance_valid(player) or not player.inventory.has(item):
		return {}
	var r := Currency.sell_value(item)
	player.remove_from_bag(item)
	grant_currency(r)
	return r


# ---------- passive tree (PassiveTree, one per class) ----------

## Skill gems: the gem's level plus "+level to all skill gems" passives.
func get_skill_rank(skill_id: String) -> int:
	return gem_level(skill_id) + int(passive_value("gem_level"))


## You own the skill gem (in the pouch or a slot).
func is_skill_unlocked(skill_id: String) -> bool:
	return skill_gem_count(skill_id) > 0 or slot_of(skill_id) >= 0


func _class_id() -> String:
	return player.class_def.id if is_instance_valid(player) and player.class_def != null else char_class


func allocated_nodes() -> Array:
	if not passive_nodes.has(_class_id()):
		passive_nodes[_class_id()] = []
	return passive_nodes[_class_id()]


func is_node_allocated(node_id: String) -> bool:
	return node_id == PassiveTree.get_tree(_class_id()).start or allocated_nodes().has(node_id)


## Total of a stat key over every allocated node of your class's tree.
func passive_value(key: String) -> float:
	var total := 0.0
	var cid := _class_id()
	for nid in allocated_nodes():
		var n := PassiveTree.get_node(cid, String(nid))
		if not n.is_empty() and n.stats.has(key):
			total += float(n.stats[key])
	# Legendary powers and set bonuses of the gear being worn (UniqueItems)
	if is_instance_valid(player):
		total += float(player.item_powers.get(key, 0.0))
	return total


## "" if this node can be taken now: it must link to a node you already have.
func node_block_reason(node_id: String) -> String:
	var n := PassiveTree.get_node(_class_id(), node_id)
	if n.is_empty():
		return "Unknown node"
	if is_node_allocated(node_id):
		return "Already allocated"
	var linked := false
	for l in n.links:
		if is_node_allocated(String(l)):
			linked = true
			break
	if not linked:
		return "Must connect to a node you already have"
	if skill_points <= 0:
		return "No passive points"
	return ""


func allocate_node(node_id: String) -> bool:
	if node_block_reason(node_id) != "":
		return false
	allocated_nodes().append(node_id)
	skill_points -= 1
	_on_skills_modified()
	return true


## A node can be refunded if everything else you have still connects back to the start.
func can_refund_node(node_id: String) -> bool:
	if not allocated_nodes().has(node_id):
		return false
	var tree := PassiveTree.get_tree(_class_id())
	var keep := {}
	for nid in allocated_nodes():
		if nid != node_id:
			keep[nid] = true
	var seen := {tree.start: true}
	var queue: Array = [tree.start]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for l in tree.nodes[cur].links:
			if keep.has(l) and not seen.has(l):
				seen[l] = true
				queue.append(l)
	return seen.size() - 1 == keep.size()


## Refunding one node costs an Orb of Regret (the Mystic's full reset is free).
func refund_node(node_id: String) -> bool:
	if not can_refund_node(node_id) or orb_count("regret") <= 0:
		return false
	orbs["regret"] = orb_count("regret") - 1
	allocated_nodes().erase(node_id)
	skill_points += 1
	_on_skills_modified()
	return true


## Points spent in your class's passive tree.
func points_spent() -> int:
	return allocated_nodes().size()


## Refund the whole passive tree. For the respec NPC.
func reset_all_skills() -> void:
	skill_points += points_spent()
	passive_nodes[_class_id()] = []
	_on_skills_modified()


# ---------- experience ----------

const MAX_LEVEL := 100

## XP needed to go from `lvl` to `lvl + 1`.
static func xp_to_next(lvl: int) -> float:
	return roundf(60.0 * pow(float(lvl), 1.5))


## Each level gained grants one skill point.
func add_xp(amount: float) -> void:
	xp += amount
	_grant_gem_xp(amount)
	var gained := false
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		skill_points += 1
		gained = true
		leveled_up.emit(level)
	if level >= MAX_LEVEL:
		xp = 0.0  # capped (skill gems still gain XP)
	if gained:
		skills_changed.emit()
		_changed()
	else:
		_queue_save()  # no UI refresh needed for plain XP ticks


# ---------- gems ----------

# ---------- flasks ----------

## A Normal flask of the given base.
func _new_flask(base_id: String, ilvl := 1) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(base_id)
	it.ilvl = ilvl
	it.display_name = it.base.display_name
	return it


## Buy a Normal flask from the Merchant.
func buy_flask(base_id: String, price: Dictionary) -> bool:
	if not is_instance_valid(player) or LootGenerator.base_by_id(base_id) == null:
		return false
	var it := _new_flask(base_id, maxi(level, 1))
	if not player.can_fit(it) or not pay(price):
		return false
	player.add_to_bag(it)
	return true


## Older saves had potion stacks (id -> count) and one potion type in the potion slot. Each type
## owned becomes one Normal flask of the same kind and strength; the slotted one is worn.
func _flasks_from_potions(potions: Dictionary, slotted: String) -> void:
	const SIZES := ["small", "medium", "large"]
	_pending_flasks = []
	_pending_loose_flasks.clear()
	var ids: Array = potions.keys()
	ids.sort_custom(func(a, b): return String(a) == slotted and String(b) != slotted)
	for id in ids:
		if int(potions[id]) <= 0:
			continue
		var parts := String(id).rsplit("_", true, 1)
		if parts.size() != 2:
			continue
		var kind := "life" if parts[0] == "health" else ("power" if parts[0] == "power" else "")
		var tier := clampi(int(parts[1]), 1, 3)
		if kind == "":
			continue
		var it := _new_flask("%s_%s_flask" % [SIZES[tier - 1], kind])
		if String(id) == slotted and _pending_flasks.is_empty():
			_pending_flasks.append(it.to_dict())
		else:
			_pending_loose_flasks.append(it)
	if _pending_flasks.is_empty():
		_pending_flasks.append(_new_flask("small_life_flask").to_dict())


# ---------- socket gems and support gems ----------

func gem_count(gem_id: String) -> int:
	return int(gems.get(gem_id, 0))


func add_gem(gem_id: String, amount: int = 1) -> void:
	gems[gem_id] = maxi(gem_count(gem_id) + amount, 0)
	if gems[gem_id] == 0:
		gems.erase(gem_id)
	_changed()


## Put a gem from the pouch into socket `idx` of an item in the bag or worn. An occupied socket
## swaps: the old gem goes back to the pouch. idx past the filled sockets uses the next free one.
func socket_gem(item: ItemInstance, idx: int, gem_id: String) -> bool:
	if item == null or not is_instance_valid(player) or gem_count(gem_id) <= 0 or item.sockets <= 0:
		return false
	if idx >= item.gems.size() and item.gems.size() >= item.sockets:
		return false
	player.modify_item(item, func():
		if idx < item.gems.size():
			var old: String = item.gems[idx]
			item.gems[idx] = gem_id
			gems[old] = gem_count(old) + 1
		else:
			item.gems.append(gem_id)
		gems[gem_id] = gem_count(gem_id) - 1
		if gems[gem_id] <= 0:
			gems.erase(gem_id)
	)
	_changed()
	return true


## Jeweler: turn GemDef.COMBINE_COUNT gems into one of the next tier, `times` times (or as
## many as possible when times <= 0). Returns how many were made.
func combine_gems(gem_id: String, times: int = 1) -> int:
	var g := GemDef.info(gem_id)
	if g.is_empty() or g.tier >= GemDef.MAX_TIER:
		return 0
	var cost := GemDef.combine_cost(g.tier)
	var made := 0
	while (times <= 0 or made < times) and gem_count(gem_id) >= GemDef.COMBINE_COUNT and can_afford(cost):
		gems[gem_id] = gem_count(gem_id) - GemDef.COMBINE_COUNT
		for oid in cost:
			orbs[oid] = orb_count(oid) - int(cost[oid])
		var up := GemDef.make_id(g.type, g.tier + 1)
		gems[up] = gem_count(up) + 1
		made += 1
	if gem_count(gem_id) <= 0:
		gems.erase(gem_id)
	if made > 0:
		_changed()
	return made


## Take the gem out of socket `idx` and return it to the pouch.
func unsocket_gem(item: ItemInstance, idx: int) -> bool:
	if item == null or not is_instance_valid(player) or idx < 0 or idx >= item.gems.size():
		return false
	player.modify_item(item, func():
		var gid: String = item.gems[idx]
		item.gems.remove_at(idx)
		gems[gid] = gem_count(gid) + 1
	)
	_changed()
	return true


func rune_count(rune_id: String) -> int:
	return int(runes.get(rune_id, 0))


func add_rune(rune_id: String, amount: int = 1) -> void:
	runes[rune_id] = maxi(rune_count(rune_id) + amount, 0)
	_changed()


# ---------- skill gems & skill slots (Path of Exile style) ----------

func _empty_slots() -> Array:
	var out: Array = []
	for i in SKILL_SLOTS:
		out.append({"skill": "", "supports": []})
	return out


## Support links each slot has at your level: 1, then +1 at levels 5, 10, 15 and 20.
func links_unlocked() -> int:
	return clampi(1 + int(level / 5.0), 1, MAX_LINKS)


## Character level at which the next link opens (0 when all are open).
func next_link_level() -> int:
	var n := links_unlocked()
	return 0 if n >= MAX_LINKS else n * 5


func skill_gem_count(skill_id: String) -> int:
	return int(skill_gems.get(skill_id, 0))


func add_skill_gem(skill_id: String, amount := 1) -> void:
	skill_gems[skill_id] = maxi(skill_gem_count(skill_id) + amount, 0)
	if skill_gems[skill_id] == 0:
		skill_gems.erase(skill_id)
	_changed()


func buy_skill_gem(skill_id: String) -> bool:
	if not pay(SkillTree.gem_price(skill_id)):
		return false
	add_skill_gem(skill_id, 1)
	return true


func gem_level(skill_id: String) -> int:
	return clampi(int(gem_levels.get(skill_id, 1)), 1, SkillTree.GEM_MAX_LEVEL)


## Experience a gem needs to go from `lvl` to `lvl + 1`.
static func gem_xp_to_next(lvl: int) -> float:
	return roundf(40.0 * pow(float(lvl), 1.6))


func support_level(rune_id: String) -> int:
	return clampi(int(support_levels.get(rune_id, 1)), 1, SkillTree.GEM_MAX_LEVEL)


## A support's effects grow 3% per level above 1 (see SkillDef).
func support_scale(rune_id: String) -> float:
	return 1.0 + 0.03 * (support_level(rune_id) - 1)


## Every support also adds 1% skill damage per level above 1.
func support_damage_bonus(rune_id: String) -> float:
	return 0.01 * (support_level(rune_id) - 1)


## Socketed skill gems, and the support gems linked to them, share the experience you earn.
func _grant_gem_xp(amount: float) -> void:
	var leveled := false
	var supports_done := {}  # the same support can be linked in two slots: it gains once
	for slot in skill_slots:
		var id: String = slot.skill
		if id == "":
			continue
		if _add_gem_xp(gem_levels, gem_xp, id, amount):
			leveled = true
		for rid in slot.supports:
			if not supports_done.has(rid):
				supports_done[rid] = true
				if _add_gem_xp(support_levels, support_xp, String(rid), amount):
					leveled = true
	if leveled:
		_on_skills_modified()


## Gemcutter's Prism: a level's worth of experience for a skill gem (`support` false) or a
## support gem. False if you have no prism or the gem is already at the top level.
func use_gemcutter(id: String, support: bool) -> bool:
	var levels: Dictionary = support_levels if support else gem_levels
	var xps: Dictionary = support_xp if support else gem_xp
	var lvl := clampi(int(levels.get(id, 1)), 1, SkillTree.GEM_MAX_LEVEL)
	if orb_count("gemcutter") <= 0 or lvl >= SkillTree.GEM_MAX_LEVEL:
		return false
	orbs["gemcutter"] = orb_count("gemcutter") - 1
	_add_gem_xp(levels, xps, id, gem_xp_to_next(lvl))
	_on_skills_modified()
	return true


## Adds XP to one gem in `levels` / `xps`; true if it levelled up.
func _add_gem_xp(levels: Dictionary, xps: Dictionary, id: String, amount: float) -> bool:
	var lvl := clampi(int(levels.get(id, 1)), 1, SkillTree.GEM_MAX_LEVEL)
	if lvl >= SkillTree.GEM_MAX_LEVEL:
		return false
	var x := float(xps.get(id, 0.0)) + amount
	var up := false
	while lvl < SkillTree.GEM_MAX_LEVEL and x >= gem_xp_to_next(lvl):
		x -= gem_xp_to_next(lvl)
		lvl += 1
		up = true
	if lvl >= SkillTree.GEM_MAX_LEVEL:
		x = 0.0
	levels[id] = lvl
	xps[id] = x
	return up


func slot_skill(i: int) -> String:
	return String(skill_slots[i].skill) if i >= 0 and i < skill_slots.size() else ""


func slot_supports(i: int) -> Array:
	return skill_slots[i].supports if i >= 0 and i < skill_slots.size() else []


## Slot holding this skill gem, or -1.
func slot_of(skill_id: String) -> int:
	for i in skill_slots.size():
		if skill_slots[i].skill == skill_id:
			return i
	return -1


## "" if the skill gem can be socketed into a slot now.
func skill_gem_block_reason(skill_id: String) -> String:
	var need := SkillTree.gem_level_req(skill_id)
	if level < need:
		return "Requires character level %d" % need
	return ""


## Socket a skill gem from the pouch into slot i (the gem already there goes back to the pouch;
## its supports stay in the slot). A skill can only be in one slot: if it is elsewhere, the two
## slots' skills swap.
func set_slot_skill(i: int, skill_id: String) -> bool:
	if i < 0 or i >= SKILL_SLOTS or skill_gem_block_reason(skill_id) != "":
		return false
	var other := slot_of(skill_id)
	if other == i:
		return true
	if other >= 0:
		skill_slots[other].skill = skill_slots[i].skill
		skill_slots[i].skill = skill_id
	else:
		if skill_gem_count(skill_id) <= 0:
			return false
		if skill_slots[i].skill != "":
			skill_gems[skill_slots[i].skill] = skill_gem_count(skill_slots[i].skill) + 1
		skill_gems[skill_id] = skill_gem_count(skill_id) - 1
		if skill_gems[skill_id] <= 0:
			skill_gems.erase(skill_id)
		skill_slots[i].skill = skill_id
	_on_skills_modified()
	return true


## Take the skill gem out of slot i back to the pouch.
func clear_slot_skill(i: int) -> bool:
	var id := slot_skill(i)
	if id == "":
		return false
	skill_slots[i].skill = ""
	skill_gems[id] = skill_gem_count(id) + 1
	_on_skills_modified()
	return true


## Swap two whole slots (skill + supports).
func swap_slots(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= SKILL_SLOTS or b >= SKILL_SLOTS:
		return false
	var t = skill_slots[a]
	skill_slots[a] = skill_slots[b]
	skill_slots[b] = t
	_on_skills_modified()
	return true


## Put a support gem from the pouch into link `idx` of slot i (replacing what is there).
func socket_support(i: int, idx: int, rune_id: String) -> bool:
	if rune_count(rune_id) <= 0 or i < 0 or i >= SKILL_SLOTS:
		return false
	var list: Array = skill_slots[i].supports.duplicate()
	if idx >= links_unlocked():
		return false
	var old := ""
	if idx < list.size():
		old = list[idx]
		list[idx] = rune_id
	else:
		list.append(rune_id)
	if not SkillDef.supports_valid(list):
		return false
	skill_slots[i].supports = list
	runes[rune_id] = rune_count(rune_id) - 1
	if old != "":
		runes[old] = rune_count(old) + 1
	_on_skills_modified()
	return true


func unsocket_support(i: int, idx: int) -> bool:
	if i < 0 or i >= SKILL_SLOTS:
		return false
	var list: Array = skill_slots[i].supports
	if idx < 0 or idx >= list.size():
		return false
	var rid: String = list[idx]
	list.remove_at(idx)
	runes[rid] = rune_count(rid) + 1
	_on_skills_modified()
	return true


## Move a linked support to another link (any slot); swaps if the target link is filled.
func move_support(from_slot: int, from_idx: int, to_slot: int, to_idx: int) -> bool:
	var a: Array = skill_slots[from_slot].supports.duplicate()
	if from_idx < 0 or from_idx >= a.size() or to_idx >= links_unlocked():
		return false
	var rid: String = a[from_idx]
	if from_slot == to_slot:
		if to_idx >= a.size():
			return false
		a[from_idx] = a[to_idx]
		a[to_idx] = rid
		skill_slots[from_slot].supports = a
		_on_skills_modified()
		return true
	var b: Array = skill_slots[to_slot].supports.duplicate()
	if to_idx < b.size():
		a[from_idx] = b[to_idx]
		b[to_idx] = rid
	else:
		a.remove_at(from_idx)
		b.append(rid)
	if not SkillDef.supports_valid(a) or not SkillDef.supports_valid(b):
		return false
	skill_slots[from_slot].supports = a
	skill_slots[to_slot].supports = b
	_on_skills_modified()
	return true


## The skill in slot i with its linked supports applied (null for an empty slot).
func get_slot_skill_def(i: int) -> SkillDef:
	var id := slot_skill(i)
	if id == "":
		return null
	var sk := SkillTree.get_skill(id)
	if sk == null:
		return null
	sk.socketed_runes.clear()
	for rid in slot_supports(i):
		sk.socketed_runes.append(String(rid))
	for r in sk.get_runes():
		sk.duration *= r.duration_mult
	sk.duration *= 1.0 + passive_value("skill_dur:" + id)
	return sk


## A skill with the supports of the slot it is in (none if it isn't slotted).
func get_skill_def_with_runes(skill_id: String) -> SkillDef:
	var i := slot_of(skill_id)
	return get_slot_skill_def(i) if i >= 0 else SkillTree.get_skill(skill_id)


## One entry per skill slot (always SKILL_SLOTS); null for an empty slot.
func get_equipped_skills() -> Array[SkillDef]:
	var list: Array[SkillDef] = []
	for i in SKILL_SLOTS:
		list.append(get_slot_skill_def(i))
	return list


## Old saves: skills learned in the tree become skill gems (their rank becomes the gem level), the
## action bar becomes skill slots, runes on skills become linked supports, points come back.
func _migrate_to_skill_gems(data: Dictionary) -> void:
	var old_unlocked: Dictionary = data.get("unlocked_skills", {})
	var old_runes: Dictionary = data.get("skill_runes", {})
	var old_bar: Array = data.get("equipped_skills", [])
	var refund := 0
	var owned := {}  # this character's skills as gems; loose skill gems are the account's
	gem_levels = {}
	gem_xp = {}
	skill_slots = _empty_slots()
	for id in old_unlocked:
		var sk := SkillTree.get_skill(String(id))
		if sk == null:
			refund += int(old_unlocked[id])  # an old passive: points come back for the new tree
			continue
		else:
			refund += int(old_unlocked[id])
			gem_levels[String(id)] = clampi(int(old_unlocked[id]), 1, SkillTree.GEM_MAX_LEVEL)
			owned[String(id)] = true
	for mods in data.get("skill_mods", {}).values():
		refund += mods.size()
	for i in mini(old_bar.size(), SKILL_SLOTS):
		var id := String(old_bar[i])
		if id != "" and owned.has(id):
			owned.erase(id)
			skill_slots[i].skill = id
	for id in owned:  # the ones not on the bar join the shared pool
		skill_gems[id] = skill_gem_count(id) + 1
	for id in old_runes:
		var slot := slot_of(String(id))
		for rid in old_runes[id]:
			if slot >= 0 and skill_slots[slot].supports.size() < links_unlocked():
				skill_slots[slot].supports.append(String(rid))
			else:
				runes[String(rid)] = rune_count(String(rid)) + 1
	skill_points += refund


## Keep slot data sane after loading (supports beyond the open links go back to the pouch).
func _fix_slots() -> void:
	while skill_slots.size() < SKILL_SLOTS:
		skill_slots.append({"skill": "", "supports": []})
	for slot in skill_slots:
		slot.skill = String(slot.get("skill", ""))
		var sup: Array = slot.get("supports", [])
		while sup.size() > links_unlocked():
			var rid: String = sup.pop_back()
			runes[rid] = rune_count(rid) + 1
		slot.supports = sup


func _on_skills_modified() -> void:
	if is_instance_valid(player):
		player.sync_skills_from_state()
	skills_changed.emit()
	_changed()


# ---------- Player hookup and saving ----------

func attach_player(p: Player) -> void:
	player = p
	LootGenerator.smart_class = p.class_def
	_restoring = true
	# Old saves list items by slot; ones that no longer fit the grid go to the stash, not lost
	var homeless := p.bag.load_array(_pending_inventory)
	if not homeless.is_empty():
		_keep(homeless)
		_save_account()
	for slot in _pending_alt_set:
		var alt := ItemInstance.from_dict(_pending_alt_set[slot])
		if alt != null and slot in Player.SET_SLOTS:
			p.alt_set[slot] = alt
	p.active_set = _pending_active_set
	p.flasks = [null, null, null, null, null]
	for i in mini(_pending_flasks.size(), Player.FLASK_SLOTS):
		if _pending_flasks[i] is Dictionary:
			var f := ItemInstance.from_dict(_pending_flasks[i])
			if f != null and f.is_flask():
				p.flasks[i] = f
	# Flasks an older save's potions turned into: into the bag, or the stash if it is full
	var extra: Array[ItemInstance] = []
	for f in _pending_loose_flasks:
		if not p.bag.add(f):
			extra.append(f)
	_pending_loose_flasks.clear()
	if not extra.is_empty():
		_keep(extra)
		_save_account()
	for slot in _pending_equipment:
		var it := ItemInstance.from_dict(_pending_equipment[slot])
		if it != null:
			p.equip_to(it, slot, true)
	p.hp = p.stats.get_stat("max_life")
	_restoring = false
	p.inventory_changed.connect(_changed)
	p.sync_skills_from_state()
	p.inventory_changed.emit()


func _changed() -> void:
	changed.emit()
	_queue_save()


func _queue_save() -> void:
	if _restoring or _save_queued:
		return
	_save_queued = true
	save.call_deferred()


func save() -> void:
	_save_queued = false
	if char_id == "":
		return  # no character picked (select screen, test scenes)
	var inv: Array = []
	var eq := {}
	if is_instance_valid(player):
		inv = player.bag.to_array()
		for slot in player.equipment:
			eq[slot] = player.equipment[slot].to_dict()
		_pending_inventory = inv
		_pending_equipment = eq
		_pending_alt_set = {}
		_pending_flasks = player.flasks.map(func(f): return f.to_dict() if f != null else null)
		for slot in player.alt_set:
			_pending_alt_set[slot] = player.alt_set[slot].to_dict()
		_pending_active_set = player.active_set
	else:
		inv = _pending_inventory
		eq = _pending_equipment

	var data := {
		"version": 2, "name": char_name, "class": char_class, "tutorial_stage": tutorial_stage,
		"recipes": known_recipes, "runs_cleared": runs_cleared,
		"rift_unlocked": rift_unlocked, "rift_level": rift_level,
		"inventory": inv, "equipment": eq,
		"alt_weapon_set": _pending_alt_set, "active_weapon_set": _pending_active_set,
		# Skills & Runes
		"skill_points": skill_points,
		"level": level,
		"xp": xp,
		"skill_tree_version": 2,
		"passive_nodes": passive_nodes,
		"gem_levels": gem_levels,
		"gem_xp": gem_xp,
		"support_levels": support_levels,
		"support_xp": support_xp,
		"skill_slots": skill_slots,
		"flasks": _pending_flasks,
	}
	_write_json(_char_path(char_id), data)
	for c in characters:
		if c.id == char_id:
			c.level = level
	_save_account()


# ---------- characters and the account ----------

func _char_path(id: String) -> String:
	return "%s/%s.json" % [CHAR_DIR, id]


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _save_account() -> void:
	_write_json(ACCOUNT_PATH, {
		"characters": characters, "last": last_character,
		"stash": stash.to_array(),
		"stash_overflow": stash_overflow.map(func(i): return i.to_dict()),
		"shared": {"orbs": orbs, "shards": shards, "materials": materials,
			"skill_gems": skill_gems, "runes": runes, "gems": gems},
	})


func _load_account() -> void:
	DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	var acc := _read_json(ACCOUNT_PATH)
	if acc.is_empty():
		_migrate_single_save()
		_load_shared({})
		_save_account()
		return
	characters.clear()
	for c in acc.get("characters", []):
		if FileAccess.file_exists(_char_path(String(c.get("id", "")))):
			characters.append({"id": String(c.id), "name": String(c.get("name", "Hero")),
				"class": String(c.get("class", "warrior")), "level": int(c.get("level", 1))})
	last_character = String(acc.get("last", ""))
	_load_stash(acc.get("stash", []), acc.get("stash_overflow", []))
	_load_shared(acc)


func _load_stash(list: Array, overflow: Array = []) -> void:
	stash_overflow.clear()
	for d in overflow:
		var it := ItemInstance.from_dict(d)
		if it != null:
			stash_overflow.append(it)
	# The old stash was a list of 60 items; what doesn't fit the grid waits in the overflow
	stash_overflow.append_array(stash.load_array(list))
	_settle_overflow()


## The shared pools from the account. An account from before they were shared gathers them
## from its characters -- every character's orbs, materials and loose gems added together -- and
## takes them out of the character saves, once. A brand-new account gets the starting pools.
func _load_shared(acc: Dictionary) -> void:
	if acc.has("shared"):
		var sh: Dictionary = acc.shared
		orbs = _ints(sh.get("orbs", {}))
		shards = _ints(sh.get("shards", {}))
		materials = _ints(sh.get("materials", {}))
		skill_gems = _ints(sh.get("skill_gems", {}))
		runes = _ints(sh.get("runes", {}))
		gems = _ints(sh.get("gems", {}))
	elif characters.is_empty():
		_starter_pools()
	else:
		for k in SHARED_KEYS:
			set(k, {})
		for c in characters:
			var path := _char_path(String(c.id))
			var data := _read_json(path)
			if data.is_empty():
				continue
			var pools := {
				"orbs": _ints(data.get("orbs", {})),
				"shards": _ints(data.get("shards", {})),
				"materials": _ints(data.get("materials", {})),
				"skill_gems": _ints(data.get("skill_gems", {})),
				# a character saved before these existed was given the starting ones on load
				"runes": _ints(data.get("runes", STARTER_RUNES)),
				"gems": _ints(data.get("gems", {"ruby_1": 2, "topaz_1": 1, "sapphire_1": 1})),
			}
			# Saves from before orbs were the money: their gold becomes orbs of the same worth
			var gold := Currency.gold_to_orbs(int(data.get("gold", 0)))
			for id in gold:
				pools.orbs[id] = int(pools.orbs.get(id, 0)) + int(gold[id])
			for k in SHARED_KEYS:
				var pool: Dictionary = get(k)
				for id in pools[k]:
					pool[id] = int(pool.get(id, 0)) + int(pools[k][id])
				data.erase(k)
			data.erase("gold")
			_write_json(path, data)
		_save_account()
	for id in orbs.keys():
		if not CraftingDB.ORBS.has(id):
			orbs.erase(id)


## The save from before characters existed becomes the first character; its stash becomes the
## account's shared stash.
func _migrate_single_save() -> void:
	var old := _read_json(SAVE_PATH)
	if old.is_empty():
		return
	var id := _new_char_id()
	_load_stash(old.get("stash", []))
	old.erase("stash")
	old["name"] = "Wanderer"
	old["class"] = "warrior"
	_write_json(_char_path(id), old)
	characters = [{"id": id, "name": "Wanderer", "class": "warrior", "level": int(old.get("level", 1))}]
	last_character = id
	_save_account()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".bak"))


func _new_char_id() -> String:
	return "c%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]


func character_info(id: String) -> Dictionary:
	for c in characters:
		if c.id == id:
			return c
	return {}


## Why `name` can't be used for a new character, or "" if it can.
func name_block_reason(new_name: String) -> String:
	var n := new_name.strip_edges()
	if n.is_empty():
		return "Enter a name"
	if n.length() > NAME_MAX_LEN:
		return "Names can be at most %d letters" % NAME_MAX_LEN
	for c in characters:
		if String(c.name).to_lower() == n.to_lower():
			return "You already have a character called %s" % n
	if characters.size() >= MAX_CHARACTERS:
		return "You can have at most %d characters" % MAX_CHARACTERS
	return ""


## Make a fresh level 1 character and make it the one being played. Returns its id ("" if not allowed).
func create_character(new_name: String, class_id: String) -> String:
	if name_block_reason(new_name) != "":
		return ""
	_new_game()
	# New characters start the tutorial with no skills socketed: they pick their first gem there.
	# (Loose skill gems are the account's; they are left alone.)
	skill_slots = _empty_slots()
	tutorial_stage = 0
	char_id = _new_char_id()
	char_name = new_name.strip_edges()
	char_class = class_id
	characters.append({"id": char_id, "name": char_name, "class": char_class, "level": 1})
	last_character = char_id
	save()
	return char_id


## Load a character to play.
func select_character(id: String) -> bool:
	var info := character_info(id)
	var data := _read_json(_char_path(id))
	if info.is_empty() or data.is_empty():
		return false
	_new_game()
	_apply_save(data)
	char_id = id
	char_name = String(info.name)
	char_class = String(info.get("class", "warrior"))
	last_character = id
	_save_account()
	return true


func delete_character(id: String) -> void:
	var path := _char_path(id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	characters = characters.filter(func(c): return c.id != id)
	if last_character == id:
		last_character = ""
	if char_id == id:
		char_id = ""
	_save_account()


## Save and stop playing the current character (back to the select screen).
func leave_character() -> void:
	save()
	char_id = ""
	player = null


## The equipment a saved character is wearing (slot -> ItemInstance), for the select screen.
func peek_equipment(id: String) -> Dictionary:
	var out := {}
	var eq: Dictionary = _read_json(_char_path(id)).get("equipment", {})
	for slot in eq:
		var it := ItemInstance.from_dict(eq[slot])
		if it != null:
			out[slot] = it
	return out


## Load a character. The shared pools (SHARED_KEYS) are the account's, loaded in _load_account.
func _apply_save(data: Dictionary) -> void:
	known_recipes.clear()
	for id in data.get("recipes", []):
		if CraftingDB.RECIPES.has(String(id)):
			known_recipes.append(String(id))
	runs_cleared = int(data.get("runs_cleared", 0))
	rift_unlocked = maxi(1, int(data.get("rift_unlocked", 1)))
	rift_level = clampi(int(data.get("rift_level", 1)), 1, rift_unlocked)
	_pending_inventory = data.get("inventory", [])
	_pending_equipment = data.get("equipment", {})
	_pending_alt_set = data.get("alt_weapon_set", {})
	_pending_active_set = int(data.get("active_weapon_set", 0))

	# Skills & Runes
	skill_points = int(data.get("skill_points", 3))
	level = clampi(int(data.get("level", 1)), 1, MAX_LEVEL)
	xp = float(data.get("xp", 0.0))
	if int(data.get("skill_tree_version", 1)) < 2:
		_migrate_to_skill_gems(data)
	else:
		passive_nodes = data.get("passive_nodes", {})
		if not data.has("passive_nodes"):
			# ranked passives from the Diablo style tree: refund for the new node tree
			for id in data.get("unlocked_skills", {}):
				skill_points += int(data.unlocked_skills[id])
		gem_levels = _ints(data.get("gem_levels", {}))
		gem_xp = data.get("gem_xp", {})
		support_levels = _ints(data.get("support_levels", {}))
		support_xp = data.get("support_xp", {})
		skill_slots = data.get("skill_slots", _empty_slots())
	_fix_slots()
	_fix_passive_points()
	if data.has("flasks"):
		_pending_flasks = data.flasks
		_pending_loose_flasks.clear()
	else:
		_flasks_from_potions(data.get("potions", {"health_1": 3}), String(data.get("potion_slot", "health_1")))
	tutorial_stage = int(data.get("tutorial_stage", TUTORIAL_DONE))  # older saves: already past it


## Passive points are exactly one per level gained. Older saves also got points from rifts and a
## few starting ones: recount, and refund the tree if it holds more nodes than the level allows.
func _fix_passive_points() -> void:
	var budget := level - 1
	var spent := 0
	for c in passive_nodes:
		spent += (passive_nodes[c] as Array).size()
	if spent > budget:
		passive_nodes = {}
		spent = 0
	skill_points = budget - spent


func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = int(d[k])
	return out
