class_name ClassDef
extends Resource
## A playable class: starting stats plus its skill list.

@export var id: String = ""
@export var display_name: String = ""
## One or two lines for the character creation screen.
@export var description: String = ""
@export var color: Color = Color.WHITE
@export var base_stats: Dictionary = {}
## Weapon / shield types this class can equip (ItemBase.weapon_type).
@export var weapon_types: Array[String] = []
## Can hold a one-handed weapon in the off hand.
@export var dual_wield: bool = false
## Skill resource (e.g. Adrenaline for the Warrior, Mana for casters).
@export var power_name: String = "Mana"
@export var power_color: Color = Color(0.25, 0.45, 1.0)
@export var power_max: float = 100.0
@export var power_start: float = 100.0
## Lost per second (Adrenaline fades when you stop fighting). Negative = regenerates.
@export var power_decay: float = -2.0
## Resource gained when hit: a flat amount per hit (at most every 0.5s) plus this much per 100% of
## max life lost (e.g. 50 -> losing 10% of your life gives +5). Warriors get angrier when hurt.
@export var power_on_hit: float = 0.0
@export var power_per_life_lost: float = 0.0
## Index 0 = basic auto-attack. Indexes 1+ = tappable skill buttons.
@export var skills: Array[SkillDef] = []
