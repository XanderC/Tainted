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
	# Chapter 3 of Act I: the grave warden of the Ashen Verge who drank the Taint, and holds half of the Warded Keystone
	"grave_warden": {
		"title": "Maddened Grave Warden", "hp": 2.0,
		"arena": 560.0, "intro": 1.6, "enrage": 150.0, "max_adds": 6,
		"lines": {"intro": "None disturb the dead. None.", "enrage": "Rest! REST!"},
		"moves": {
			"spade": {"kind": "slam", "windup": 0.7, "cd": 2.6, "range": [0.0, 190.0], "weight": 5, "r": 150.0, "dmg": 1.3, "recover": 0.5},
			"reap": {"kind": "sweep", "windup": 0.8, "cd": 3.4, "range": [0.0, 280.0], "weight": 4, "r": 270.0, "arc": 2.4, "dmg": 1.2, "recover": 0.5},
			"lurch": {"kind": "charge", "windup": 0.8, "cd": 5.0, "range": [200.0, 700.0], "weight": 3, "length": 520.0, "width": 90.0,
				"speed": 1000.0, "dmg": 1.4, "recover": 0.8},
			"raise": {"kind": "summon", "windup": 1.1, "cd": 12.0, "range": [0.0, 900.0], "weight": 2, "recover": 0.6},
		},
		"phases": [
			{"at": 1.0, "moves": ["spade", "reap", "lurch"]},
			{"at": 0.6, "say": "Up! Up, all of you!", "moves": ["spade", "reap", "lurch", "raise"],
				"adds": [{"kind": "skeleton", "n": 3}], "speed": 1.1},
			{"at": 0.3, "say": "The dead are mine to keep!", "moves": ["spade", "reap", "lurch", "raise"],
				"adds": [{"kind": "skeleton_warrior", "n": 2}], "speed": 1.2, "dmg": 1.15, "cd": 0.85},
		],
		"loot": {"rares": 2, "magics": 2, "orbs": {"alteration": 2, "augment": 2, "alchemy": 1}, "scrolls": 2},
	},
	# Chapter 3 of Act I: the golem a Bleed Rift animated, with the other half of the Warded Keystone lodged in its chest
	"rift_golem": {
		"title": "Bleed-Rift Golem", "hp": 2.6,
		"arena": 600.0, "intro": 2.0, "enrage": 170.0, "max_adds": 5,
		"lines": {"intro": "The rift bleeds. The stone obeys.", "enrage": "The tear widens."},
		"moves": {
			"pound": {"kind": "slam", "windup": 0.9, "cd": 3.0, "range": [0.0, 230.0], "weight": 5, "r": 200.0, "dmg": 1.5, "recover": 0.8},
			"quake": {"kind": "slam", "windup": 1.5, "cd": 9.0, "range": [0.0, 500.0], "weight": 2, "r": 340.0, "dmg": 1.7, "recover": 1.0},
			"fling": {"kind": "rain", "windup": 1.2, "cd": 7.0, "range": [0.0, 900.0], "weight": 3, "count": 6, "r": 110.0, "dmg": 1.3, "recover": 0.7},
			"tear": {"kind": "summon", "windup": 1.2, "cd": 14.0, "range": [0.0, 900.0], "weight": 2, "recover": 0.7},
		},
		"phases": [
			{"at": 1.0, "moves": ["pound", "fling", "quake"]},
			{"at": 0.65, "say": "", "moves": ["pound", "fling", "quake", "tear"], "adds": [{"kind": "bleed_fiend", "n": 2}], "speed": 1.1},
			{"at": 0.3, "say": "", "moves": ["pound", "fling", "quake", "tear"], "adds": [{"kind": "bleed_fiend", "n": 2}], "speed": 1.2, "dmg": 1.15, "cd": 0.85},
		],
		"loot": {"rares": 2, "magics": 3, "orbs": {"alteration": 2, "augment": 2, "alchemy": 2}, "scrolls": 2},
	},
	# Chapter 2 of Act I: the guardian of the Brood Cyst in the Weeping Hollow
	"matron_vhol": {
		"title": "Skittering Matron", "hp": 2.2,
		"arena": 560.0, "intro": 1.8, "enrage": 150.0, "max_adds": 6,
		"lines": {"intro": "The brood remembers the light.", "enrage": "Feed. Feed. FEED."},
		"moves": {
			"skitter": {"kind": "charge", "windup": 0.8, "cd": 4.0, "range": [160.0, 700.0], "weight": 4, "length": 560.0,
				"width": 80.0, "speed": 1250.0, "dmg": 1.4, "recover": 0.7},
			"lash": {"kind": "sweep", "windup": 0.7, "cd": 3.0, "range": [0.0, 240.0], "weight": 5, "r": 240.0, "arc": 2.2,
				"dmg": 1.2, "recover": 0.5},
			"spit": {"kind": "rain", "windup": 1.2, "cd": 7.0, "range": [0.0, 900.0], "weight": 3, "count": 5, "r": 105.0,
				"dmg": 1.3, "recover": 0.7},
			"brood": {"kind": "summon", "windup": 1.0, "cd": 12.0, "range": [0.0, 900.0], "weight": 2, "recover": 0.6},
		},
		"phases": [
			{"at": 1.0, "moves": ["skitter", "lash", "spit"]},
			{"at": 0.6, "say": "Little ones, eat!", "moves": ["skitter", "lash", "spit", "brood"],
				"adds": [{"kind": "cave_skitterer", "n": 3}], "speed": 1.1},
			{"at": 0.3, "say": "The cyst bleeds for me!", "moves": ["skitter", "lash", "spit", "brood"],
				"adds": [{"kind": "cave_skitterer", "n": 3}], "speed": 1.2, "dmg": 1.15, "cd": 0.8},
		],
		"loot": {"rares": 2, "magics": 2, "orbs": {"alteration": 2, "augment": 2, "alchemy": 1}, "scrolls": 2},
	},
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
