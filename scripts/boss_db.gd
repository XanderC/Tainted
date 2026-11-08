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
	"raider_captain": {
		"title": "Raider Captain", "hp": 1.8,
		"arena": 560.0, "intro": 1.8, "enrage": 150.0, "max_adds": 5,
		"lines": {
			"intro": "You've come a long way to die in my camp.",
			"enrage": "No more games!",
		},
		"moves": {
			"volley": {"kind": "volley", "windup": 0.85, "cd": 3.4, "range": [180.0, 760.0], "weight": 3, "arrows": 5,
				"spread": 0.75, "length": 620.0, "dmg": 0.9, "recover": 0.5},
			"pin": {"kind": "pin", "windup": 1.05, "cd": 5.5, "range": [240.0, 820.0], "weight": 2, "length": 760.0,
				"width": 64.0, "dmg": 2.4, "recover": 0.6},
			"backstep": {"kind": "backstep", "windup": 0.15, "cd": 4.0, "range": [0.0, 210.0], "weight": 8, "dist": 380.0,
				"speed": 1100.0, "recover": 0.25},
			"rain": {"kind": "rain", "windup": 1.3, "cd": 8.0, "range": [0.0, 900.0], "weight": 3, "count": 5, "r": 100.0,
				"dmg": 1.5, "recover": 0.7},
		},
		"phases": [
			{"at": 1.0, "moves": ["volley", "pin", "backstep"]},
			{"at": 0.65, "say": "Archers! Cut them down!", "moves": ["volley", "pin", "backstep", "rain"],
				"adds": [{"kind": "bandit_archer", "n": 2}, {"kind": "goblin", "n": 2}], "speed": 1.1},
			{"at": 0.3, "say": "Burn it all down!", "moves": ["volley", "pin", "backstep", "rain"],
				"adds": [{"kind": "bandit_archer", "n": 2}], "speed": 1.2, "dmg": 1.15, "cd": 0.75},
		],
		"loot": {"rares": 2, "magics": 1, "orbs": {"alteration": 2, "transmute": 3, "augment": 1}, "scrolls": 2},
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
