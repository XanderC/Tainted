class_name MonsterKinds
extends RefCounted
## The monsters a rift can throw at you, each a character from the packs (RigSprite.skin). A pack
## of monsters is all one kind. Deeper rifts (min_level) add the tougher kinds; stats are
## multipliers on the rift's normal monster.

## id: name, skin ("" = the rig's own zombie), min_level, hp / speed / damage multipliers
const KINDS := {
	"zombie": {"name": "Zombie", "skin": "", "min_level": 1, "hp": 1.0, "speed": 1.0, "damage": 1.0},
	"villager": {"name": "Rotting Villager", "skins": ["zombie_villager_1", "zombie_villager_2", "zombie_villager_3"], "min_level": 1, "hp": 0.9, "speed": 0.9, "damage": 0.9},
	"skeleton": {"name": "Skeleton", "skins": ["skeleton_1", "skeleton_2", "skeleton_3"], "min_level": 1, "hp": 0.85, "speed": 1.1, "damage": 1.0},
	"goblin": {"name": "Goblin", "skins": ["goblin", "goblin_1", "goblin_2", "goblin_3"], "min_level": 1, "hp": 0.7, "speed": 1.3, "damage": 0.8},
	"ghoul": {"name": "Ghoul", "skin": "ghoul", "min_level": 2, "hp": 0.9, "speed": 1.35, "damage": 1.0},
	"mummy": {"name": "Mummy", "skin": "mummy", "min_level": 2, "hp": 1.4, "speed": 0.8, "damage": 1.1},
	"skeleton_warrior": {"name": "Skeleton Warrior", "skins": ["skeleton_warrior_1", "skeleton_warrior_2"], "min_level": 3, "hp": 1.15, "speed": 1.0, "damage": 1.15},
	"orc": {"name": "Orc", "skin": "orc", "min_level": 3, "hp": 1.4, "speed": 0.95, "damage": 1.25},
	"orc_shaman": {"name": "Orc Shaman", "skins": ["orc_shaman_1", "orc_shaman_2"], "min_level": 3, "hp": 1.0, "speed": 1.0, "damage": 1.2},
	"gnoll": {"name": "Gnoll", "skin": "gnoll", "min_level": 4, "hp": 1.1, "speed": 1.25, "damage": 1.1},
	"dark_elf": {"name": "Dark Elf", "skins": ["dark_elf_1", "dark_elf_2"], "min_level": 5, "hp": 1.0, "speed": 1.3, "damage": 1.3},
	"skeleton_viking": {"name": "Draugr", "skins": ["skeleton_viking_1", "skeleton_viking_2"], "min_level": 5, "hp": 1.35, "speed": 1.0, "damage": 1.3},
	"skeleton_crusader": {"name": "Fallen Crusader", "skins": ["skeleton_crusader_1", "skeleton_crusader_2"], "min_level": 6, "hp": 1.5, "speed": 0.95, "damage": 1.35},
	"devil": {"name": "Devil", "skin": "devil", "min_level": 7, "hp": 1.3, "speed": 1.2, "damage": 1.45},
	"ghost_knight": {"name": "Ghost Knight", "skin": "ghost_knight", "min_level": 8, "hp": 1.6, "speed": 1.05, "damage": 1.5},
}

## Rift bosses: id -> name, skin. One is picked for each rift.
const BOSSES := {
	"minotaur": {"name": "The Horned Butcher", "skin": "minotaur"},
	"golem": {"name": "The Stone Colossus", "skin": "golem"},
	"ogre": {"name": "Gorgut the Ogre", "skin": "ogre"},
	"lich": {"name": "The Lich King", "skin": "lich"},
	"death_knight": {"name": "The Grave Warden", "skin": "death_knight"},
	"demon": {"name": "The Shadow Fiend", "skin": "demon"},
	"hell_knight": {"name": "The Hell Knight", "skin": "hell_knight"},
	"blood_demon": {"name": "The Blood Demon", "skin": "blood_demon"},
}


## The kinds a level-`level` rift can spawn.
static func pool(level: int) -> Array:
	var out: Array = []
	for id in KINDS:
		if int(KINDS[id]["min_level"]) <= level:
			out.append(id)
	return out


static func random_kind(level: int) -> String:
	var p := pool(level)
	return p[randi() % p.size()]


## A skin for one monster of `kind` (kinds with several looks pick one each).
static func skin_for(kind: String) -> String:
	var k: Dictionary = KINDS.get(kind, KINDS["zombie"])
	if k.has("skins"):
		var s: Array = k["skins"]
		return s[randi() % s.size()]
	return String(k.get("skin", ""))


static func random_boss() -> String:
	var ids := BOSSES.keys()
	return ids[randi() % ids.size()]
