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
const WEAPON_NAMES := {"bow": "a bow", "melee": "a melee weapon"}

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
	var mult := damage_mult * (1.0 + 0.10 * (skill_rank - 1))  # +10% per rank
	for r in get_runes():
		mult += r.damage_mult_bonus * _lv(r) + GameState.support_damage_bonus(r.id)
	if not for_hireling:
		mult *= 1.0 + GameState.passive_value("skill_dmg:" + id)  # Legendary / Set powers for this skill
	return maxf(mult, 0.1)


func get_effective_cooldown(skill_rank: int = 1) -> float:
	if cooldown <= 0.0:
		return 0.0
	var rank_cd_reduction := (skill_rank - 1) * 0.02  # -2% per rank
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


## Support rules for one skill: at most one elemental conversion, and no two of the same support.
static func supports_valid(rune_ids: Array) -> bool:
	var seen := {}
	var conversions := 0
	for rid in rune_ids:
		var b := RuneDef.DB.base_of(String(rid))
		if seen.has(b):
			return false
		seen[b] = true
		var r := RuneDef.DB.get_rune(String(rid))
		if r != null and r.category == RuneDef.Category.TRANSMUTATION:
			conversions += 1
	return conversions <= 1
