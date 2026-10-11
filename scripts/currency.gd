class_name Currency
extends RefCounted
## Path of Exile style currency: orbs are both crafting tools and the money. There is no gold.
## A price is a Dictionary {orb id: count}. Vendors pay for items in orbs and orb shards
## (SHARDS_PER_ORB shards of an orb join into one orb). The orbs themselves are in CraftingDB.ORBS.

const SHARDS_PER_ORB := 20

## What the Merchant sells each orb for: [paid with orb, how many].
## Exalted, Divine, Annulment and Mirror are never sold: they only drop.
const VENDOR_ORBS := {
	"identify": ["transmute", 1],
	"alteration": ["transmute", 2],
	"augment": ["alteration", 1],
	"chance": ["alteration", 2],
	"jeweller": ["alteration", 2],
	"armourer": ["transmute", 1],
	"whetstone": ["transmute", 2],
	"blessed": ["alteration", 4],
	"scour": ["alteration", 4],
	"alchemy": ["alteration", 5],
	"regret": ["alchemy", 1],
	"regal": ["alchemy", 2],
	"chaos": ["alchemy", 3],
	"gemcutter": ["chaos", 1],
	"vaal": ["chaos", 1],
}

## Old saves: gold is exchanged at this many gold per Transmutation-worth of value.
const GOLD_PER_TRANSMUTE := 15


static func orb_name(id: String) -> String:
	return String(CraftingDB.ORBS.get(id, {}).get("name", id))


static func orb_color(id: String) -> Color:
	return CraftingDB.ORBS.get(id, {}).get("color", Color.WHITE)


## "2 Orb of Alteration" (BBCode, red when you can't afford it).
static func price_text(price: Dictionary, colour_afford := true) -> String:
	var parts: Array[String] = []
	for id in price:
		var ok := GameState.orb_count(id) >= int(price[id])
		var col := orb_color(id) if (ok or not colour_afford) else Color(0.95, 0.40, 0.40)
		parts.append("[color=#%s]%d %s[/color]" % [col.to_html(false), int(price[id]), orb_name(id)])
	return ", ".join(PackedStringArray(parts))


## Short "2 Alt" style tag for small cells.
static func price_tag(price: Dictionary) -> String:
	var parts: Array[String] = []
	for id in price:
		parts.append("%d %s" % [int(price[id]), String(CraftingDB.ORBS[id].get("tag", CraftingDB.ORBS[id].short))])
	return " ".join(PackedStringArray(parts))


## Price of an orb at the Merchant ({} if it is not sold).
static func orb_price(id: String) -> Dictionary:
	if not VENDOR_ORBS.has(id):
		return {}
	return {String(VENDOR_ORBS[id][0]): int(VENDOR_ORBS[id][1])}


## What the Merchant pays for an item, PoE vendor style: {"orbs": {...}, "shards": {...}}.
##   Normal -> Transmutation shards, Magic -> Alteration shards, Rare -> Alchemy shards,
##   Legendary / Set -> an Alchemy orb and Chaos shards.
##   Bonuses: 3+ sockets -> a Jeweller's Orb; 20% quality -> a Whetstone / Armourer's Scrap.
static func sell_value(item: ItemInstance) -> Dictionary:
	var orbs := {}
	var shards := {}
	var bonus := int(item.ilvl / 10.0)
	match item.rarity:
		ItemInstance.Rarity.MAGIC: shards["alteration"] = 3 + bonus
		ItemInstance.Rarity.RARE: shards["alchemy"] = 4 + bonus
		ItemInstance.Rarity.LEGENDARY, ItemInstance.Rarity.SET:
			orbs["alchemy"] = 1
			shards["chaos"] = 5 + bonus
		_: shards["transmute"] = 2 + bonus
	if item.sockets >= 3:
		orbs["jeweller"] = int(orbs.get("jeweller", 0)) + 1
	if item.quality >= ItemInstance.MAX_QUALITY:
		var q := "whetstone" if item.is_weapon() else "armourer"
		orbs[q] = int(orbs.get(q, 0)) + 1
	return {"orbs": orbs, "shards": shards}


## "+3 Alteration Shards, +1 Jeweller's Orb" for a sell_value / reward dictionary.
static func reward_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	for id in r.get("orbs", {}):
		parts.append("+%d %s" % [int(r.orbs[id]), orb_name(id)])
	for id in r.get("shards", {}):
		parts.append("+%d %s Shard%s" % [int(r.shards[id]), CraftingDB.ORBS[id].short, "" if int(r.shards[id]) == 1 else "s"])
	return ", ".join(PackedStringArray(parts))


## Old saves had gold: turn it into orbs of the same worth (Chaos, Alchemy, Alteration, Transmutation).
static func gold_to_orbs(gold: int) -> Dictionary:
	var units := int(gold / float(GOLD_PER_TRANSMUTE))
	var out := {}
	for id in ["chaos", "alchemy", "alteration", "transmute"]:
		var v := int(CraftingDB.ORBS[id].value)
		var n := int(units / float(v))
		if n > 0:
			out[id] = n
			units -= n * v
	return out
