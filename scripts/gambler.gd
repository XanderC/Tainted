class_name Gambler
extends RefCounted
## The Gambler in Ashfall (Diablo II's Gheed): a stall of random gear, every piece unidentified, so
## you pay for what it might be. Most are Magic, some Rare, now and then a Legendary or Set item.
## Its stock (GameState.gamble_stock, saved with the character) is rolled for your level, and is new
## every REFRESH_SECS or as soon as you've bought it all. A piece's price goes by its item level and
## kind (jewellery costs double), never by what it really is.

const STOCK_SIZE := 18
const REFRESH_SECS := 20 * 60
## What a piece really is: [rarity, chance], the rest Magic
const ODDS := [[ItemInstance.Rarity.LEGENDARY, 0.03], [ItemInstance.Rarity.SET, 0.02], [ItemInstance.Rarity.RARE, 0.25]]
## Kinds of gear on the stall, each as often as its weight
const SLOT_WEIGHTS := {"weapon": 4, "offhand": 1, "helmet": 2, "shoulders": 2, "chest": 2, "gloves": 2, "boots": 2,
	"ring": 2, "amulet": 1, "belt": 1}
## [up to item level, price], the first that fits
const PRICES := [[14, {"alteration": 2}], [29, {"alteration": 5}], [44, {"alchemy": 1}], [999, {"chaos": 1}]]


## The stall's wares, new ones first if they are due (time's up, or all sold).
static func stock() -> Array[ItemInstance]:
	if GameState.gamble_stock.is_empty() or seconds_left() <= 0:
		restock()
	return GameState.gamble_stock


## Seconds until the stall is restocked anyway.
static func seconds_left() -> int:
	return GameState.gamble_at + REFRESH_SECS - int(Time.get_unix_time_from_system())


## New wares for your level, all unidentified.
static func restock() -> void:
	var items: Array[ItemInstance] = []
	for i in STOCK_SIZE:
		var it := roll(GameState.level)
		if it != null:
			items.append(it)
	GameState.gamble_stock = items
	GameState.gamble_at = int(Time.get_unix_time_from_system())
	GameState.save_soon()


## One piece for a character of `level`: a random kind of gear, its real rarity rolled by ODDS.
static func roll(level: int) -> ItemInstance:
	var ilvl := maxi(1, level + randi_range(0, 2))
	var r := randf()
	var it: ItemInstance = null
	for o in ODDS:
		if r < float(o[1]):
			if int(o[0]) in [ItemInstance.Rarity.LEGENDARY, ItemInstance.Rarity.SET]:
				it = UniqueItems.roll(ilvl, int(o[0]) == ItemInstance.Rarity.SET, LootGenerator.smart_class)
			else:
				it = LootGenerator.roll_item(ilvl, int(o[0]), _pick_slot())
			break
		r -= float(o[1])
	if it == null:
		it = LootGenerator.roll_item(ilvl, ItemInstance.Rarity.MAGIC, _pick_slot())
	it.unidentify()
	return it


static func _pick_slot() -> String:
	var total := 0
	for s in SLOT_WEIGHTS:
		total += int(SLOT_WEIGHTS[s])
	var n := randi() % total
	for s in SLOT_WEIGHTS:
		n -= int(SLOT_WEIGHTS[s])
		if n < 0:
			return s
	return "weapon"


## What a piece costs: by its item level, double for jewellery.
static func price(it: ItemInstance) -> Dictionary:
	for p in PRICES:
		if it.ilvl <= int(p[0]):
			var out := {}
			for k in p[1]:
				out[k] = int(p[1][k]) * (2 if it.base.slot in ["ring", "amulet"] else 1)
			return out
	return {}


## Buys `it` off the stall into `player`'s bag: "" if bought, otherwise why not.
static func buy(player: Player, it: ItemInstance) -> String:
	if not it in GameState.gamble_stock:
		return "That's gone."
	if not player.bag.can_fit(it):
		return "No room in your bag!"
	if not GameState.pay(price(it)):
		return "Not enough orbs!"
	GameState.gamble_stock.erase(it)
	player.pick_up(it)
	GameState.save_soon()
	return ""
