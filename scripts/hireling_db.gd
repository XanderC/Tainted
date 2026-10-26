class_name HirelingDB
extends RefCounted
## The kinds of hireling you can take on in Ashfall (Diablo II's mercenaries): what each fights
## with, how it grows, which gear it wears, the skills its gems are drawn from, and what in the
## story opens it up. More open as the campaign goes on: add a type here with its `unlock`.
##
## A type:
##   name, desc, ranged (keeps away and shoots) and the art: `skins` to pick from (pack characters
##   on the archer rig), or none for a figure dressed in its own gear
##   unlock      - quest id that has to be done first ("" = from the start); unlock_text says so
##   weapons     - weapon / shield types it can use (ItemBase.weapon_type)
##   slots       - the equipment slots it has
##   one_handed  - true: no two-handed weapons (it fights with a shield)
##   base, grow  - StatBlock base stats at level 1, and what each level adds
##   attr        - its Attributes at level 1; each level brings Attributes.POINTS_PER_LEVEL for you to add
##                 (ATTR_KEYS only: it has no Adrenaline for Energy to raise)
##   attacks     - its main attack is one of these (skill ids, see SkillTree)
##   skills      - its other skill gems are SKILL_COUNT of these, picked at random

const SKILL_COUNT := 2  ## skill gems besides the main attack
const ATTR_KEYS := ["str", "dex", "vit"]  ## the attributes you add points to
const CANDIDATES := 3   ## hirelings on offer of each type
const NAMES := ["Aldric", "Bryn", "Cassia", "Doran", "Edda", "Falk", "Greta", "Hollis", "Ines", "Joren",
	"Kael", "Lysa", "Marek", "Nessa", "Orrin", "Petra", "Quill", "Rhosyn", "Sorrel", "Tamsin",
	"Ulric", "Vala", "Wynn", "Yara", "Zeb", "Mira", "Tobin", "Sera", "Gideon", "Ilse"]

const TYPES := {
	"sellsword": {
		"name": "Sellsword",
		"desc": "Sword and shield from the outpost's garrison. Stands in front of you and takes the blows.",
		"ranged": false, "skins": [], "unlock": "", "unlock_text": "",
		"weapons": ["sword", "axe", "mace", "shield"], "one_handed": true,
		"slots": ["weapon", "offhand", "helmet", "shoulders", "chest", "gloves", "boots"],
		"base": {"max_life": 110.0, "damage": 8.0, "attack_speed": 1.0, "move_speed": 235.0, "armor": 18.0,
			"crit_chance": 0.05, "life_regen": 1.5},
		"grow": {"max_life": 13.0, "damage": 1.5, "armor": 2.5, "life_regen": 0.15},
		"attr": {"str": 25, "dex": 18, "vit": 20, "ene": 10},
		"attacks": ["cleave", "frenzy", "sundering_strike"],
		"skills": ["shield_slam", "ground_stomp", "battle_cry", "war_cry", "iron_skin"],
	},
	"scout": {
		"name": "Woodland Scout",
		"desc": "Bow-armed outriders who know the Ashwood. Keep their distance and shoot, so keep them out of the crush.",
		"ranged": true, "unlock": "a1_into_the_wastes", "unlock_text": "Finish Into the Ashwood for Brom",
		"skins": ["archer_1", "archer_2", "archer_3", "archer_guy", "elf_archer_1", "elf_archer_2",
			"elf_archer_3", "forest_ranger_1", "forest_ranger_2"],
		"weapons": ["bow", "crossbow"], "one_handed": false,
		"slots": ["weapon", "helmet", "shoulders", "chest", "gloves", "boots"],
		"base": {"max_life": 85.0, "damage": 9.0, "attack_speed": 1.05, "move_speed": 240.0, "armor": 8.0,
			"crit_chance": 0.07, "life_regen": 1.2},
		"grow": {"max_life": 10.0, "damage": 1.6, "armor": 1.5, "life_regen": 0.12},
		"attr": {"str": 15, "dex": 28, "vit": 15, "ene": 12},
		"attacks": ["hl_shot"],
		"skills": ["hl_power_shot", "hl_multishot", "hl_rain"],
	},
	"warden": {
		"name": "Iron Warden",
		"desc": "Caravan wardens who swing two-handed iron. Leap into packs and break them apart.",
		"ranged": false, "skins": [], "unlock": "a1_lost_caravan", "unlock_text": "Recover Hesk's strongbox (The Lost Caravan)",
		"weapons": ["sword", "axe", "mace", "spear"], "one_handed": false,
		"slots": ["weapon", "helmet", "shoulders", "chest", "gloves", "boots"],
		"base": {"max_life": 125.0, "damage": 11.0, "attack_speed": 0.95, "move_speed": 230.0, "armor": 14.0,
			"crit_chance": 0.05, "life_regen": 1.6},
		"grow": {"max_life": 14.0, "damage": 1.9, "armor": 2.0, "life_regen": 0.16},
		"attr": {"str": 30, "dex": 12, "vit": 22, "ene": 8},
		"attacks": ["cleave", "sundering_strike", "double_swing"],
		"skills": ["whirlwind", "leap_slam", "earthquake", "taunt", "war_cry"],
	},
}
## The order types are shown in.
const ORDER := ["sellsword", "scout", "warden"]


static func type_def(id: String) -> Dictionary:
	return TYPES.get(id, {})


## Whether the story has opened this type up yet.
static func unlocked(id: String) -> bool:
	var q := String(type_def(id).get("unlock", ""))
	return q == "" or Quests.state(q) == Quests.DONE


## Its stats at a level (gear not included): {stat: value}.
static func stats_at(id: String, lvl: int) -> Dictionary:
	var t := type_def(id)
	var out := {}
	var base: Dictionary = t.get("base", {})
	var grow: Dictionary = t.get("grow", {})
	for k in base:
		out[k] = float(base[k]) + float(grow.get(k, 0.0)) * (lvl - 1)
	return out


## Its starting attributes (before the points you add): what gear requirements start from.
static func base_attributes(id: String) -> Dictionary:
	var base: Dictionary = type_def(id).get("attr", {})
	var out := {}
	for k in Attributes.KEYS:
		out[k] = int(base.get(k, 0))
	return out


## Its skill gems' level: they grow with the hireling (a level every three).
static func skill_rank(lvl: int) -> int:
	return clampi(1 + int((lvl - 1) / 3.0), 1, SkillTree.GEM_MAX_LEVEL)


## Support links each skill has: like the player's, by the hireling's own level.
static func links_at(lvl: int) -> int:
	return clampi(1 + int(lvl / 5.0), 1, GameState.MAX_LINKS)


## What taking one on costs, by its level (in orbs, the money).
static func hire_price(lvl: int) -> Dictionary:
	if lvl < 10:
		return {"transmute": 2 + int(lvl / 3.0)}
	if lvl < 25:
		return {"alteration": 2 + int((lvl - 10) / 5.0)}
	return {"alchemy": 1 + int((lvl - 25) / 10.0)}


## What bringing a fallen one back costs.
static func revive_price(lvl: int) -> Dictionary:
	if lvl < 10:
		return {"transmute": 1 + int(lvl / 5.0)}
	if lvl < 25:
		return {"alteration": 1 + int((lvl - 10) / 8.0)}
	return {"alteration": 4 + int((lvl - 25) / 6.0)}


## A hireling for hire: {type, name, level, xp, skills: [attack, others...], supports: [[]...],
## look (Appearance) or skin, dead}. Its level is near yours, never above it. `taken`: names
## already on offer, so no two share one.
static func roll_candidate(id: String, player_level: int, taken: Array = []) -> Dictionary:
	var t := type_def(id)
	var lvl := clampi(player_level - randi_range(0, 2), 1, GameState.MAX_LEVEL)
	var others: Array = (t.skills as Array).duplicate()
	others.shuffle()
	var skills: Array = [String((t.attacks as Array).pick_random())]
	for i in mini(SKILL_COUNT, others.size()):
		skills.append(String(others[i]))
	var free := NAMES.filter(func(n): return not taken.has(n))
	var c := {"type": id, "name": String((free if not free.is_empty() else NAMES).pick_random()), "level": lvl, "xp": 0.0, "skills": skills,
		"supports": skills.map(func(_s): return []), "dead": false}
	var skins: Array = t.get("skins", [])
	if skins.is_empty():
		c["look"] = Appearance.random_look()
	else:
		c["skin"] = String(skins.pick_random())
	return c
