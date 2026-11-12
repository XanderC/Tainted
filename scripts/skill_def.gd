class_name SkillDef
extends Resource
## An active skill. Linked support gems (RuneDef) mutate its damage type, geometry and utility;
## a support's level scales its effects and adds a little damage.
## Its gem's colour is its attribute (`attributes`, the first the main one): red Strength skills
## build and spend Adrenaline, green Dexterity and blue Energy skills spend Mana. Using it needs
## enough of each (SkillTree.gem_attr_req), and some need a weapon (`weapon`: a bow, or a melee one).

enum Kind {
	# Juggernaut
	CLEAVE,
	SHIELD_SLAM,
	EARTHQUAKE,
	IRON_SKIN,
	# Berserker
	WHIRLWIND,
	LEAP_SLAM,
	FRENZY,
	BATTLE_CRY,
	# Warlord
	SUNDERING_STRIKE,
	BLADE_VORTEX,
	BATTLE_STANDARD,
	CALL_ANCIENTS,
	# Bows (a player's Dexterity skills, and hireling archers): arrows rather than swings
	SHOT,
	POWER_SHOT,
	MULTISHOT,
	ARROW_RAIN,
	# Dexterity
	DASH,         ## dash through to a target, cutting everything along the way
	KNIFE_FAN,    ## knives thrown out all round
	# Energy: spells
	BOLT,         ## a bolt that bursts where it hits
	NOVA,         ## a burst all round you
	ARC,          ## lightning striking the nearest enemies in turn
	METEOR,       ## a delayed blast where the enemies are
	WARD,         ## a ward taking part of the damage you take
	HOLY_NOVA,    ## heals you and burns what's near
	# Hybrids
	SMITE,        ## a melee blow and a bolt of lightning on what it hits (Strength and Energy)
}

## What it needs in hand: "bow", "melee" (anything but a bow), or "" (any, or none: spells).
const WEAPON_NAMES := {"bow": "a bow or crossbow", "melee": "a melee weapon"}

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: Kind = Kind.CLEAVE
@export var cluster: String = "basic"  ## SkillTree.CLUSTERS id
@export var icon: String = "⚔"
@export var cooldown: float = 0.0
@export var damage_mult: float = 1.0
@export var radius: float = 100.0
@export var arc_degrees: float = 360.0
@export var stun: float = 0.0
@export var duration: float = 0.0
@export var max_range: float = 0.0
@export var color: Color = Color.WHITE
## Its gem's attributes ("str", "dex", "ene"), the main one first: Strength skills use Adrenaline,
## the others Mana.
@export var attributes: Array[String] = ["str"]
@export var weapon: String = ""
## A spell: scaled by Energy and spell damage rather than Strength and attack damage.
@export var is_spell: bool = false
## Its own element and ailment before any support changes them (spells: fire, cold, lightning).
@export var base_damage_type: RuneDef.DamageType = RuneDef.DamageType.PHYSICAL
@export var base_ailment: String = ""
## Resource spent per use (per tick for channelled skills like Whirlwind).
@export var resource_cost: float = 0.0
## Resource generated per use that hits something (+ a little per extra enemy hit).
@export var resource_gain: float = 0.0

## Support gems linked to this skill (rune ids), filled from its skill slot
@export var socketed_runes: Array[String] = []

@export var max_rank: int = 15
@export var is_passive: bool = false
## Only hirelings use it (an archer's Shot): never a gem you can find, buy or socket.
@export var hireling_only: bool = false
## This copy is a hireling's: the player's Legendary skill powers don't apply to it.
var for_hireling := false
@export var custom_stats_text: String = ""


func duplicate_skill() -> SkillDef:
	var s: SkillDef = duplicate()
	s.socketed_runes = socketed_runes.duplicate()
	s.attributes = attributes.duplicate()
	return s


## The main attribute: its gem's colour.
func main_attribute() -> String:
	return attributes[0] if not attributes.is_empty() else "str"


## Spends (or builds) Mana rather than Adrenaline.
func uses_mana() -> bool:
	return main_attribute() != "str"


func resource_name() -> String:
	return "Mana" if uses_mana() else "Adrenaline"


## The gem's colour: red, green or blue by its main attribute.
func gem_color() -> Color:
	return Attributes.GEM_COLORS.get(main_attribute(), Color.WHITE)


func get_rank_description(rank: int) -> String:
	if rank <= 0:
		return "[color=#888888]Not learned yet. Requires 1 Skill Point.[/color]\n\n" + description

	var txt := description + "\n"
	if not is_passive:
		var rcol := "60a5fa" if uses_mana() else "fb923c"
		if resource_gain > 0.0:
			txt += "\n[color=#e2d9c8]• Generates: [color=#%s]%d[/color] %s per hit[/color]" % [rcol, int(round(get_effective_gain())), resource_name()]
		elif resource_cost > 0.0:
			txt += "\n[color=#e2d9c8]• Cost: [color=#%s]%d[/color] %s%s[/color]" % [rcol,
				int(round(get_effective_cost())), resource_name(), " per second" if kind == Kind.WHIRLWIND and cooldown <= 0.0 else ""]
		else:
			txt += "\n[color=#e2d9c8]• Costs nothing[/color]"
		if weapon != "":
			txt += "\n[color=#e2d9c8]• Needs %s[/color]" % WEAPON_NAMES.get(weapon, weapon)
		var dmg_pct := int(round(get_effective_damage_mult(rank) * 100.0))
		var cd := get_effective_cooldown(rank)
		txt += "\n[color=#e2d9c8]• Damage: [color=#ffd700]%d%%[/color] base damage[/color]" % dmg_pct
		if cd > 0.0:
			txt += "\n[color=#e2d9c8]• Cooldown: [color=#60a5fa]%.1fs[/color][/color]" % cd
		if radius > 0.0:
			txt += "\n[color=#e2d9c8]• Area Radius: [color=#e2d9c8]%d px[/color][/color]" % int(radius)
		if stun > 0.0:
			txt += "\n[color=#e2d9c8]• Stun Duration: [color=#f59e0b]%.1fs[/color][/color]" % stun
		if duration > 0.0:
			txt += "\n[color=#e2d9c8]• Buff Duration: [color=#34d399]%.1fs[/color][/color]" % duration

	if not custom_stats_text.is_empty():
		txt += "\n[color=#a78bfa]• %s[/color]" % custom_stats_text

	return txt


func get_next_rank_description(rank: int) -> String:
	if rank >= max_rank:
		return "[color=#ffd700]Maximum skill rank achieved.[/color]"

	var next_r := rank + 1
	var txt := ""
	if not is_passive:
		var cur_dmg := int(round(get_effective_damage_mult(maxi(1, rank)) * 100.0))
		var nxt_dmg := int(round(get_effective_damage_mult(next_r) * 100.0))
		txt += "Deals [color=#ffd700]%d%%[/color] Damage ([color=#34d399]+%d%%[/color])" % [nxt_dmg, nxt_dmg - cur_dmg]
		if cooldown > 0.0:
			var cur_cd := get_effective_cooldown(maxi(1, rank))
			var nxt_cd := get_effective_cooldown(next_r)
			txt += "\nCooldown reduced to [color=#60a5fa]%.1fs[/color] ([color=#34d399]-%.1fs[/color])" % [nxt_cd, cur_cd - nxt_cd]
	return txt


# ---------- Rune mutation evaluations ----------

## The linked support gems.
func get_runes() -> Array[RuneDef]:
	var list: Array[RuneDef] = []
	for rid in socketed_runes:
		var r := RuneDef.DB.get_rune(rid)
		if r != null:
			list.append(r)
	return list


## How much a linked support's level boosts its effects (1.0 at level 1, see GameState.support_scale).
static func _lv(r: RuneDef) -> float:
	return GameState.support_scale(r.id)


func get_cost_mult() -> float:
	var m := 1.0
	for r in get_runes():
		m *= r.cost_mult
	return m


func get_gain_mult() -> float:
	var m := 1.0
	for r in get_runes():
		m *= 1.0 + (r.gain_mult - 1.0) * _lv(r)
	return m


func get_effective_cost() -> float:
	return resource_cost * get_cost_mult()


func get_effective_gain() -> float:
	return resource_gain * get_gain_mult()


## Resource restored / fraction of life healed when the skill is used (upgrades).
func get_on_use_gain() -> float:
	var g := 0.0
	for r in get_runes():
		g += r.on_use_gain * _lv(r)
	return g


func get_on_use_heal() -> float:
	var h := 0.0
	for r in get_runes():
		h += r.on_use_heal * _lv(r)
	return h


func get_effective_name() -> String:
	var prefix := ""
	for r in get_runes():
		if r.category == RuneDef.Category.TRANSMUTATION and not r.title_prefix.is_empty():
			prefix = r.title_prefix + " "
			break
	if prefix.is_empty():
		for r in get_runes():
			if not r.title_prefix.is_empty():
				prefix = r.title_prefix + " "
				break
	return prefix + display_name


func get_effective_damage_type() -> RuneDef.DamageType:
	for r in get_runes():
		if r.category == RuneDef.Category.TRANSMUTATION:
			return r.damage_type
	return base_damage_type


func get_effective_color() -> Color:
	for r in get_runes():
		if r.category == RuneDef.Category.TRANSMUTATION:
			return r.color
	return color


func get_effective_damage_mult(skill_rank: int = 1) -> float:
	skill_rank += get_level_bonus()
	var mult := damage_mult * (1.0 + 0.10 * (skill_rank - 1))  # +10% per rank
	for r in get_runes():
		mult += r.damage_mult_bonus * _lv(r) + GameState.support_damage_bonus(r.id)
	for r in get_runes():
		if r.more_damage != 0.0:
			mult *= 1.0 + (r.more_damage * _lv(r) if r.more_damage > 0.0 else r.more_damage)
	if not for_hireling:
		mult *= 1.0 + GameState.passive_value("skill_dmg:" + id)  # Legendary / Set powers for this skill
	return maxf(mult, 0.1)


func get_effective_cooldown(skill_rank: int = 1) -> float:
	if cooldown <= 0.0:
		return 0.0
	var rank_cd_reduction := (skill_rank + get_level_bonus() - 1) * 0.02  # -2% per rank
	var cd := cooldown * (1.0 - rank_cd_reduction)
	for r in get_runes():
		cd *= maxf(1.0 - (1.0 - r.cooldown_mult) * _lv(r), 0.3) if r.cooldown_mult < 1.0 else r.cooldown_mult
	if not for_hireling:
		cd *= maxf(1.0 - GameState.passive_value("skill_cdr:" + id), 0.3)  # Legendary / Set powers
	return maxf(cd, 0.4)


func get_effective_radius() -> float:
	var rad := radius
	for r in get_runes():
		rad *= 1.0 + (r.radius_mult - 1.0) * _lv(r)
	return rad


func get_effective_arc() -> float:
	for r in get_runes():
		if r.force_360_arc:
			return 360.0
	return arc_degrees


func get_effective_ailment() -> String:
	for r in get_runes():
		if not r.ailment.is_empty():
			return r.ailment
	return base_ailment


func get_effective_leech() -> float:
	var leech := 0.0
	for r in get_runes():
		leech += r.life_leech * _lv(r)
	return leech


func has_echo() -> bool:
	for r in get_runes():
		if r.has_echo:
			return true
	return false


func get_execute_bonus() -> float:
	var bonus := 0.0
	for r in get_runes():
		bonus += r.execute_bonus * _lv(r)
	return bonus


## The "+N to level" a linked support gives (Fire Mastery and its kin).
func get_level_bonus() -> int:
	var n := 0
	for r in get_runes():
		n += r.level_bonus
	return n


## Projectiles a shot of this skill gains, and times a chaining skill chains again (Multishot, Chain).
func get_extra_projectiles() -> int:
	var n := 0
	for r in get_runes():
		n += r.extra_projectiles
	return n


func get_extra_chains() -> int:
	var n := 0
	for r in get_runes():
		n += r.extra_chains
	return n


## Enemies a projectile of this skill passes through (Pierce; 99 = all) and the damage each pierce takes off.
func get_pierce_count() -> int:
	var n := 0
	for r in get_runes():
		n = maxi(n, r.pierce)
	return n


func get_pierce_less() -> float:
	var f := 0.0
	for r in get_runes():
		f = maxf(f, r.pierce_less)
	return f


## Projectiles a hit splits into (Fork), and the damage the forks lose.
func get_forks() -> int:
	var n := 0
	for r in get_runes():
		n = maxi(n, r.forks)
	return n


func get_fork_less() -> float:
	var f := 0.0
	for r in get_runes():
		f = maxf(f, r.fork_less)
	return f


## The resistance (0 to 1; 1 or more = all of it) this skill's hits penetrate of element `dtype`.
func get_penetration(dtype: int) -> float:
	var p := 0.0
	for r in get_runes():
		if r.penetration > 0.0 and r.pen_type == dtype:
			p = maxf(p, r.penetration)
	return p


## Whether a hit of element `dtype` that lands its ailment (or, for cold, a critical hit) exposes the enemy.
func exposes(dtype: int) -> bool:
	for r in get_runes():
		if r.expose_type >= 0 and r.expose_type == dtype:
			return true
	return false


## How much faster (above 1) or slower (below) the skill is used with its supports (Rapid Attacks, Multishot's penalty).
func get_speed_mult() -> float:
	var m := 1.0
	for r in get_runes():
		if r.speed_bonus != 0.0:
			m *= 1.0 + (r.speed_bonus * _lv(r) if r.speed_bonus > 0.0 else r.speed_bonus)
	return maxf(m, 0.3)


## Controlled Destruction: no critical hits.
func cannot_crit() -> bool:
	for r in get_runes():
		if r.no_crit:
			return true
	return false


## What this skill is, for the supports that only go on some skills: "spell" or "attack", "hit" (it deals damage),
## "projectile", "chaining", "area", "melee", and its element ("physical", "fire", "cold", "lightning", "chaos").
## `rune_ids`: the supports it is linked with, one of which may convert the element.
func skill_tags(rune_ids: Array = []) -> Array[String]:
	var tags: Array[String] = []
	var hits := damage_mult > 0.0
	if hits:
		tags.append("hit")
		tags.append("spell" if is_spell else "attack")
	elif is_spell:
		tags.append("spell")
	if kind in [Kind.SHOT, Kind.POWER_SHOT, Kind.MULTISHOT, Kind.BOLT]:
		tags.append("projectile")
	if kind == Kind.ARC and cluster != "ultimate":
		tags.append("chaining")
	if radius > 0.0:
		tags.append("area")
	if weapon == "melee":
		tags.append("melee")
	var dtype := base_damage_type
	for rid in rune_ids:
		var r := RuneDef.DB.get_rune(String(rid))
		if r != null and r.category == RuneDef.Category.TRANSMUTATION:
			dtype = r.damage_type
	tags.append(["physical", "cold", "fire", "lightning", "chaos"][dtype])
	return tags


## "" if these supports can be linked to `skill` (null: any skill) together, else why not: no two of one support or of
## one family (Multishot I and II), at most one elemental conversion, at most one meta support, and each support's own
## restriction (Chain needs a chaining skill, Fire Mastery a Fire one).
static func supports_block_reason(rune_ids: Array, skill: SkillDef = null) -> String:
	var seen := {}
	var conversions := 0
	var metas := 0
	for rid in rune_ids:
		var b := RuneDef.DB.base_of(String(rid))
		var r := RuneDef.DB.get_rune(String(rid))
		var key := b if r == null or r.family.is_empty() else r.family
		if seen.has(key):
			return "no doubles, and one of each family"
		seen[key] = true
		if r != null and r.category == RuneDef.Category.TRANSMUTATION:
			conversions += 1
		elif r != null and r.category == RuneDef.Category.META:
			metas += 1
	if conversions > 1:
		return "one elemental support per skill"
	if metas > 1:
		return "one meta support per skill"
	if skill != null:
		var tags := skill.skill_tags(rune_ids)
		for rid in rune_ids:
			var r := RuneDef.DB.get_rune(String(rid))
			if r == null:
				continue
			for need in r.needs:
				if not tags.has(String(need)):
					return "%s needs a %s skill" % [r.display_name, need]
	return ""


static func supports_valid(rune_ids: Array, skill: SkillDef = null) -> bool:
	return supports_block_reason(rune_ids, skill) == ""


## Whether any of the supports is one a hireling cannot have: a meta support, or one whose effect is in the player's own
## casting (Multishot, Chain, speed).
static func supports_not_for_hirelings(rune_ids: Array) -> bool:
	for rid in rune_ids:
		var r := RuneDef.DB.get_rune(String(rid))
		if r != null and (r.category == RuneDef.Category.META or r.player_only):
			return true
	return false


## Whether any of the supports is a meta support (those fire the player's own skills: a hireling cannot link them).
static func supports_have_meta(rune_ids: Array) -> bool:
	for rid in rune_ids:
		var r := RuneDef.DB.get_rune(String(rid))
		if r != null and r.category == RuneDef.Category.META:
			return true
	return false
