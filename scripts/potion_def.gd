class_name PotionDef
extends RefCounted
## Potions: consumable stacks kept in GameState.potions (id -> count). One potion type sits in the
## potion slot (GameState.potion_slot) and is drunk with the HUD potion button (or Q).
## Ids look like "health_2": kind + tier. "power" potions restore the class resource
## (Adrenaline for the Warrior, Mana for casters).

const COOLDOWN := 6.0  # seconds between potions
const TIER_NAMES := ["Minor", "Greater", "Superior"]
const MAX_TIER := 3

const KINDS := {
	"health": {"name": "Health Potion", "color": Color(0.90, 0.15, 0.20),
		"amounts": [0.30, 0.50, 0.75], "prices": [{"transmute": 1}, {"alteration": 2}, {"alchemy": 1}]},   # fraction of max life
	"power": {"name": "%s Potion", "color": Color(1.0, 0.55, 0.10),
		"amounts": [40.0, 70.0, 100.0], "prices": [{"transmute": 1}, {"alteration": 2}, {"alchemy": 1}]},  # flat resource
}


static func make_id(kind: String, tier: int) -> String:
	return "%s_%d" % [kind, tier]


## {} for an unknown id. power_name: the class resource name, e.g. "Adrenaline".
static func info(id: String, power_name := "Adrenaline") -> Dictionary:
	var parts := id.rsplit("_", true, 1)
	if parts.size() != 2 or not KINDS.has(parts[0]):
		return {}
	var kind: String = parts[0]
	var k: Dictionary = KINDS[kind]
	var tier := clampi(int(parts[1]), 1, MAX_TIER)
	var amount: float = k.amounts[tier - 1]
	var base_name: String = k.name % power_name if kind == "power" else k.name
	var desc: String
	if kind == "health":
		desc = "Restores %d%% of Maximum Life" % int(round(amount * 100.0))
	else:
		desc = "Restores %d %s" % [int(amount), power_name]
	return {
		"id": id, "kind": kind, "tier": tier, "amount": amount,
		"name": "%s %s" % [TIER_NAMES[tier - 1], base_name],
		"color": k.color, "desc": desc, "price": k.prices[tier - 1],
	}


static func icon(id: String) -> Texture2D:
	var p := info(id)
	if p.is_empty():
		return null
	return IconFactory.potion_icon(id, p.color, p.tier)


## Every potion id, health first, then by tier.
static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for kind in KINDS:
		for t in range(1, MAX_TIER + 1):
			ids.append(make_id(kind, t))
	return ids
