class_name PassiveTree
extends RefCounted
## Path of Exile style passive trees, one per class (instead of one huge shared tree).
## A tree is a graph of nodes: you start on the class's "start" node and may take any node linked
## to one you already have, 1 point each (one point per level gained).
##   small    - a modest stat
##   notable  - a strong combination, at the end of a cluster
##   keystone - a big build-defining effect with a drawback, at the far end of a branch
## Node stats use the keys read by Player / GameState.passive_value(): damage_inc, crit,
## attack_speed_inc, move_inc, life_flat, life_inc, armor_inc, regen, leech, thorns, execute,
## rampage, cost_red, power_max, gem_level, no_crit, no_decay.
##
## Each node: {"id", "name", "kind", "pos": Vector2, "stats": {}, "links": [ids]}

static var _trees := {}


static func get_tree(class_id: String) -> Dictionary:
	if not _trees.has(class_id):
		match class_id:
			_: _trees[class_id] = _build_warrior()
	return _trees[class_id]


static func get_node(class_id: String, node_id: String) -> Dictionary:
	return get_tree(class_id).nodes.get(node_id, {})


## "+5% Damage, +10 Max Life" style text for a stats dictionary.
static func stat_text(stats: Dictionary) -> String:
	var parts: Array[String] = []
	var pct := func(v: float) -> String: return "%s%d%%" % ["+" if v >= 0.0 else "", int(round(v * 100.0))]
	for k in stats:
		var v: float = stats[k]
		match k:
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
			"gem_level": parts.append("+%d to the level of all Skill Gems" % int(v))
			"no_crit": parts.append("Never deal Critical Strikes")
			"no_decay": parts.append("Adrenaline no longer fades")
			_:  # per-skill item powers (UniqueItems): "skill_dmg:whirlwind" etc.
				var sk := SkillTree.get_skill(String(k).get_slice(":", 1)) if String(k).contains(":") else null
				var sname := sk.display_name if sk != null else String(k).get_slice(":", 1).capitalize()
				match String(k).get_slice(":", 0):
					"skill_dmg": parts.append("%s %s Damage" % [pct.call(v), sname])
					"skill_cdr": parts.append("-%d%% %s Cooldown" % [int(round(v * 100.0)), sname])
					"skill_dur": parts.append("%s %s Duration" % [pct.call(v), sname])
	return ", ".join(PackedStringArray(parts))


# ---------- the Warrior tree ----------

static func _node(g: Dictionary, id: String, name: String, kind: String, pos: Vector2, stats: Dictionary) -> void:
	g.nodes[id] = {"id": id, "name": name, "kind": kind, "pos": pos, "stats": stats, "links": []}


static func _link(g: Dictionary, a: String, b: String) -> void:
	g.nodes[a].links.append(b)
	g.nodes[b].links.append(a)


## Four branches leave the start: along `dir` a path of small nodes, a notable, two more smalls and
## a keystone; a wheel of nodes (ending in a notable) loops off to the `perp` side and back into the
## path; two connector nodes join that wheel to the next branch, so the tree is a web.
static func _build_warrior() -> Dictionary:
	var g := {"nodes": {}, "start": "start"}
	_node(g, "start", "Warrior", "start", Vector2.ZERO, {})
	var branches := [
		{"key": "might", "dir": Vector2(0, -1), "perp": Vector2(1, 0),
			"path": [["Strength", {"damage_inc": 0.05}], ["Strength", {"damage_inc": 0.05}], ["Strength", {"damage_inc": 0.05}], ["Strength", {"damage_inc": 0.05}]],
			"notable": ["Brutal Blows", {"damage_inc": 0.15, "execute": 0.10}],
			"tail": [["Might", {"damage_inc": 0.06}], ["Might", {"damage_inc": 0.06}]],
			"keystone": ["Resolute Technique", {"damage_inc": 0.40, "no_crit": 1.0}],
			"wheel": [["Savagery", {"damage_inc": 0.04}], ["Savagery", {"execute": 0.06}], ["Savagery", {"damage_inc": 0.04}]],
			"wheel_notable": ["Rampage", {"rampage": 0.30, "damage_inc": 0.05}]},
		{"key": "fury", "dir": Vector2(1, 0), "perp": Vector2(0, 1),
			"path": [["Quickness", {"attack_speed_inc": 0.03}], ["Quickness", {"attack_speed_inc": 0.03}], ["Quickness", {"attack_speed_inc": 0.03}], ["Quickness", {"attack_speed_inc": 0.03}]],
			"notable": ["Blade Dancer", {"attack_speed_inc": 0.10, "move_inc": 0.05}],
			"tail": [["Fervor", {"crit": 0.015}], ["Fervor", {"crit": 0.015}]],
			"keystone": ["Berserker's Fury", {"attack_speed_inc": 0.30, "life_inc": -0.15}],
			"wheel": [["Precision", {"crit": 0.02}], ["Precision", {"crit": 0.02}], ["Fleet", {"move_inc": 0.03}]],
			"wheel_notable": ["Killing Instinct", {"crit": 0.05, "damage_inc": 0.06}]},
		{"key": "rage", "dir": Vector2(0, 1), "perp": Vector2(-1, 0),
			"path": [["Rage", {"power_max": 5.0}], ["Focus", {"cost_red": 0.03}], ["Rage", {"power_max": 5.0}], ["Focus", {"cost_red": 0.03}]],
			"notable": ["Battle Trance", {"power_max": 15.0, "cost_red": 0.06}],
			"tail": [["Bloodthirst", {"leech": 0.01}], ["Bloodthirst", {"leech": 0.01}]],
			"keystone": ["Endless Rage", {"power_max": 30.0, "no_decay": 1.0}],
			"wheel": [["Vigour", {"leech": 0.01}], ["Vigour", {"regen": 0.8}], ["Vigour", {"leech": 0.01}]],
			"wheel_notable": ["Warlord", {"gem_level": 1.0, "cost_red": 0.04}]},
		{"key": "bastion", "dir": Vector2(-1, 0), "perp": Vector2(0, -1),
			"path": [["Toughness", {"life_flat": 10.0}], ["Plating", {"armor_inc": 0.06}], ["Toughness", {"life_flat": 10.0}], ["Plating", {"armor_inc": 0.06}]],
			"notable": ["Juggernaut's Hide", {"armor_inc": 0.20, "life_inc": 0.06}],
			"tail": [["Fortitude", {"life_inc": 0.03}], ["Fortitude", {"life_inc": 0.03}]],
			"keystone": ["Unbreakable", {"armor_inc": 0.60, "move_inc": -0.10}],
			"wheel": [["Mending", {"regen": 1.0}], ["Spikes", {"thorns": 8.0}], ["Mending", {"regen": 1.0}]],
			"wheel_notable": ["Retaliation", {"thorns": 30.0, "armor_inc": 0.08}]},
	]
	for b in branches:
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
		# (kept inside the connector line that runs from the wheel notable to the next branch)
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
	# connectors: each wheel's notable to the next branch's third path node
	var keys := ["might", "fury", "rage", "bastion"]
	for i in 4:
		var a: String = keys[i] + "_wn"
		var b: String = keys[(i + 1) % 4] + "_p2"
		var pa: Vector2 = g.nodes[a].pos
		var pb: Vector2 = g.nodes[b].pos
		var c1 := "%s_c0" % keys[i]
		var c2 := "%s_c1" % keys[i]
		_node(g, c1, "Discipline", "small", pa.lerp(pb, 0.36), {"life_flat": 8.0})
		_node(g, c2, "Discipline", "small", pa.lerp(pb, 0.68), {"damage_inc": 0.03})
		_link(g, a, c1)
		_link(g, c1, c2)
		_link(g, c2, b)
	_build_warrior_outer(g)
	return g


# Outer tree themes, one per quarter (ring index / 12): right, down, left, up.
const _THEMES := [
	[["Swiftness", {"attack_speed_inc": 0.025}], ["Keen Edge", {"crit": 0.01}]],   # fury
	[["Wrath", {"power_max": 4.0}], ["Hunger", {"leech": 0.01}]],                   # rage
	[["Bulwark", {"armor_inc": 0.05}], ["Vitality", {"life_flat": 8.0}]],           # bastion
	[["Brawn", {"damage_inc": 0.04}], ["Ferocity", {"execute": 0.05}]],             # might
]
# Big outer clusters, every 45 degrees from the right going clockwise: two notables and a keystone.
const _CLUSTERS := [
	[["Flurry", {"attack_speed_inc": 0.08, "crit": 0.02}], ["Duelist's Poise", {"crit": 0.04, "move_inc": 0.05}],
		["Whirling Blades", {"attack_speed_inc": 0.25, "move_inc": 0.10, "armor_inc": -0.30}]],
	[["Bloodlust", {"attack_speed_inc": 0.06, "leech": 0.02}], ["Adrenal Surge", {"power_max": 10.0, "crit": 0.03}],
		["Frenzied Soul", {"attack_speed_inc": 0.15, "damage_inc": 0.15, "cost_red": -0.20}]],
	[["Unending Hunger", {"leech": 0.03, "regen": 1.5}], ["Seething Fury", {"power_max": 15.0, "cost_red": 0.05}],
		["Blood Pact", {"leech": 0.05, "power_max": 20.0, "life_inc": -0.10}]],
	[["Stoic Mind", {"cost_red": 0.06, "armor_inc": 0.10}], ["Second Wind", {"regen": 2.0, "life_flat": 20.0}],
		["Eternal Warrior", {"gem_level": 1.0, "power_max": -20.0}]],
	[["Iron Skin", {"armor_inc": 0.18, "life_flat": 15.0}], ["Barbed Plate", {"thorns": 25.0, "armor_inc": 0.08}],
		["Iron Fortress", {"armor_inc": 0.80, "thorns": 40.0, "attack_speed_inc": -0.12}]],
	[["Crushing Weight", {"damage_inc": 0.10, "armor_inc": 0.10}], ["Titan's Grip", {"life_inc": 0.06, "damage_inc": 0.06}],
		["Avatar of Pain", {"thorns": 80.0, "damage_inc": 0.15, "armor_inc": -0.25}]],
	[["Butcher", {"damage_inc": 0.12, "execute": 0.08}], ["Carnage", {"rampage": 0.20, "damage_inc": 0.05}],
		["Executioner's Creed", {"execute": 0.50, "damage_inc": 0.10, "life_inc": -0.10}]],
	[["Crimson Edge", {"crit": 0.03, "damage_inc": 0.08}], ["Relentless", {"attack_speed_inc": 0.06, "damage_inc": 0.06}],
		["Crimson Dance", {"crit": 0.10, "damage_inc": 0.20, "life_inc": -0.12}]],
]
# Short spurs off the ring, 22.5 degrees either side of each branch, ending in a notable.
const _SPURS := [
	["Hamstring", {"move_inc": 0.06, "attack_speed_inc": 0.04}], ["Vampiric Strikes", {"leech": 0.02, "damage_inc": 0.05}],
	["Battle Hardened", {"power_max": 10.0, "life_flat": 15.0}], ["Stone Skin", {"armor_inc": 0.15, "regen": 1.0}],
	["Unyielding", {"life_inc": 0.08}], ["Overpower", {"damage_inc": 0.10, "armor_inc": 0.05}],
	["Bloodbath", {"rampage": 0.15, "execute": 0.05}], ["Deadly Precision", {"crit": 0.05}],
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
static func _build_warrior_outer(g: Dictionary) -> void:
	for i in RING_N:
		var sm := _theme_small(i, i)
		_node(g, "ring%d" % i, sm[0], "small", Vector2.from_angle(_ring_angle(i)) * RING_R, sm[1])
	for i in RING_N:
		_link(g, "ring%d" % i, "ring%d" % ((i + 1) % RING_N))
	# spokes: from each wheel notable and each connector's outer node, straight out to the ring
	for k in ["might", "fury", "rage", "bastion"]:
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
