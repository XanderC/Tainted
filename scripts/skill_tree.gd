class_name SkillTree
extends RefCounted
## Skill gems (Path of Exile style): you socket them into skill slots and link support gems to them.
## A gem levels up as you fight (+10% power per level). Its cluster sets the character level needed
## to use it (GEM_LEVEL_REQ), how much of its attribute it needs (GEM_ATTR_REQ) and its merchant
## price. Its colour is its attribute: red Strength (melee, Adrenaline), green Dexterity (bows,
## daggers, speed: Mana), blue Energy (spells: Mana); a few are two colours. Passives live in
## PassiveTree.

const ACTIVE_MAX_RANK := 15

const GEM_MAX_LEVEL := 20
## Character level needed to use a skill gem, and its merchant price, by cluster.
const GEM_LEVEL_REQ := {"basic": 1, "core": 3, "defensive": 5, "brawling": 8, "mastery": 12, "ultimate": 18}
## The attribute a gem needs, by cluster (everyone starts with 15 of each: the basic gems of every
## colour work from the start).
const GEM_ATTR_REQ := {"basic": 10, "core": 18, "defensive": 24, "brawling": 32, "mastery": 42, "ultimate": 56}
const GEM_PRICE := {"basic": {"transmute": 1}, "core": {"alteration": 1}, "defensive": {"alteration": 3},
	"brawling": {"alchemy": 1}, "mastery": {"alchemy": 2}, "ultimate": {"chaos": 1}}

static var _skills: Dictionary = {}
static var _mod_cache: Dictionary = {}


static func _make(id: String, name: String, cluster: String, icon_sym: String,
		kind: SkillDef.Kind, cd: float, mult: float, radius: float, arc: float,
		skill_col: Color, desc: String, is_pass: bool = false, extra := {}) -> SkillDef:
	var s := SkillDef.new()
	s.id = id
	s.display_name = name
	s.cluster = cluster
	s.is_passive = is_pass
	s.max_rank = ACTIVE_MAX_RANK
	s.icon = icon_sym
	s.kind = kind
	s.cooldown = cd
	s.damage_mult = mult
	s.radius = radius
	s.arc_degrees = arc
	s.color = skill_col
	s.description = desc
	s.stun = extra.get("stun", 0.0)
	s.duration = extra.get("duration", 0.0)
	s.max_range = extra.get("max_range", 0.0)
	s.custom_stats_text = extra.get("custom_text", "")
	s.attributes.assign(extra.get("attrs", ["str"]))
	s.weapon = String(extra.get("weapon", ""))
	s.is_spell = bool(extra.get("spell", false))
	s.base_damage_type = int(extra.get("dtype", RuneDef.DamageType.PHYSICAL)) as RuneDef.DamageType
	s.base_ailment = String(extra.get("ailment", ""))
	# Strength's basic skills build Adrenaline and the rest spend it; Dexterity and Energy skills
	# spend Mana, their basic ones nothing
	s.resource_gain = extra.get("gain", 0.0) if s.main_attribute() == "str" else 0.0
	if not is_pass and s.resource_gain <= 0.0 and not (cluster == "basic" and s.uses_mana()):
		s.resource_cost = extra.get("cost", 10.0)
	_skills[id] = s
	return s


const STR := ["str"]
const DEX := ["dex"]
const ENE := ["ene"]
const FIRE := RuneDef.DamageType.FIRE
const COLD := RuneDef.DamageType.COLD
const LIGHTNING := RuneDef.DamageType.LIGHTNING
const CHAOS := RuneDef.DamageType.CHAOS


static func init_skills() -> void:
	if not _skills.is_empty():
		return

	# ================ STRENGTH (red: melee, Adrenaline) ================
	# ---- basic (build Adrenaline) ----
	_make("cleave", "Cleave", "basic", "🪓", SkillDef.Kind.CLEAVE, 0.0, 1.05, 115.0, 125.0, Color(0.9, 0.85, 0.8),
		"Frontal sweeping slash hitting every enemy in a wide arc. Generates Adrenaline.",
		false, {"gain": 8.0, "weapon": "melee"})
	_make("sundering_strike", "Sundering Strike", "basic", "💥", SkillDef.Kind.SUNDERING_STRIKE, 0.0, 1.2, 105.0, 100.0, Color(0.95, 0.4, 0.35),
		"Overhead strike that sunders armor: enemies hit take +35% damage for 5 seconds. Generates Adrenaline.",
		false, {"duration": 5.0, "gain": 8.0, "weapon": "melee"})

	# ---- core ----
	_make("whirlwind", "Whirlwind", "core", "🌪", SkillDef.Kind.WHIRLWIND, 0.0, 0.85, 145.0, 360.0, Color(0.98, 0.55, 0.15),
		"Channel a cyclone of steel, cutting down every foe around you while moving freely.",
		false, {"sockets": 3, "cost": 20.0, "weapon": "melee"})
	_make("double_swing", "Double Swing", "core", "🪓", SkillDef.Kind.CLEAVE, 0.0, 1.35, 105.0, 120.0, Color(1.0, 0.5, 0.2),
		"Twin weapon slashes in immediate succession, shredding everything in front of you.",
		false, {"cost": 12.0, "weapon": "melee"})
	_make("rend", "Rend", "core", "🩸", SkillDef.Kind.SUNDERING_STRIKE, 4.0, 1.4, 110.0, 110.0, Color(0.9, 0.3, 0.3),
		"Lacerates all targets in a wide arc, leaving a bleeding wound.",
		false, {"duration": 5.0, "cost": 18.0, "custom_text": "Bleed: 180% Damage over 5s", "weapon": "melee"})

	# ---- defensive ----
	_make("ground_stomp", "Ground Stomp", "defensive", "🦶", SkillDef.Kind.EARTHQUAKE, 8.0, 1.3, 130.0, 360.0, Color(0.65, 0.75, 0.85),
		"Smash the ground, stunning every nearby enemy.", false, {"stun": 2.0, "cost": 15.0})
	_make("iron_skin", "Iron Skin", "defensive", "🗿", SkillDef.Kind.IRON_SKIN, 16.0, 0.0, 0.0, 0.0, Color(0.6, 0.75, 0.9),
		"Harden your flesh into stone: +100 Armor and 12 Life Regeneration per second.",
		false, {"duration": 7.0, "sockets": 3, "cost": 20.0})
	_make("threatening_shout", "Threatening Shout", "defensive", "🗣", SkillDef.Kind.BATTLE_CRY, 10.0, 0.0, 180.0, 360.0, Color(0.9, 0.4, 0.3),
		"A ferocious shout that weakens and slows nearby enemies.",
		false, {"duration": 12.0, "cost": 15.0, "custom_text": "Enemies deal 60% less damage"})
	_make("ignore_pain", "Ignore Pain", "defensive", "🧱", SkillDef.Kind.IRON_SKIN, 20.0, 0.0, 0.0, 0.0, Color(0.5, 0.7, 0.95),
		"Shrug off agony: greatly reduces incoming damage for a short time.",
		false, {"duration": 6.0, "sockets": 3, "cost": 25.0, "custom_text": "65% Damage Reduction"})

	# ---- brawling ----
	_make("leap", "Leap", "brawling", "🏃", SkillDef.Kind.LEAP_SLAM, 5.0, 0.5, 90.0, 360.0, Color(0.9, 0.45, 0.3),
		"Spring into the air toward the target area, jumping over enemies and obstacles.",
		false, {"max_range": 260.0, "cost": 15.0})
	_make("leap_slam", "Leap Slam", "brawling", "☄", SkillDef.Kind.LEAP_SLAM, 6.5, 2.7, 135.0, 360.0, Color(0.95, 0.3, 0.2),
		"Leap and crash down with catastrophic force, stunning every target in the impact.",
		false, {"stun": 1.5, "max_range": 320.0, "sockets": 3, "cost": 25.0, "weapon": "melee"})
	_make("shield_slam", "Shield Slam", "brawling", "🛡", SkillDef.Kind.SHIELD_SLAM, 4.5, 1.8, 100.0, 100.0, Color(0.4, 0.75, 1.0),
		"Bash forward with crushing force: heavy damage, a stun, and +35 Armor for 5 seconds.",
		false, {"stun": 1.5, "duration": 5.0, "cost": 15.0, "weapon": "melee"})
	_make("taunt", "Demoralizing Taunt", "brawling", "👁", SkillDef.Kind.BATTLE_CRY, 12.0, 0.0, 200.0, 360.0, Color(0.85, 0.3, 0.35),
		"Taunt every nearby monster, lowering their Armor.",
		false, {"duration": 8.0, "cost": 15.0, "custom_text": "-40% Enemy Armor"})

	# ---- mastery ----
	_make("earthquake", "Earthquake", "mastery", "🌋", SkillDef.Kind.EARTHQUAKE, 8.0, 2.9, 175.0, 360.0, Color(0.85, 0.55, 0.25),
		"Fracture the earth for massive area damage, slowing everything caught in it.",
		false, {"duration": 4.0, "sockets": 3, "cost": 30.0, "weapon": "melee"})
	_make("battle_cry", "Battle Cry", "mastery", "🦁", SkillDef.Kind.BATTLE_CRY, 14.0, 0.0, 220.0, 360.0, Color(1.0, 0.8, 0.2),
		"A thundering war cry: +30% More Damage and +15% Critical Chance.",
		false, {"duration": 7.0, "sockets": 3, "cost": 20.0})
	_make("war_cry", "War Cry", "mastery", "📣", SkillDef.Kind.BATTLE_CRY, 16.0, 0.0, 220.0, 360.0, Color(0.95, 0.65, 0.2),
		"A galvanizing cry that bolsters your fortitude.",
		false, {"duration": 10.0, "sockets": 3, "cost": 20.0, "custom_text": "+65 Armor, +8% Life Regen"})
	_make("battle_standard", "War Banner", "mastery", "🚩", SkillDef.Kind.BATTLE_STANDARD, 15.0, 1.3, 185.0, 360.0, Color(0.95, 0.75, 0.2),
		"Plant a War Banner that pulses damage every second and empowers you inside its zone.",
		false, {"duration": 8.5, "sockets": 3, "cost": 30.0})

	# ---- ultimate ----
	_make("berserk", "Wrath of the Berserker", "ultimate", "🔥", SkillDef.Kind.BATTLE_CRY, 45.0, 0.0, 0.0, 0.0, Color(1.0, 0.3, 0.1),
		"Enter an uncontrollable frenzy: +50% Damage, +40% Move Speed and +30% Attack Speed.",
		false, {"duration": 12.0, "sockets": 3, "cost": 50.0})
	_make("colossus", "Avatar of Stone", "ultimate", "🏔", SkillDef.Kind.IRON_SKIN, 45.0, 0.0, 0.0, 0.0, Color(0.4, 0.8, 1.0),
		"Become an unshakeable colossus: triple Armor and restore 25% Life.",
		false, {"duration": 10.0, "sockets": 3, "cost": 50.0, "custom_text": "+200% Armor"})
	_make("ancients", "Call of the Ancients", "ultimate", "👻", SkillDef.Kind.CALL_ANCIENTS, 50.0, 2.0, 200.0, 360.0, Color(0.95, 0.85, 0.5),
		"Summon three barbarian spirits to fight beside you: Talic whirls through enemies, Korlic leaps in and frenzies, Madawc splits the ground and stuns.",
		false, {"duration": 15.0, "sockets": 3, "cost": 50.0})

	# ================ DEXTERITY (green: bows, daggers, speed; Mana) ================
	_make("frenzy", "Frenzy", "basic", "⚔️", SkillDef.Kind.FRENZY, 0.0, 0.95, 95.0, 115.0, Color(1.0, 0.65, 0.2),
		"Rapid strikes. Each hit grants stacking Frenzy (+10% Attack Speed, +5% Move Speed, up to 5 stacks).",
		false, {"attrs": DEX, "weapon": "melee"})
	_make("quick_shot", "Quick Shot", "basic", "🏹", SkillDef.Kind.SHOT, 0.0, 1.0, 0.0, 0.0, Color(0.85, 0.80, 0.55),
		"Loose an arrow at the nearest enemy (or where you face).",
		false, {"attrs": DEX, "weapon": "bow", "max_range": 520.0})
	_make("power_shot", "Power Shot", "core", "➶", SkillDef.Kind.POWER_SHOT, 1.5, 2.4, 0.0, 0.0, Color(1.0, 0.7, 0.3),
		"A heavy arrow that pierces every enemy in its line.",
		false, {"attrs": DEX, "weapon": "bow", "cost": 8.0, "max_range": 600.0})
	_make("multishot", "Multishot", "core", "⇶", SkillDef.Kind.MULTISHOT, 0.0, 0.75, 0.0, 40.0, Color(0.75, 0.9, 0.6),
		"Five arrows in a fan.",
		false, {"attrs": DEX, "weapon": "bow", "cost": 10.0, "max_range": 520.0})
	_make("blade_vortex", "Blade Vortex", "core", "🌀", SkillDef.Kind.BLADE_VORTEX, 5.0, 1.85, 125.0, 360.0, Color(0.85, 0.45, 0.95),
		"Hurl spectral blades that spiral outward, slicing every enemy in their path.",
		false, {"attrs": DEX, "max_range": 280.0, "sockets": 3, "cost": 20.0})
	_make("fan_of_knives", "Fan of Knives", "defensive", "🗡", SkillDef.Kind.KNIFE_FAN, 3.0, 0.9, 0.0, 360.0, Color(0.55, 0.9, 0.45),
		"Throw a ring of poisoned knives all round you.",
		false, {"attrs": DEX, "cost": 14.0, "max_range": 340.0, "ailment": "poison", "dtype": CHAOS, "custom_text": "10 knives, each poisons what it hits"})
	_make("shadow_step", "Shadow Step", "brawling", "👤", SkillDef.Kind.DASH, 4.0, 1.8, 60.0, 0.0, Color(0.6, 0.5, 0.95),
		"Dash through the nearest enemy, cutting everything along the way.",
		false, {"attrs": DEX, "weapon": "melee", "cost": 12.0, "max_range": 300.0})
	_make("spear_throw", "Spear Throw", "brawling", "🔱", SkillDef.Kind.BLADE_VORTEX, 3.5, 2.1, 80.0, 360.0, Color(0.95, 0.7, 0.3),
		"Hurl a barbed spear that pierces through ranks of enemies.",
		false, {"attrs": DEX, "max_range": 350.0, "cost": 14.0})
	_make("arrow_rain", "Arrow Rain", "mastery", "☔", SkillDef.Kind.ARROW_RAIN, 6.0, 0.7, 130.0, 360.0, Color(0.7, 0.8, 1.0),
		"Three volleys rain down where the enemies stand, hitting all in the area.",
		false, {"attrs": DEX, "weapon": "bow", "cost": 20.0, "max_range": 500.0})
	_make("death_blossom", "Death Blossom", "ultimate", "🌸", SkillDef.Kind.KNIFE_FAN, 30.0, 1.1, 0.0, 360.0, Color(0.95, 0.45, 0.7),
		"Spin and throw three waves of poisoned knives in every direction.",
		false, {"attrs": DEX, "cost": 40.0, "max_range": 380.0, "ailment": "poison", "dtype": CHAOS, "custom_text": "3 waves of 10 knives"})

	# ================ ENERGY (blue: spells, Mana) ================
	_make("firebolt", "Firebolt", "basic", "🔥", SkillDef.Kind.BOLT, 0.0, 1.25, 55.0, 0.0, Color(1.0, 0.5, 0.2),
		"Hurl a bolt of fire that bursts where it hits, burning what's near.",
		false, {"attrs": ENE, "spell": true, "dtype": FIRE, "ailment": "burn", "max_range": 520.0})
	_make("frost_nova", "Frost Nova", "core", "❄", SkillDef.Kind.NOVA, 3.0, 1.5, 170.0, 360.0, Color(0.55, 0.85, 1.0),
		"A burst of ice all round you, chilling (and on a critical strike freezing) everything it hits.",
		false, {"attrs": ENE, "spell": true, "dtype": COLD, "ailment": "chill", "cost": 14.0})
	_make("arc", "Arc", "core", "⚡", SkillDef.Kind.ARC, 0.0, 1.1, 0.0, 0.0, Color(0.95, 0.95, 0.45),
		"Lightning leaps between the three nearest enemies, shocking them.",
		false, {"attrs": ENE, "spell": true, "dtype": LIGHTNING, "ailment": "shock", "cost": 9.0, "max_range": 420.0})
	_make("arcane_ward", "Arcane Ward", "defensive", "🔮", SkillDef.Kind.WARD, 18.0, 0.0, 0.0, 0.0, Color(0.6, 0.6, 1.0),
		"Wrap yourself in a ward that takes 40% of the damage you'd take.",
		false, {"attrs": ENE, "spell": true, "duration": 8.0, "cost": 20.0, "custom_text": "40% less damage taken"})
	_make("holy_nova", "Holy Nova", "brawling", "✨", SkillDef.Kind.HOLY_NOVA, 10.0, 1.4, 160.0, 360.0, Color(1.0, 0.9, 0.5),
		"A wave of holy light: heals you for 15% of your life and burns every enemy near.",
		false, {"attrs": ENE, "spell": true, "dtype": FIRE, "cost": 18.0, "custom_text": "Heals 15% of your life"})
	_make("meteor", "Meteor", "mastery", "☄", SkillDef.Kind.METEOR, 7.0, 4.0, 140.0, 360.0, Color(1.0, 0.45, 0.15),
		"Call down a meteor on the enemies near you: after a moment it crashes for massive fire damage.",
		false, {"attrs": ENE, "spell": true, "dtype": FIRE, "ailment": "burn", "cost": 26.0, "max_range": 450.0})
	_make("thunderstorm", "Thunderstorm", "ultimate", "🌩", SkillDef.Kind.ARC, 45.0, 1.6, 0.0, 0.0, Color(0.8, 0.85, 1.0),
		"A storm follows you: lightning strikes the nearest enemies again and again for four seconds.",
		false, {"attrs": ENE, "spell": true, "dtype": LIGHTNING, "ailment": "shock", "cost": 50.0, "max_range": 450.0, "duration": 4.0,
			"custom_text": "12 strikes"})

	# ================ HYBRIDS ================
	_make("viper_strike", "Viper Strike", "basic", "🐍", SkillDef.Kind.CLEAVE, 0.0, 0.9, 100.0, 70.0, Color(0.5, 0.85, 0.35),
		"A quick, poisoned stab (Dexterity and Strength: an assassin's opener).",
		false, {"attrs": ["dex", "str"], "weapon": "melee", "ailment": "poison"})
	_make("smite", "Smite", "core", "🔨", SkillDef.Kind.SMITE, 0.0, 1.25, 105.0, 100.0, Color(1.0, 0.92, 0.55),
		"A holy blow: lightning strikes whatever it hits (Strength and Energy: a paladin's strike).",
		false, {"attrs": ["str", "ene"], "weapon": "melee", "cost": 10.0, "custom_text": "Lightning: 60% of the hit on up to 3 enemies"})

	# ---------------- HIRELING ARCHERS (HirelingDB: never player gems) ----------------
	for s in [
		_make("hl_shot", "Shot", "basic", "🏹", SkillDef.Kind.SHOT, 0.0, 1.0, 0.0, 0.0, Color(0.85, 0.75, 0.55),
			"Loose an arrow at the nearest enemy.", false, {"max_range": 430.0, "gain": 1.0}),
		_make("hl_power_shot", "Power Shot", "core", "➶", SkillDef.Kind.POWER_SHOT, 4.0, 2.6, 0.0, 0.0, Color(1.0, 0.7, 0.3),
			"A heavy arrow that pierces every enemy in its line.", false, {"max_range": 520.0}),
		_make("hl_multishot", "Multishot", "core", "⇶", SkillDef.Kind.MULTISHOT, 5.0, 0.9, 0.0, 40.0, Color(0.75, 0.9, 0.6),
			"Five arrows in a fan.", false, {"max_range": 430.0}),
		_make("hl_rain", "Arrow Rain", "core", "☔", SkillDef.Kind.ARROW_RAIN, 7.0, 0.65, 120.0, 360.0, Color(0.7, 0.8, 1.0),
			"Three volleys rain down where enemies stand, hitting all in the area.", false, {"max_range": 450.0}),
	]:
		s.hireling_only = true
		s.resource_cost = 0.0


# ---------------- lookups ----------------

static func get_skill(id: String) -> SkillDef:
	init_skills()
	var template: SkillDef = _skills.get(id, null)
	if template != null:
		return template.duplicate_skill()
	return null


static func all_skills() -> Array[SkillDef]:
	init_skills()
	var list: Array[SkillDef] = []
	for id in _skills:
		list.append(_skills[id])
	return list


# ---------------- skill gems ----------------

static func gem_level_req(skill_id: String) -> int:
	init_skills()
	var s: SkillDef = _skills.get(skill_id)
	return int(GEM_LEVEL_REQ.get(s.cluster, 1)) if s != null else 1


## How much of its attributes a gem needs ({key: n}): by cluster for its main attribute, and 70% of
## that for a second one.
static func gem_attr_req(skill_id: String) -> Dictionary:
	init_skills()
	var s: SkillDef = _skills.get(skill_id)
	if s == null:
		return {}
	var n := int(GEM_ATTR_REQ.get(s.cluster, 10))
	var out := {}
	for i in s.attributes.size():
		out[s.attributes[i]] = n if i == 0 else int(round(n * 0.7))
	return out


## Merchant price in orbs.
static func gem_price(skill_id: String) -> Dictionary:
	init_skills()
	var s: SkillDef = _skills.get(skill_id)
	return GEM_PRICE.get(s.cluster, {"alteration": 2}) if s != null else {"alteration": 2}


## Every active skill (each one is a skill gem), in catalogue order. Hirelings' own skills aren't gems.
static func active_skills() -> Array[SkillDef]:
	init_skills()
	var list: Array[SkillDef] = []
	for id in _skills:
		if not _skills[id].is_passive and not _skills[id].hireling_only:
			list.append(_skills[id])
	return list
