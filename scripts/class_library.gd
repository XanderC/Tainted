class_name ClassLibrary
extends RefCounted
## All playable classes. Add a new static func here to add a class.


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


## Tanky melee bruiser: high life and armor, area attacks, self-buff.
static func warrior() -> ClassDef:
	var c := ClassDef.new()
	c.id = "warrior"
	c.display_name = "Warrior"
	c.color = Color(0.35, 0.5, 0.95)
	c.base_stats = {
		"max_life": 160.0,
		"damage": 12.0,
		"attack_speed": 1.1,
		"move_speed": 220.0,
		"armor": 20.0,
		"crit_chance": 0.05,
		"life_regen": 1.5,
	}
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
