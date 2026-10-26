class_name ClassLibrary
extends RefCounted
## There are no classes: every character is an Adventurer, the same at the start; attributes, the
## passive tree, skill gems and gear make the build (Attributes.build_title names it). The
## Adventurer is the base: starting stats, any weapon, and Adrenaline's rules (Mana's are Player's).

const CLASS_IDS := ["adventurer"]


static func get_class_def(_id := "") -> ClassDef:
	return adventurer()


static func _skill(id: String, title: String, kind: SkillDef.Kind, cd: float, mult: float,
		radius: float, arc: float, col: Color, extra := {}) -> SkillDef:
	var s := SkillDef.new()
	s.id = id
	s.display_name = title
	s.kind = kind
	s.cooldown = cd
	s.damage_mult = mult
	s.radius = radius
	s.arc_degrees = arc
	s.color = col
	s.stun = extra.get("stun", 0.0)
	s.duration = extra.get("duration", 0.0)
	s.max_range = extra.get("max_range", 0.0)
	return s


## Everyone: any weapon (if its attribute requirements are met), one-handers in either hand.
static func adventurer() -> ClassDef:
	var c := ClassDef.new()
	c.id = "adventurer"
	c.display_name = "Adventurer"
	c.description = "Everyone starts the same. Where you put your attribute and passive points, which " + \
		"skill gems you socket and what you wield make you a warrior, an archer, a sorcerer, or anything in between."
	c.color = Color(0.85, 0.75, 0.5)
	c.base_stats = {
		"max_life": 140.0,
		"damage": 12.0,
		"attack_speed": 1.1,
		"move_speed": 220.0,
		"armor": 15.0,
		"crit_chance": 0.05,
		"life_regen": 1.5,
	}
	c.weapon_types = ["sword", "axe", "mace", "spear", "dagger", "staff", "bow", "crossbow", "shield"]
	c.dual_wield = true
	# Adrenaline (Strength skills): starts empty, built by their basic attacks, slowly drains away
	c.power_name = "Adrenaline"
	c.power_color = Color(1.0, 0.55, 0.1)
	c.power_max = 100.0
	c.power_start = 0.0
	c.power_decay = 2.5
	c.power_on_hit = 3.0
	c.power_per_life_lost = 50.0
	# 0: basic auto-attack, a wide melee arc that hits every enemy in front
	c.skills.append(_skill("cleave", "Cleave", SkillDef.Kind.CLEAVE, 0.0, 1.0, 105.0, 120.0,
			Color(0.9, 0.9, 0.95)))
	c.skills.append(_skill("whirlwind", "Whirl", SkillDef.Kind.WHIRLWIND, 4.0, 1.8, 135.0, 360.0,
			Color(0.9, 0.5, 0.2)))
	c.skills.append(_skill("leap_slam", "Leap", SkillDef.Kind.LEAP_SLAM, 7.0, 2.5, 115.0, 360.0,
			Color(0.75, 0.3, 0.3), {"stun": 1.2, "max_range": 280.0}))
	c.skills.append(_skill("battle_cry", "Cry", SkillDef.Kind.BATTLE_CRY, 15.0, 0.0, 0.0, 0.0,
			Color(0.9, 0.75, 0.2), {"duration": 6.0}))
	return c
