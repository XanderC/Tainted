class_name GemDef
extends RefCounted
## Gems are socketed into equipment and add a stat to it. Each gem type grants one stat;
## its strength comes from the tier (Chipped → Perfect). Gem ids look like "ruby_3".
## Owned gems live in GameState.gems (id -> count); socketed gems in ItemInstance.gems.

const TIER_NAMES := ["Chipped", "Flawed", "", "Flawless", "Perfect"]
const MAX_TIER := 5

const TYPES := {
	"ruby": {"name": "Ruby", "stat": "max_life", "mod": StatBlock.ModType.FLAT, "pct": false,
		"label": "Max Life", "color": Color(0.95, 0.20, 0.25), "values": [10.0, 18.0, 28.0, 40.0, 55.0]},
	"topaz": {"name": "Topaz", "stat": "damage", "mod": StatBlock.ModType.FLAT, "pct": false,
		"label": "Damage", "color": Color(1.0, 0.78, 0.20), "values": [2.0, 4.0, 6.0, 9.0, 13.0]},
	"sapphire": {"name": "Sapphire", "stat": "armor", "mod": StatBlock.ModType.FLAT, "pct": false,
		"label": "Armor", "color": Color(0.25, 0.45, 1.0), "values": [6.0, 11.0, 18.0, 27.0, 38.0]},
	"emerald": {"name": "Emerald", "stat": "attack_speed", "mod": StatBlock.ModType.INCREASED, "pct": true,
		"label": "Increased Attack Speed", "color": Color(0.20, 0.85, 0.40), "values": [0.03, 0.05, 0.07, 0.10, 0.14]},
	"amethyst": {"name": "Amethyst", "stat": "crit_chance", "mod": StatBlock.ModType.FLAT, "pct": true,
		"label": "Critical Chance", "color": Color(0.70, 0.35, 0.95), "values": [0.01, 0.015, 0.02, 0.03, 0.04]},
	"diamond": {"name": "Diamond", "stat": "move_speed", "mod": StatBlock.ModType.INCREASED, "pct": true,
		"label": "Increased Move Speed", "color": Color(0.85, 0.95, 1.0), "values": [0.02, 0.03, 0.05, 0.07, 0.09]},
}


static func make_id(type: String, tier: int) -> String:
	return "%s_%d" % [type, tier]


## Returns {} for an unknown id. Runes (SocketRune) share the gems' pool and sockets, so their ids
## come through here too; `slot` picks a rune's weapon or armour stat ("" describes both).
static func info(id: String, slot: String = "") -> Dictionary:
	if SocketRune.is_rune(id):
		return SocketRune.info(id, slot)
	var parts := id.rsplit("_", true, 1)
	if parts.size() != 2 or not TYPES.has(parts[0]):
		return {}
	var tier := clampi(int(parts[1]), 1, MAX_TIER)
	var t: Dictionary = TYPES[parts[0]]
	var value: float = t.values[tier - 1]
	var tier_name: String = TIER_NAMES[tier - 1]
	var text: String
	if t.pct:
		text = "%s%d%% %s" % ["+" if t.mod == StatBlock.ModType.FLAT else "", int(round(value * 100.0)), t.label]
	else:
		text = "+%d %s" % [int(value), t.label]
	return {
		"id": id, "type": parts[0], "tier": tier,
		"name": (tier_name + " " + t.name).strip_edges(),
		"stat": t.stat, "mod": t.mod, "value": value, "color": t.color, "text": text,
	}


static func icon(id: String) -> Texture2D:
	if SocketRune.is_rune(id):
		return SocketRune.icon(id)
	var g := info(id)
	if g.is_empty():
		return null
	return IconFactory.gem_icon(id, g.color, g.tier)


## Every gem id, ordered by type then tier, then the runes in ladder order (used for pouch ordering).
static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for type in TYPES:
		for tier in range(1, MAX_TIER + 1):
			ids.append(make_id(type, tier))
	ids.append_array(SocketRune.all_ids())
	return ids


const COMBINE_COUNT := 3


# ---------- combining, for gems and runes alike ----------

## How many of this gem or rune the Jeweler combines into one of the next.
static func combine_count_of(id: String) -> int:
	return SocketRune.combine_count(id) if SocketRune.is_rune(id) else COMBINE_COUNT


## The gem or rune one tier up, or "" at the top.
static func next_id(id: String) -> String:
	if SocketRune.is_rune(id):
		return SocketRune.next_id(id)
	var g := info(id)
	if g.is_empty() or int(g.tier) >= MAX_TIER:
		return ""
	return make_id(String(g.type), int(g.tier) + 1)


## Orbs the Jeweler charges for one combine of this gem or rune.
static func combine_cost_of(id: String) -> Dictionary:
	if SocketRune.is_rune(id):
		return SocketRune.combine_cost(id)
	return combine_cost(int(info(id).get("tier", 1)))


## Orbs the Jeweler charges to combine COMBINE_COUNT gems of `tier` into one of tier + 1.
static func combine_cost(tier: int) -> Dictionary:
	match tier:
		1: return {"transmute": 1}
		2: return {"alteration": 1}
		3: return {"alteration": 4}
	return {"alchemy": 2}


## A random gem of tier 1..max_tier (lower tiers far more common).
static func random_drop(max_tier: int = 2) -> String:
	var tier := 1
	while tier < clampi(max_tier, 1, MAX_TIER) and randf() < 0.3:
		tier += 1
	return make_id(TYPES.keys().pick_random(), tier)
