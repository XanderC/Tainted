class_name MonsterAffix
extends RefCounted
## Elite and Legendary monsters: tougher versions of normal monsters with affixes that give them
## resistances or special abilities (behaviour lives in Enemy). Tune the numbers here.

enum Tier { NORMAL, ELITE, LEGENDARY }

## Per tier: life & damage multipliers, body size, affix count, rift-progress weight, colour.
const TIERS := {
	Tier.ELITE: {"name": "Elite", "hp": 3.5, "damage": 1.5, "size": 1.2, "affixes": 1, "weight": 3,
		"color": Color(0.45, 0.65, 1.0)},
	Tier.LEGENDARY: {"name": "Legendary", "hp": 7.0, "damage": 2.2, "size": 1.4, "affixes": 2, "weight": 6,
		"color": Color(1.0, 0.75, 0.25)},
}

## Chance a pack is led by an elite / legendary, before rift level bonuses.
const ELITE_CHANCE := 0.30
const LEGENDARY_CHANCE := 0.08
const ELITE_CHANCE_PER_LEVEL := 0.02
const LEGENDARY_CHANCE_PER_LEVEL := 0.01

const AFFIXES := {
	"armored": {"name": "Armored", "desc": "Takes 40% less physical damage", "color": Color(0.75, 0.75, 0.8)},
	"fire_res": {"name": "Fireproof", "desc": "Takes 70% less fire damage", "color": Color(1.0, 0.5, 0.2)},
	"cold_res": {"name": "Frostborn", "desc": "Takes 70% less cold damage", "color": Color(0.45, 0.85, 1.0)},
	"lightning_res": {"name": "Grounded", "desc": "Takes 70% less lightning damage", "color": Color(1.0, 0.95, 0.35)},
	"poison_res": {"name": "Plagueborn", "desc": "Takes 70% less poison damage", "color": Color(0.8, 0.35, 1.0)},
	"fast": {"name": "Fast", "desc": "Moves 50% faster", "color": Color(0.6, 1.0, 0.6)},
	"vampiric": {"name": "Vampiric", "desc": "Heals when it hits you", "color": Color(0.95, 0.2, 0.3)},
	"regenerating": {"name": "Regenerating", "desc": "Recovers 2% Life per second", "color": Color(0.4, 0.95, 0.5)},
	"molten": {"name": "Molten", "desc": "Burns you up close, and explodes on death", "color": Color(1.0, 0.45, 0.1)},
	"frozen": {"name": "Frozen", "desc": "Drops frost orbs that burst and slow you", "color": Color(0.5, 0.9, 1.0)},
	"electrified": {"name": "Electrified", "desc": "Sparks fly at you when it is hit", "color": Color(1.0, 0.95, 0.4)},
	"teleporter": {"name": "Teleporter", "desc": "Blinks to your side", "color": Color(0.8, 0.5, 1.0)},
	"shielding": {"name": "Shielding", "desc": "Becomes immune to damage for short bursts", "color": Color(0.9, 0.9, 1.0)},
	"summoner": {"name": "Summoner", "desc": "Raises more zombies", "color": Color(0.6, 0.8, 0.4)},
}

const NAME_FIRST := ["Gorebelly", "Rotfang", "Skarn", "Mortis", "Grimjaw", "Vex", "Ashmaw", "Kroll", "Sorrowgut", "Blight"]
const NAME_TITLE := ["the Defiler", "the Hungering", "the Unburied", "Bonegrinder", "the Wretched",
	"the Plaguebearer", "Skullsplitter", "the Restless", "the Ravenous", "of the Pit"]


## Tier for a new pack leader at this rift level.
static func roll_tier(rift_level: int) -> int:
	var r := randf()
	if r < LEGENDARY_CHANCE + LEGENDARY_CHANCE_PER_LEVEL * (rift_level - 1):
		return Tier.LEGENDARY
	if r < LEGENDARY_CHANCE + ELITE_CHANCE + (LEGENDARY_CHANCE_PER_LEVEL + ELITE_CHANCE_PER_LEVEL) * (rift_level - 1):
		return Tier.ELITE
	return Tier.NORMAL


## Distinct random affixes; one more at rift level 6+.
static func roll_affixes(tier: int, rift_level: int) -> Array[String]:
	var n: int = TIERS[tier].affixes + (1 if rift_level >= 6 else 0)
	var pool: Array = AFFIXES.keys()
	pool.shuffle()
	var out: Array[String] = []
	var has_res := false
	for id in pool:
		if out.size() >= n:
			break
		# at most one elemental resistance, so they stay readable
		if String(id).ends_with("_res"):
			if has_res:
				continue
			has_res = true
		out.append(id)
	return out


static func legendary_name() -> String:
	return "%s %s" % [NAME_FIRST.pick_random(), NAME_TITLE.pick_random()]
