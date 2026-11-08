class_name BossDB
extends RefCounted
## Boss fights: what each quest or act boss does (BossBrain runs it). A boss on a map ("boss" object, with
## an id) that has an entry here gets a brain, an arena, a health bar with a name card and its own
## rewards; one without keeps the plain tough monster with a ground slam.
##
## An entry:
##   title    - under its name on the bar ("Raider Captain")
##   hp       - times the life the map gives it (the fight has roars and adds in it, so more than a plain monster)
##   arena    - radius of the ring that seals round it when it wakes; it wakes at 80% of that
##   intro    - seconds it roars, untouchable, before it fights
##   enrage   - seconds into the fight after which it speeds up and hits harder, for good
##   max_adds - the most of its adds alive at once
##   moves    - id -> a move (see below)
##   phases   - from full health down: {at (share of its life it starts at), say, adds [{kind, n}],
##              moves (ids it can use), speed, dmg, cd (multipliers; cd < 1 is faster)}
##   lines    - what it says: "intro", "enrage"
##   loot     - {rares, magics, orbs {id: n}, scrolls}
## A move: kind, windup (seconds of warning), cd (seconds before it can use it again), range [min, max]
## to its foe, weight (how often it picks it), recover (seconds still after it), and by kind:
##   slam     r, dmg          a circle round it
##   sweep    r, arc, dmg     a cone in front of it
##   charge   length, width, speed, dmg    a dash along a line, then it stands a moment
##   volley   arrows, spread, length, dmg  a fan of arrows (a cone)
##   pin      length, width, dmg           one heavy arrow down a line
##   rain     count, r, dmg                circles of arrows landing on players and about
##   backstep dist, speed                  leaps away from its foe, no damage
##   summon   (the phase's adds, or `adds`)
## dmg is a share of the boss's own hit (Enemy.touch_damage). Everything but the damage is shown on the
## ground first (BossTelegraph), so a player can step out of it.

const BOSSES := {
	# Chapter 1 of Act I: the pack leader that has Scout Captain Dennis pinned in the hunting lodge
	"briar_alpha": {
		"title": "Tainted Briarwolf", "hp": 1.4,
		"arena": 480.0, "intro": 1.4, "enrage": 120.0, "max_adds": 4,
		"lines": {},
		"moves": {
			"lunge": {"kind": "charge", "windup": 0.7, "cd": 3.2, "range": [140.0, 620.0], "weight": 4, "length": 480.0,
				"width": 70.0, "speed": 1150.0, "dmg": 1.3, "recover": 0.6},
			"maul": {"kind": "slam", "windup": 0.6, "cd": 2.4, "range": [0.0, 170.0], "weight": 5, "r": 125.0, "dmg": 1.1,
				"recover": 0.5},
			"howl": {"kind": "summon", "windup": 0.9, "cd": 12.0, "range": [0.0, 900.0], "weight": 2, "recover": 0.6},
		},
		"phases": [
			{"at": 1.0, "moves": ["lunge", "maul"]},
			{"at": 0.5, "moves": ["lunge", "maul", "howl"], "adds": [{"kind": "briarwolf", "n": 2}], "speed": 1.15},
		],
		"loot": {"rares": 1, "magics": 1, "orbs": {"transmute": 2, "augment": 1}, "scrolls": 1},
	},
}

## Entries added at run time (tests): id -> entry
static var _extra := {}


static func register(id: String, entry: Dictionary) -> void:
	_extra[id] = entry


static func has(id: String) -> bool:
	return id != "" and (BOSSES.has(id) or _extra.has(id))


## The boss's entry, {} when it has none.
static func def(id: String) -> Dictionary:
	if _extra.has(id):
		return _extra[id]
	return BOSSES.get(id, {})


## Which phase a boss with `frac` of its life left is in (the last whose `at` is not above it).
static func phase_at(d: Dictionary, frac: float) -> int:
	var idx := 0
	var phases: Array = d.get("phases", [])
	for i in phases.size():
		if frac <= float(phases[i].get("at", 1.0)) + 0.0001:
			idx = i
	return idx
