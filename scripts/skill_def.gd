class_name SkillDef
extends Resource
## One skill a class can use. Index 0 in a class's skill list is the basic
## auto-attack; the rest are buttons the player taps.

enum Kind { CLEAVE, WHIRLWIND, LEAP_SLAM, BATTLE_CRY }

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.CLEAVE
@export var cooldown: float = 0.0
## Multiplier on the player's Damage stat.
@export var damage_mult: float = 1.0
@export var radius: float = 100.0
@export var arc_degrees: float = 360.0
@export var stun: float = 0.0
@export var duration: float = 0.0
@export var max_range: float = 0.0
@export var color: Color = Color.WHITE
