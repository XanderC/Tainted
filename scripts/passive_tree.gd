class_name PassiveTree
extends RefCounted
## The passive tree (Path of Exile style), one for everyone: there are no classes. From the start in
## the middle four branches lead off, one per attribute: Strength up (attack damage, Adrenaline),
## Dexterity right (speed, crits, bows), Vitality down (life, armour) and Energy left (spells,
## Mana). Between neighbours the paths cross: their connectors give both attributes, and out past
## the ring each diagonal has a hybrid cluster with its own keystone: Strength and Dexterity the
## Assassin's (up right), Dexterity and Vitality the Warden's, Vitality and Energy the Druid's, and
## Energy and Strength the Paladin's (up left).
## You start on "start" and may take any node linked to one you already have, 1 point each (one
## point per level gained).
##   small    - a modest stat (many give attribute points: "+8 Strength")
##   notable  - a strong combination, at the end of a cluster
##   keystone - a big build-defining effect with a drawback, at the far end of a branch
## Node stats use the keys read by Player / GameState.passive_value(): str, dex, vit, ene (attribute
## points), attack_inc, spell_inc, bow_inc, damage_inc, crit, attack_speed_inc, move_inc, life_flat,
## life_inc, armor_inc, regen, leech, thorns, execute, rampage, cost_red, power_max (Adrenaline),
## mana_max, mana_regen_inc, gem_level, no_crit, no_decay, mana_shield, blood_magic.
##
## Each node: {"id", "name", "kind", "pos": Vector2, "stats": {}, "links": [ids]}

static var _tree := {}


## The tree (`_class_id` is kept for older callers: there's one for everyone).
static func get_tree(_class_id := "") -> Dictionary:
	if _tree.is_empty():
		_tree = _build()
	return _tree


static func get_node(class_id: String, node_id: String) -> Dictionary:
	return get_tree(class_id).nodes.get(node_id, {})


## "+5% Attack Damage, +8 Strength" style text for a stats dictionary.
static func stat_text(stats: Dictionary) -> String:
	var parts: Array[String] = []
	var pct := func(v: float) -> String: return "%s%d%%" % ["+" if v >= 0.0 else "", int(round(v * 100.0))]
	for k in stats:
		var v: float = stats[k]
		match k:
			"str", "dex", "vit", "ene": parts.append("%+d %s" % [int(v), Attributes.NAMES[k]])
			"attack_inc": parts.append("%s Attack Damage" % pct.call(v))
			"spell_inc": parts.append("%s Spell Damage" % pct.call(v))
			"bow_inc": parts.append("%s Bow Damage" % pct.call(v))
			"damage_inc": parts.append("%s Damage" % pct.call(v))
			"crit": parts.append("%s Critical Chance" % pct.call(v))
			"attack_speed_inc": parts.append("%s Attack Speed" % pct.call(v))
			"move_inc": parts.append("%s Movement Speed" % pct.call(v))
			"life_flat": parts.append("%+d Max Life" % int(v))
			"life_inc": parts.append("%s Max Life" % pct.call(v))
			"armor_inc": parts.append("%s Armor" % pct.call(v))
			"regen": parts.append("+%.1f Life per second" % v)
			"leech": parts.append("%s Life Leech" % pct.call(v))
			"thorns": parts.append("Reflect %d damage when hit" % int(v))
			"execute": parts.append("%s Damage to enemies below 40%% Life" % pct.call(v))
			"rampage": parts.append("Slain enemies explode for %d%% of your Damage" % int(round(v * 100.0)))
			"cost_red": parts.append("%+d%% Skill Cost" % -int(round(v * 100.0)))
			"power_max": parts.append("%+d Maximum Adrenaline" % int(v))
			"mana_max": parts.append("%+d Maximum Mana" % int(v))
			"mana_regen_inc": parts.append("%s Mana Regeneration" % pct.call(v))
			"gem_level": parts.append("+%d to the level of all Skill Gems" % int(v))
			"no_crit": parts.append("Never deal Critical Strikes")
			"no_decay": parts.append("Adrenaline no longer fades")
			"mana_shield": parts.append("%d%% of damage taken comes off your Mana first" % int(round(v * 100.0)))
			"blood_magic": parts.append("Mana skills cost Life instead of Mana")
			_:  # per-skill item powers (UniqueItems): "skill_dmg:whirlwind" etc.
				var sk := SkillTree.get_skill(String(k).get_slice(":", 1)) if String(k).contains(":") else null
				var sname := sk.display_name if sk != null else String(k).get_slice(":", 1).capitalize()
				match String(k).get_slice(":", 0):
					"skill_dmg": parts.append("%s %s Damage" % [pct.call(v), sname])
					"skill_cdr": parts.append("-%d%% %s Cooldown" % [int(round(v * 100.0)), sname])
					"skill_dur": parts.append("%s %s Duration" % [pct.call(v), sname])
	return ", ".join(PackedStringArray(parts))


# ---------- building it ----------

static func _node(g: Dictionary, id: String, name: String, kind: String, pos: Vector2, stats: Dictionary) -> void:
	g.nodes[id] = {"id": id, "name": name, "kind": kind, "pos": pos, "stats": stats, "links": []}


static func _link(g: Dictionary, a: String, b: String) -> void:
	g.nodes[a].links.append(b)
	g.nodes[b].links.append(a)


## The four attribute branches, clockwise from the top (connectors join each to the next one).
const BRANCHES := [
	{"key": "str", "dir": Vector2(0, -1), "perp": Vector2(1, 0),
		"path": [["Strength", {"str": 8}], ["Might", {"attack_inc": 0.06}], ["Strength", {"str": 8}], ["Might", {"attack_inc": 0.06}]],
		"notable": ["Brutal Blows", {"attack_inc": 0.15, "execute": 0.10}],
		"tail": [["Strength", {"str": 10}], ["Fury", {"power_max": 8.0}]],
		"keystone": ["Resolute Technique", {"attack_inc": 0.40, "no_crit": 1.0}],
		"wheel": [["Savagery", {"attack_inc": 0.04}], ["Fury", {"power_max": 5.0}], ["Savagery", {"execute": 0.06}]],
		"wheel_notable": ["Bloodthirst", {"leech": 0.02, "power_max": 10.0}]},
	{"key": "dex", "dir": Vector2(1, 0), "perp": Vector2(0, 1),
		"path": [["Dexterity", {"dex": 8}], ["Quickness", {"attack_speed_inc": 0.03}], ["Dexterity", {"dex": 8}], ["Precision", {"crit": 0.01}]],
		"notable": ["Blade Dancer", {"attack_speed_inc": 0.10, "move_inc": 0.05}],
		"tail": [["Dexterity", {"dex": 10}], ["Marksman", {"bow_inc": 0.06}]],
		"keystone": ["Eagle Eye", {"bow_inc": 0.40, "crit": 0.03, "life_inc": -0.10}],
		"wheel": [["Fleet", {"move_inc": 0.03}], ["Marksman", {"bow_inc": 0.05}], ["Precision", {"crit": 0.015}]],
		"wheel_notable": ["Killing Instinct", {"crit": 0.04, "attack_inc": 0.06}]},
	{"key": "vit", "dir": Vector2(0, 1), "perp": Vector2(-1, 0),
		"path": [["Vitality", {"vit": 8}], ["Toughness", {"life_flat": 10.0}], ["Vitality", {"vit": 8}], ["Plating", {"armor_inc": 0.06}]],
		"notable": ["Juggernaut's Hide", {"armor_inc": 0.20, "life_inc": 0.06}],
		"tail": [["Vitality", {"vit": 10}], ["Fortitude", {"life_inc": 0.03}]],
		"keystone": ["Blood Magic", {"blood_magic": 1.0, "life_inc": 0.20}],
		"wheel": [["Mending", {"regen": 1.0}], ["Spikes", {"thorns": 8.0}], ["Mending", {"regen": 1.0}]],
		"wheel_notable": ["Retaliation", {"thorns": 30.0, "armor_inc": 0.08}]},
	{"key": "ene", "dir": Vector2(-1, 0), "perp": Vector2(0, -1),
		"path": [["Energy", {"ene": 8}], ["Sorcery", {"spell_inc": 0.06}], ["Energy", {"ene": 8}], ["Clarity", {"mana_regen_inc": 0.10}]],
		"notable": ["Arcane Potency", {"spell_inc": 0.15, "mana_max": 15.0}],
		"tail": [["Energy", {"ene": 10}], ["Sorcery", {"spell_inc": 0.06}]],
		"keystone": ["Eldritch Battery", {"mana_shield": 0.30, "mana_max": 30.0}],
		"wheel": [["Focus", {"cost_red": 0.03}], ["Clarity", {"mana_regen_inc": 0.10}], ["Focus", {"cost_red": 0.03}]],
		"wheel_notable": ["Wellspring", {"mana_max": 25.0, "mana_regen_inc": 0.20}]},
]
## The connectors from each branch's wheel to the next branch: both attributes, the hybrid's start.
const CONNECTOR_NAMES := {"str": "Duelist", "dex": "Ranger", "vit": "Warden", "ene": "Templar"}


## Four branches leave the start: along `dir` a path of small nodes, a notable, two more smalls and
## a keystone; a wheel of nodes (ending in a notable) loops off to the `perp` side and back into the
## path; two connector nodes join that wheel to the next branch, so the tree is a web.
static func _build() -> Dictionary:
	var g := {"nodes": {}, "start": "start"}
	_node(g, "start", "Wanderer", "start", Vector2.ZERO, {})
	for b in BRANCHES:
		var k: String = b.key
		var d: Vector2 = b.dir
		var pp: Vector2 = b.perp
		var prev := "start"
		for i in 4:
			var id := "%s_p%d" % [k, i]
			_node(g, id, b.path[i][0], "small", d * (90.0 + i * 75.0), b.path[i][1])
			_link(g, prev, id)
			prev = id
		_node(g, k + "_notable", b.notable[0], "notable", d * 400.0, b.notable[1])
		_link(g, prev, k + "_notable")
		prev = k + "_notable"
		for i in 2:
			var id := "%s_t%d" % [k, i]
			_node(g, id, b.tail[i][0], "small", d * (480.0 + i * 75.0), b.tail[i][1])
			_link(g, prev, id)
			prev = id
		_node(g, k + "_key", b.keystone[0], "keystone", d * 645.0, b.keystone[1])
		_link(g, prev, k + "_key")
		# the wheel, looping from path node 1 out to the side and back into path node 3
		var wpos := [d * 160.0 + pp * 55.0, d * 215.0 + pp * 95.0, d * 280.0 + pp * 115.0]
		var wprev := k + "_p1"
		for i in 3:
			var id := "%s_w%d" % [k, i]
			_node(g, id, b.wheel[i][0], "small", wpos[i], b.wheel[i][1])
			_link(g, wprev, id)
			wprev = id
		_node(g, k + "_wn", b.wheel_notable[0], "notable", d * 345.0 + pp * 135.0, b.wheel_notable[1])
		_link(g, wprev, k + "_wn")
		_link(g, k + "_wn", k + "_p3")
	# connectors: each wheel's notable to the next branch's third path node, giving both attributes
	for i in 4:
		var ka: String = BRANCHES[i].key
		var kb: String = BRANCHES[(i + 1) % 4].key
		var a: String = ka + "_wn"
		var b: String = kb + "_p2"
		var pa: Vector2 = g.nodes[a].pos
		var pb: Vector2 = g.nodes[b].pos
		var c1 := "%s_c0" % ka
		var c2 := "%s_c1" % ka
		var nm: String = CONNECTOR_NAMES[ka]
		_node(g, c1, nm, "small", pa.lerp(pb, 0.36), {ka: 5, kb: 3})
		_node(g, c2, nm, "small", pa.lerp(pb, 0.68), {ka: 3, kb: 5})
		_link(g, a, c1)
		_link(g, c1, c2)
		_link(g, c2, b)
	_build_outer(g)
	return g


# Outer tree themes, one per quarter (ring index / 12): right (Dexterity), down (Vitality),
# left (Energy), up (Strength).
const _THEMES := [
	[["Swiftness", {"attack_speed_inc": 0.025}], ["Dexterity", {"dex": 6}]],
	[["Vitality", {"vit": 6}], ["Bulwark", {"armor_inc": 0.05}]],
	[["Energy", {"ene": 6}], ["Sorcery", {"spell_inc": 0.04}]],
	[["Strength", {"str": 6}], ["Brawn", {"attack_inc": 0.04}]],
]
# Big outer clusters, every 45 degrees from the right going clockwise: two notables and a keystone.
# The diagonals are the hybrids.
const _CLUSTERS := [
	# right: Dexterity
	[["Flurry", {"attack_speed_inc": 0.08, "crit": 0.02}], ["Deadeye", {"bow_inc": 0.15, "crit": 0.02}],
		["Whirling Blades", {"attack_speed_inc": 0.25, "move_inc": 0.10, "armor_inc": -0.30}]],
	# down right: Dexterity and Vitality, the Warden
	[["Survivalist", {"move_inc": 0.06, "regen": 1.5}], ["Hunter's Hide", {"life_inc": 0.06, "bow_inc": 0.08}],
		["Warden's Vigil", {"life_inc": 0.12, "regen": 3.0, "move_inc": 0.08, "attack_inc": -0.10}]],
	# down: Vitality
	[["Iron Skin", {"armor_inc": 0.18, "life_flat": 15.0}], ["Barbed Plate", {"thorns": 25.0, "armor_inc": 0.08}],
		["Unbreakable", {"armor_inc": 0.60, "life_inc": 0.10, "move_inc": -0.10}]],
	# down left: Vitality and Energy, the Druid
	[["Spirit Bond", {"mana_max": 20.0, "life_flat": 20.0}], ["Wellspring of Life", {"mana_regen_inc": 0.20, "regen": 1.5}],
		["Nature's Balance", {"life_inc": 0.10, "mana_max": 40.0, "spell_inc": 0.10, "attack_inc": -0.15}]],
	# left: Energy
	[["Arcane Mastery", {"spell_inc": 0.12, "mana_max": 10.0}], ["Clarity of Mind", {"cost_red": 0.08, "mana_regen_inc": 0.15}],
		["Archmage", {"spell_inc": 0.40, "gem_level": 1.0, "life_inc": -0.15}]],
	# up left: Energy and Strength, the Paladin
	[["Holy Might", {"attack_inc": 0.08, "spell_inc": 0.08}], ["Consecrated Plate", {"armor_inc": 0.12, "mana_max": 15.0}],
		["Templar's Oath", {"attack_inc": 0.20, "spell_inc": 0.20, "armor_inc": 0.20, "attack_speed_inc": -0.10}]],
	# up: Strength
	[["Butcher", {"attack_inc": 0.12, "execute": 0.08}], ["Carnage", {"rampage": 0.20, "attack_inc": 0.05}],
		["Endless Rage", {"power_max": 30.0, "no_decay": 1.0}]],
	# up right: Strength and Dexterity, the Assassin
	[["Crimson Edge", {"crit": 0.03, "attack_inc": 0.08}], ["Shadow Strike", {"attack_speed_inc": 0.06, "move_inc": 0.05}],
		["Assassin's Creed", {"crit": 0.10, "attack_inc": 0.20, "life_inc": -0.12}]],
]
# Short spurs off the ring, 22.5 degrees either side of each branch, ending in a notable.
const _SPURS := [
	["Hamstring", {"move_inc": 0.06, "attack_speed_inc": 0.04}], ["Stone Skin", {"armor_inc": 0.15, "regen": 1.0}],
	["Spirit Ward", {"life_flat": 15.0, "mana_max": 15.0}], ["Mana Tide", {"mana_max": 20.0, "mana_regen_inc": 0.10}],
	["Battle Mage", {"spell_inc": 0.06, "armor_inc": 0.06}], ["Overpower", {"attack_inc": 0.10, "armor_inc": 0.05}],
	["Vampiric Strikes", {"leech": 0.02, "attack_inc": 0.05}], ["Deadly Precision", {"crit": 0.05}],
]
const RING_N := 48
const RING_R := 900.0


static func _ring_angle(i: int) -> float:
	return TAU * i / RING_N


static func _theme_small(ring_i: int, n: int) -> Array:
	var theme: Array = _THEMES[int(round(float(posmod(ring_i, RING_N)) / 12.0)) % 4]
	return theme[n % 2]


## A chain of small nodes from node `a` to node `b`, roughly `step` apart.
static func _chain(g: Dictionary, prefix: String, a: String, b: String, ring_i: int, step: float = 125.0) -> void:
	var pa: Vector2 = g.nodes[a].pos
	var pb: Vector2 = g.nodes[b].pos
	var n := maxi(int(round(pa.distance_to(pb) / step)) - 1, 0)
	var prev := a
	for i in n:
		var id := "%s%d" % [prefix, i]
		var sm := _theme_small(ring_i, i)
		_node(g, id, sm[0], "small", pa.lerp(pb, float(i + 1) / (n + 1)), sm[1])
		_link(g, prev, id)
		prev = id
	_link(g, prev, b)


## The outer tree: a ring of travel nodes around the core, joined to it by 8 spokes; 8 big clusters
## outside the ring (each leading on to a keystone), and 8 short spurs ending in notables.
static func _build_outer(g: Dictionary) -> void:
	for i in RING_N:
		var sm := _theme_small(i, i)
		_node(g, "ring%d" % i, sm[0], "small", Vector2.from_angle(_ring_angle(i)) * RING_R, sm[1])
	for i in RING_N:
		_link(g, "ring%d" % i, "ring%d" % ((i + 1) % RING_N))
	# spokes: from each wheel notable and each connector's outer node, straight out to the ring
	for b in BRANCHES:
		var k: String = b.key
		for from in [k + "_wn", k + "_c1"]:
			var p: Vector2 = g.nodes[from].pos
			var ri := posmod(int(round(p.angle() / TAU * RING_N)), RING_N)
			_chain(g, from + "_s", from, "ring%d" % ri, ri, 130.0)
	# clusters
	for c in 8:
		var ri := c * 6
		var dir := Vector2.from_angle(_ring_angle(ri))
		var centre := dir * 1200.0
		var key := "cl%d" % c
		var info: Array = _CLUSTERS[c]
		for j in 10:
			var pos := centre + Vector2.from_angle(dir.angle() + PI + j * TAU / 10.0) * 140.0
			var id := "%s_%d" % [key, j]
			if j == 3 or j == 7:
				var nt: Array = info[0 if j == 3 else 1]
				_node(g, id, nt[0], "notable", pos, nt[1])
			else:
				var sm := _theme_small(ri + (2 if j < 5 else -2), j)
				_node(g, id, sm[0], "small", pos, sm[1])
			if j > 0:
				_link(g, "%s_%d" % [key, j - 1], id)
		_link(g, key + "_9", key + "_0")
		_link(g, "ring%d" % ri, key + "_0")
		var ks: Array = info[2]
		_node(g, key + "_key", ks[0], "keystone", dir * 1720.0, ks[1])
		_chain(g, key + "_k", key + "_5", key + "_key", ri, 100.0)
	# spurs
	for s in 8:
		var ri := 3 + s * 6
		var dir := Vector2.from_angle(_ring_angle(ri))
		var key := "sp%d" % s
		var nt: Array = _SPURS[s]
		_node(g, key + "_n", nt[0], "notable", dir * 1380.0, nt[1])
		_chain(g, key + "_", "ring%d" % ri, key + "_n", ri, 100.0)
