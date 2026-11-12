class_name RuneDef
extends Resource
## A support gem (formerly "rune"): linked to a skill gem in a skill slot it mutates that skill's
## damage type, geometry or utility, like Path of Exile support gems. Every support makes the skill
## cost more (cost_mult). Data ids keep the old "rune_" prefix so saves keep working.
##
## Runes come in the same rarities as items (Normal / Magic / Rare). A rarer rune has stronger
## effects (RARITY_POWER) and a little extra skill damage (RARITY_DAMAGE). Rarity is part of the
## rune id: "rune_frost" is Normal, "rune_frost@1" Magic, "rune_frost@2" Rare, so the pouch and
## sockets (which store ids) need no other changes.

enum Category {
	TRANSMUTATION,  ## Converts damage type and applies elemental ailment (max 1 per skill)
	FORM,           ## Alters skill geometry / delivery (Nova, Reach, Echo)
	MODIFIER,       ## Stat enhancements and utility (Vampiric, Brutality, Alacrity, Execute)
	META            ## Fires another skill on an event (max 1 per skill): see `trigger`
}

enum DamageType {
	PHYSICAL,
	COLD,
	FIRE,
	LIGHTNING,
	CHAOS
}

@export var id: String = ""
@export var display_name: String = ""
@export var title_prefix: String = ""  ## e.g. "Glacial", "Molten", "Storm"
@export var category: Category = Category.TRANSMUTATION
@export var damage_type: DamageType = DamageType.PHYSICAL
@export var icon: String = "💎"
@export var color: Color = Color.WHITE
@export var description: String = ""

# Numeric and mechanical mutations
@export var damage_mult_bonus: float = 0.0   ## additive on skill damage multiplier (e.g. +0.3)
@export var cooldown_mult: float = 1.0       ## multiplier on cooldown (e.g. 0.7 = -30% cd)
@export var radius_mult: float = 1.0         ## multiplier on radius (e.g. 1.4 = +40% aoe)
@export var force_360_arc: bool = false      ## Nova effect: forces 360 degree arc
@export var life_leech: float = 0.0          ## fraction of damage returned as life (e.g. 0.15 = 15%)
@export var has_echo: bool = false           ## triggers secondary aftershock hit
@export var execute_bonus: float = 0.0       ## bonus crit chance against targets < 35% HP
@export var ailment: String = ""             ## "chill", "burn", "shock", "poison"
@export var ailment_chance: float = 1.0
@export var cost_mult: float = 1.0           ## resource cost multiplier (skill upgrades)
@export var gain_mult: float = 1.0           ## resource generated multiplier (skill upgrades)
@export var duration_mult: float = 1.0       ## buff / effect duration multiplier (skill upgrades)
@export var on_use_gain: float = 0.0         ## resource restored when the skill is used
@export var on_use_heal: float = 0.0         ## fraction of max life healed when the skill is used
@export var trigger: String = ""             ## META: "crit" (when you land a critical strike) or "hurt" (when you take damage)

# Path of Exile 2 supports (POE2_REFERENCE.md): a family of tiers, restricted by what the skill is, with a trade-off.
@export var family: String = ""              ## supports of one family do not go together (Multishot I and II)
@export var tier: int = 0                    ## 1, 2, 3 within the family (shown as I, II, III)
@export var needs: Array = []                ## skill tags the linked skill must all have (SkillDef.skill_tags); empty = any
@export var more_damage: float = 0.0         ## "N% more / less damage" (multiplies the skill's damage; positive grows with the level)
@export var speed_bonus: float = 0.0         ## "N% increased / less skill speed" (shortens the wait between casts)
@export var extra_projectiles: int = 0       ## projectiles added to each shot
@export var extra_chains: int = 0            ## times a chaining skill chains again
@export var no_crit: bool = false            ## the skill cannot deal critical hits
@export var level_bonus: int = 0             ## "+1 to level of supported skills" (the skill rank for its damage and cooldown)
@export var pierce: int = 0                  ## enemies a projectile passes through (99 = all of them)
@export var pierce_less: float = 0.0         ## each enemy it has pierced takes this fraction off its damage
@export var forks: int = 0                   ## projectiles a hit splits into (Fork)
@export var fork_less: float = 0.0           ## damage the forked projectiles lose
@export var penetration: float = 0.0         ## resistance the supported skill's hits penetrate (1.0 or more: they ignore it)
@export var pen_type: int = -1               ## ...of this element (DamageType); -1 = none
@export var expose_type: int = -1            ## the element whose ailment also exposes the enemy (DamageType); -1 = none
@export var player_only: bool = false        ## its effect is in the player's own casting, so a hireling cannot link it
@export var rarity: int = 0                  ## ItemInstance.Rarity
@export var base_id: String = ""             ## id without the rarity suffix

## Seconds a meta support waits between casts, by trigger.
const TRIGGER_COOLDOWN := {"crit": 0.4, "hurt": 1.0}
const RARITY_NAMES := ["", "Empowered", "Exalted"]
const RARITY_POWER := [1.0, 1.5, 2.0]         ## multiplies the rune's effects
const RARITY_DAMAGE := [0.0, 0.10, 0.20]      ## extra skill damage on top
## Drop odds [Magic, Rare]; each rift level above 1 adds RIFT_RARITY_BONUS to both.
const DROP_ODDS := [0.25, 0.05]
const BOSS_DROP_ODDS := [0.45, 0.15]
const RIFT_RARITY_BONUS := 0.03


func rarity_color() -> Color:
	return ItemInstance.RARITY_COLORS[rarity]


## BBCode lines with the rune's actual numbers (scaled by rarity, and by the gem's level `lvl`:
## +3% effects and +1% skill damage per level above 1, see GameState.support_scale).
func stat_lines(lvl: int = 1) -> String:
	var sc := 1.0 + 0.03 * (lvl - 1)
	var dmg := damage_mult_bonus * sc + 0.01 * (lvl - 1)
	var t := ""
	if rarity > 0:
		t += "[color=#%s]%s rune: effects ×%.1f[/color]\n" % [rarity_color().to_html(false),
			ItemInstance.Rarity.keys()[rarity].capitalize(), RARITY_POWER[rarity]]
	if lvl > 1:
		t += "[color=#60a5fa]Level %d: effects +%d%%[/color]\n" % [lvl, int(round((sc - 1.0) * 100))]
	if cost_mult != 1.0:
		t += "[color=#fb923c]• Linked skill costs ×%.2f[/color]\n" % cost_mult
	if dmg != 0.0:
		t += "[color=#66ff66]• Skill Damage: +%d%%[/color]\n" % int(round(dmg * 100))
	if cooldown_mult < 1.0:
		t += "[color=#66e6ff]• Cooldown Reduction: -%d%%[/color]\n" % int(round(minf((1.0 - cooldown_mult) * sc, 0.7) * 100))
	elif cooldown_mult > 1.0:
		t += "[color=#f87171]• Cooldown: +%d%%[/color]\n" % int(round((cooldown_mult - 1.0) * 100))
	if radius_mult > 1.0:
		t += "[color=#ffcc4d]• Area of Effect: +%d%% Radius[/color]\n" % int(round((radius_mult - 1.0) * sc * 100))
	if life_leech > 0.0:
		t += "[color=#ff4d66]• Life Leech: %d%% of Damage Dealt[/color]\n" % int(round(life_leech * sc * 100))
	if execute_bonus > 0.0:
		t += "[color=#ff9f43]• +%d%% Crit Chance vs enemies below 35%% Life[/color]\n" % int(round(execute_bonus * sc * 100))
	if extra_projectiles > 0:
		t += "[color=#ffcc4d]• Fires %d additional Projectiles[/color]\n" % extra_projectiles
	if extra_chains > 0:
		t += "[color=#ffcc4d]• Chains %d additional time%s[/color]\n" % [extra_chains, "" if extra_chains == 1 else "s"]
	if pierce > 0:
		t += "[color=#ffcc4d]• Projectiles pierce %s[/color]\n" % ("all enemies" if pierce >= 99 else "%d enem%s" % [pierce, "y" if pierce == 1 else "ies"])
	if pierce_less > 0.0:
		t += "[color=#f87171]• Projectiles deal %d%% less damage for each enemy they pierce[/color]\n" % int(round(pierce_less * 100))
	if forks > 0:
		t += "[color=#ffcc4d]• Projectiles fork into %d on hitting an enemy[/color]\n" % forks
		t += "[color=#f87171]• Forked projectiles deal %d%% less damage[/color]\n" % int(round(fork_less * 100))
	if penetration > 0.0:
		t += "[color=#ffcc4d]• Hits %s %s resistance[/color]\n" % ["ignore" if penetration >= 1.0 else "penetrate %d%%" % int(round(penetration * 100)),
			DamageType.keys()[pen_type].to_lower()]
	if expose_type >= 0:
		t += "[color=#ffcc4d]• %s that %s also expose the enemy: -20%% %s resistance for 8s[/color]\n" % [
			"Critical hits" if expose_type == DamageType.COLD else "Hits",
			{DamageType.FIRE: "ignite", DamageType.COLD: "freeze", DamageType.LIGHTNING: "shock"}.get(expose_type, "afflict"),
			DamageType.keys()[expose_type].to_lower()]
	if more_damage != 0.0:
		var md := more_damage * sc if more_damage > 0.0 else more_damage
		t += "[color=#%s]• %d%% %s Damage[/color]\n" % ["66ff66" if md > 0.0 else "f87171", int(round(absf(md) * 100)), "more" if md > 0.0 else "less"]
	if speed_bonus != 0.0:
		var sb := speed_bonus * sc if speed_bonus > 0.0 else speed_bonus
		t += "[color=#%s]• %d%% %s Skill Speed[/color]\n" % ["66e6ff" if sb > 0.0 else "f87171", int(round(absf(sb) * 100)), "increased" if sb > 0.0 else "less"]
	if no_crit:
		t += "[color=#f87171]• Cannot deal Critical Hits[/color]\n"
	if level_bonus > 0:
		t += "[color=#ffd24d]• +%d to Level of the supported skill[/color]\n" % level_bonus
	if not needs.is_empty():
		t += "[color=#9a8f7e]Supports: %s skills[/color]\n" % ", ".join(PackedStringArray(needs))
	if ailment != "":
		t += "[color=#%s]• Inflicts %s (%d%% chance)[/color]\n" % [color.to_html(false), ailment.to_upper(), int(ailment_chance * 100)]
	if category == Category.META:
		t += "[color=#ffd24d]• Casts a skill of your choice %s[/color]\n" % ("on a critical strike" if trigger == "crit" else "when you take damage")
	return t


## This support gem's picture: its painted icon, or a drawn placeholder.
func get_icon() -> Texture2D:
	return IconFactory.rune_icon(self)


class DB:
	static var _catalog: Dictionary = {}

	static func _make(id: String, name: String, prefix: String, cat: Category,
			dtype: DamageType, icon_sym: String, col: Color, desc: String, mods := {}) -> RuneDef:
		var r := RuneDef.new()
		r.id = id
		r.base_id = id
		r.display_name = name
		r.title_prefix = prefix
		r.category = cat
		r.damage_type = dtype
		r.icon = icon_sym
		r.color = col
		r.description = desc
		r.damage_mult_bonus = mods.get("damage_mult_bonus", 0.0)
		r.cooldown_mult = mods.get("cooldown_mult", 1.0)
		r.radius_mult = mods.get("radius_mult", 1.0)
		r.force_360_arc = mods.get("force_360_arc", false)
		r.life_leech = mods.get("life_leech", 0.0)
		r.has_echo = mods.get("has_echo", false)
		r.execute_bonus = mods.get("execute_bonus", 0.0)
		r.ailment = mods.get("ailment", "")
		r.ailment_chance = mods.get("ailment_chance", 1.0)
		r.cost_mult = mods.get("cost_mult", 1.3)
		r.trigger = mods.get("trigger", "")
		r.family = mods.get("family", "")
		r.tier = mods.get("tier", 0)
		r.needs = mods.get("needs", [])
		r.more_damage = mods.get("more_damage", 0.0)
		r.speed_bonus = mods.get("speed_bonus", 0.0)
		r.extra_projectiles = mods.get("extra_projectiles", 0)
		r.extra_chains = mods.get("extra_chains", 0)
		r.no_crit = mods.get("no_crit", false)
		r.level_bonus = mods.get("level_bonus", 0)
		r.pierce = mods.get("pierce", 0)
		r.pierce_less = mods.get("pierce_less", 0.0)
		r.forks = mods.get("forks", 0)
		r.fork_less = mods.get("fork_less", 0.0)
		r.penetration = mods.get("penetration", 0.0)
		r.pen_type = mods.get("pen_type", -1)
		r.expose_type = mods.get("expose_type", -1)
		r.player_only = mods.get("player_only", false)
		_catalog[id] = r
		return r

	static func init_catalog() -> void:
		if not _catalog.is_empty():
			return

		# --- Transmutation (Elemental) Runes ---
		_make("rune_frost", "Glacial Support", "Glacial", Category.TRANSMUTATION, DamageType.COLD,
			"❄", Color(0.4, 0.85, 1.0),
			"Converts damage to Cold. Chills enemies (40% slow) and Freezes on critical strikes.",
			{"ailment": "chill", "ailment_chance": 1.0, "cost_mult": 1.2})

		_make("rune_fire", "Cinder Support", "Molten", Category.TRANSMUTATION, DamageType.FIRE,
			"🔥", Color(1.0, 0.45, 0.15),
			"Converts damage to Fire. Ignites enemies to suffer burning damage over 3 seconds.",
			{"ailment": "burn", "ailment_chance": 1.0, "damage_mult_bonus": 0.15, "cost_mult": 1.2})

		_make("rune_lightning", "Storm Support", "Tempest", Category.TRANSMUTATION, DamageType.LIGHTNING,
			"⚡", Color(1.0, 0.95, 0.3),
			"Converts damage to Lightning. Shocks foes to make them take 25% increased damage.",
			{"ailment": "shock", "ailment_chance": 1.0, "cost_mult": 1.2})

		_make("rune_chaos", "Venom Support", "Noxious", Category.TRANSMUTATION, DamageType.CHAOS,
			"☠", Color(0.85, 0.3, 1.0),
			"Converts damage to Chaos. Poisons targets to deal armor-bypassing decay over time.",
			{"ailment": "poison", "ailment_chance": 1.0, "damage_mult_bonus": 0.1, "cost_mult": 1.2})

		# --- Form / Geometry Runes ---
		_make("rune_nova", "Nova Support", "Radial", Category.FORM, DamageType.PHYSICAL,
			"💥", Color(1.0, 0.7, 0.2),
			"Converts frontal attacks into a 360° outward shockwave around the warrior with +25% radius.",
			{"force_360_arc": true, "radius_mult": 1.25, "cost_mult": 1.3})

		_make("rune_echo", "Cascade Support", "Echoing", Category.FORM, DamageType.PHYSICAL,
			"🔁", Color(0.5, 0.9, 0.6),
			"Striking releases a delayed secondary aftershock 0.25s later dealing 50% damage.",
			{"has_echo": true, "cost_mult": 1.4})

		_make("rune_reach", "Reach Support", "Vast", Category.FORM, DamageType.PHYSICAL,
			"🎯", Color(0.7, 0.85, 0.95),
			"Vastly expands the skill's reach and impact area by +45%.",
			{"radius_mult": 1.45, "cost_mult": 1.2})

		# --- Modifier / Utility Runes ---
		_make("rune_vampiric", "Vampiric Support", "Bloody", Category.MODIFIER, DamageType.PHYSICAL,
			"🩸", Color(0.95, 0.2, 0.3),
			"Restores 18% of damage dealt as life to the warrior.",
			{"life_leech": 0.18, "cost_mult": 1.25})

		_make("rune_brutality", "Brutality Support", "Savage", Category.MODIFIER, DamageType.PHYSICAL,
			"⚔", Color(1.0, 0.3, 0.1),
			"+35% More Skill Damage, but slightly increases cooldown by 15%.",
			{"damage_mult_bonus": 0.35, "cooldown_mult": 1.15, "cost_mult": 1.4})

		_make("rune_alacrity", "Alacrity Support", "Swift", Category.MODIFIER, DamageType.PHYSICAL,
			"⌛", Color(0.3, 0.95, 0.8),
			"Reduces skill cooldown by 30% and accelerates execution speed.",
			{"cooldown_mult": 0.70, "cost_mult": 1.3})

		_make("rune_execute", "Execute Support", "Lethal", Category.MODIFIER, DamageType.PHYSICAL,
			"💀", Color(0.9, 0.4, 0.1),
			"+50% Critical Strike Chance against enemies below 35% health.",
			{"execute_bonus": 0.50, "cost_mult": 1.2})

		# --- Meta supports: fire another skill (chosen in the link) for free ---
		_make("rune_cast_crit", "Cast on Critical Strike", "", Category.META, DamageType.PHYSICAL,
			"✴", Color(1.0, 0.82, 0.30),
			"Whenever you land a critical strike, also casts the skill chosen in this link, free of cost (at most once every %.1f seconds)." % TRIGGER_COOLDOWN.crit,
			{"trigger": "crit", "cost_mult": 1.0})

		_make("rune_cast_hurt", "Cast when Damage Taken", "", Category.META, DamageType.PHYSICAL,
			"🛡", Color(0.95, 0.45, 0.55),
			"Whenever you take damage, also casts the skill chosen in this link, free of cost (at most once every %.1f seconds)." % TRIGGER_COOLDOWN.hurt,
			{"trigger": "hurt", "cost_mult": 1.0})

		# --- Path of Exile 2 supports (numbers from poe2db.tw: see POE2_REFERENCE.md). A tier is a stronger version of
		# the same family; each is restricted to the skills it makes sense on, and none costs more to use (PoE2's
		# 100% mana multiplier), Magnified Area aside. ---
		_make("rune_multishot_1", "Multishot I", "", Category.FORM, DamageType.PHYSICAL,
			"⇶", Color(0.75, 0.9, 0.6), "Fires 2 additional projectiles, but deals 35% less damage and has 20% less skill speed.",
			{"family": "multishot", "tier": 1, "needs": ["projectile"], "extra_projectiles": 2, "more_damage": -0.35,
				"speed_bonus": -0.20, "cost_mult": 1.0, "player_only": true})
		_make("rune_multishot_2", "Multishot II", "", Category.FORM, DamageType.PHYSICAL,
			"⇶", Color(0.55, 0.85, 0.7), "Fires 2 additional projectiles, but deals 25% less damage and has 20% less skill speed.",
			{"family": "multishot", "tier": 2, "needs": ["projectile"], "extra_projectiles": 2, "more_damage": -0.25,
				"speed_bonus": -0.20, "cost_mult": 1.0, "player_only": true})
		_make("rune_chain_1", "Chain I", "", Category.FORM, DamageType.LIGHTNING,
			"⛓", Color(0.85, 0.9, 0.5), "The skill chains 1 additional time, but deals 30% less damage.",
			{"family": "chain", "tier": 1, "needs": ["chaining"], "extra_chains": 1, "more_damage": -0.30,
				"cost_mult": 1.0, "player_only": true})
		_make("rune_chain_2", "Chain II", "", Category.FORM, DamageType.LIGHTNING,
			"⛓", Color(0.95, 0.85, 0.4), "The skill chains 2 additional times, but deals 50% less damage.",
			{"family": "chain", "tier": 2, "needs": ["chaining"], "extra_chains": 2, "more_damage": -0.50,
				"cost_mult": 1.0, "player_only": true})
		_make("rune_rapid_attacks_1", "Rapid Attacks I", "", Category.MODIFIER, DamageType.PHYSICAL,
			"⚔", Color(0.95, 0.6, 0.3), "The attack is used 15% faster.",
			{"family": "rapid_attacks", "tier": 1, "needs": ["attack"], "speed_bonus": 0.15, "cost_mult": 1.0, "player_only": true})
		_make("rune_rapid_casting_1", "Rapid Casting I", "", Category.MODIFIER, DamageType.PHYSICAL,
			"⌛", Color(0.5, 0.7, 1.0), "The spell is cast 15% faster.",
			{"family": "rapid_casting", "tier": 1, "needs": ["spell"], "speed_bonus": 0.15, "cost_mult": 1.0, "player_only": true})
		_make("rune_controlled_destruction", "Controlled Destruction", "", Category.MODIFIER, DamageType.PHYSICAL,
			"🎯", Color(0.6, 0.6, 1.0), "A spell that hits deals 25% more damage, but cannot deal critical hits.",
			{"family": "controlled_destruction", "tier": 1, "needs": ["spell", "hit"], "more_damage": 0.25, "no_crit": true,
				"cost_mult": 1.0, "player_only": true})
		_make("rune_magnified_area_1", "Magnified Area I", "", Category.FORM, DamageType.PHYSICAL,
			"◎", Color(0.7, 0.85, 0.95), "The skill's area of effect is 35% larger.",
			{"family": "magnified_area", "tier": 1, "needs": ["area"], "radius_mult": 1.35, "cost_mult": 1.3})
		_make("rune_life_leech_1", "Life Leech I", "", Category.MODIFIER, DamageType.PHYSICAL,
			"🩸", Color(0.9, 0.25, 0.35), "Leeches 12% of the damage dealt as life.",
			{"family": "life_leech", "tier": 1, "needs": ["attack", "physical"], "life_leech": 0.12, "cost_mult": 1.0})
		_make("rune_chain_3", "Chain III", "", Category.FORM, DamageType.LIGHTNING,
			"⛓", Color(1.0, 0.8, 0.35), "The skill chains 2 additional times, but deals 40% less damage.",
			{"family": "chain", "tier": 3, "needs": ["chaining"], "extra_chains": 2, "more_damage": -0.40,
				"cost_mult": 1.0, "player_only": true})
		_make("rune_rapid_attacks_2", "Rapid Attacks II", "", Category.MODIFIER, DamageType.PHYSICAL,
			"⚔", Color(0.98, 0.55, 0.25), "The attack is used 25% faster.",
			{"family": "rapid_attacks", "tier": 2, "needs": ["attack"], "speed_bonus": 0.25, "cost_mult": 1.0, "player_only": true})
		_make("rune_rapid_attacks_3", "Rapid Attacks III", "", Category.MODIFIER, DamageType.PHYSICAL,
			"⚔", Color(1.0, 0.5, 0.2), "The attack is used 35% faster, but deals 50% less damage.",
			{"family": "rapid_attacks", "tier": 3, "needs": ["attack"], "speed_bonus": 0.35, "more_damage": -0.50,
				"cost_mult": 1.0, "player_only": true})
		_make("rune_rapid_casting_2", "Rapid Casting II", "", Category.MODIFIER, DamageType.PHYSICAL,
			"⌛", Color(0.45, 0.65, 1.0), "The spell is cast 20% faster.",
			{"family": "rapid_casting", "tier": 2, "needs": ["spell"], "speed_bonus": 0.20, "cost_mult": 1.0, "player_only": true})
		_make("rune_magnified_area_2", "Magnified Area II", "", Category.FORM, DamageType.PHYSICAL,
			"◎", Color(0.65, 0.8, 0.98), "The skill's area of effect is 45% larger.",
			{"family": "magnified_area", "tier": 2, "needs": ["area"], "radius_mult": 1.45, "cost_mult": 1.3})
		_make("rune_life_leech_2", "Life Leech II", "", Category.MODIFIER, DamageType.PHYSICAL,
			"🩸", Color(0.92, 0.22, 0.32), "Leeches 16% of the damage dealt as life.",
			{"family": "life_leech", "tier": 2, "needs": ["attack", "physical"], "life_leech": 0.16, "cost_mult": 1.0})
		_make("rune_fire_mastery", "Fire Mastery", "", Category.MODIFIER, DamageType.FIRE,
			"🔥", Color(1.0, 0.5, 0.2), "+1 to the level of a Fire skill.",
			{"family": "fire_mastery", "tier": 5, "needs": ["fire"], "level_bonus": 1, "cost_mult": 1.0})
		_make("rune_cold_mastery", "Cold Mastery", "", Category.MODIFIER, DamageType.COLD,
			"❄", Color(0.5, 0.85, 1.0), "+1 to the level of a Cold skill.",
			{"family": "cold_mastery", "tier": 5, "needs": ["cold"], "level_bonus": 1, "cost_mult": 1.0})
		_make("rune_lightning_mastery", "Lightning Mastery", "", Category.MODIFIER, DamageType.LIGHTNING,
			"⚡", Color(1.0, 0.95, 0.4), "+1 to the level of a Lightning skill.",
			{"family": "lightning_mastery", "tier": 5, "needs": ["lightning"], "level_bonus": 1, "cost_mult": 1.0})
		_make("rune_chaos_mastery", "Chaos Mastery", "", Category.MODIFIER, DamageType.CHAOS,
			"☠", Color(0.8, 0.35, 1.0), "+1 to the level of a Chaos skill.",
			{"family": "chaos_mastery", "tier": 5, "needs": ["chaos"], "level_bonus": 1, "cost_mult": 1.0})
		# Projectile supports: Pierce passes through enemies, Fork splits the shot where it lands. (poe2db: Pierce III
		# pierces everything at 20% less damage per enemy; Pierce I and II counts, 1 and 3, are our own.)
		_make("rune_pierce_1", "Pierce I", "", Category.FORM, DamageType.PHYSICAL,
			"➤", Color(0.85, 0.85, 0.95), "Projectiles pierce an enemy, then deal 20% less damage.",
			{"family": "pierce", "tier": 1, "needs": ["projectile"], "pierce": 1, "pierce_less": 0.2, "cost_mult": 1.0, "player_only": true})
		_make("rune_pierce_2", "Pierce II", "", Category.FORM, DamageType.PHYSICAL,
			"➤", Color(0.85, 0.85, 0.95), "Projectiles pierce three enemies, each pierce costing them 20% damage.",
			{"family": "pierce", "tier": 3, "needs": ["projectile"], "pierce": 3, "pierce_less": 0.2, "cost_mult": 1.0, "player_only": true})
		_make("rune_pierce_3", "Pierce III", "", Category.FORM, DamageType.PHYSICAL,
			"➤", Color(0.85, 0.85, 0.95), "Projectiles pierce every enemy, each pierce costing them 20% damage.",
			{"family": "pierce", "tier": 5, "needs": ["projectile"], "pierce": 99, "pierce_less": 0.2, "cost_mult": 1.0, "player_only": true})
		_make("rune_fork", "Fork", "", Category.FORM, DamageType.PHYSICAL,
			"⑂", Color(0.9, 0.8, 0.5), "Projectiles fork in two where they hit an enemy; the forks deal 30% less damage.",
			{"family": "fork", "tier": 3, "needs": ["projectile"], "forks": 2, "fork_less": 0.3, "cost_mult": 1.1, "player_only": true})
		# Penetration and Exposure work on the resistances Tainted's monsters carry (Fireproof, Frostborn, Grounded).
		_make("rune_fire_penetration_1", "Fire Penetration I", "", Category.MODIFIER, DamageType.FIRE,
			"🔥", Color(1.0, 0.5, 0.2), "Hits penetrate 30% of the enemy's fire resistance.",
			{"family": "fire_penetration", "tier": 2, "needs": ["hit"], "penetration": 0.3, "pen_type": DamageType.FIRE, "cost_mult": 1.2, "player_only": true})
		_make("rune_fire_penetration_2", "Fire Penetration II", "", Category.MODIFIER, DamageType.FIRE,
			"🔥", Color(1.0, 0.5, 0.2), "Hits ignore the enemy's fire resistance.",
			{"family": "fire_penetration", "tier": 5, "needs": ["hit"], "penetration": 1.0, "pen_type": DamageType.FIRE, "cost_mult": 1.2, "player_only": true})
		_make("rune_cold_penetration", "Cold Penetration", "", Category.MODIFIER, DamageType.COLD,
			"❄", Color(0.5, 0.85, 1.0), "Hits penetrate 30% of the enemy's cold resistance.",
			{"family": "cold_penetration", "tier": 2, "needs": ["hit"], "penetration": 0.3, "pen_type": DamageType.COLD, "cost_mult": 1.2, "player_only": true})
		_make("rune_lightning_penetration", "Lightning Penetration", "", Category.MODIFIER, DamageType.LIGHTNING,
			"⚡", Color(1.0, 0.95, 0.4), "Hits penetrate 30% of the enemy's lightning resistance.",
			{"family": "lightning_penetration", "tier": 2, "needs": ["hit"], "penetration": 0.3, "pen_type": DamageType.LIGHTNING, "cost_mult": 1.2, "player_only": true})
		_make("rune_fire_exposure", "Fire Exposure", "", Category.MODIFIER, DamageType.FIRE,
			"🔥", Color(1.0, 0.5, 0.2), "Hits that ignite also expose the enemy: -20% fire resistance for 8 seconds.",
			{"family": "fire_exposure", "tier": 4, "needs": ["hit"], "expose_type": DamageType.FIRE, "cost_mult": 1.2, "player_only": true})
		_make("rune_cold_exposure", "Cold Exposure", "", Category.MODIFIER, DamageType.COLD,
			"❄", Color(0.5, 0.85, 1.0), "Cold critical hits also expose the enemy: -20% cold resistance for 8 seconds.",
			{"family": "cold_exposure", "tier": 4, "needs": ["hit"], "expose_type": DamageType.COLD, "cost_mult": 1.2, "player_only": true})
		_make("rune_lightning_exposure", "Lightning Exposure", "", Category.MODIFIER, DamageType.LIGHTNING,
			"⚡", Color(1.0, 0.95, 0.4), "Hits that shock also expose the enemy: -20% lightning resistance for 8 seconds.",
			{"family": "lightning_exposure", "tier": 4, "needs": ["hit"], "expose_type": DamageType.LIGHTNING, "cost_mult": 1.2, "player_only": true})

	static func make_id(base: String, r: int) -> String:
		return base if r <= 0 else "%s@%d" % [base, r]

	static func base_of(id: String) -> String:
		return id.get_slice("@", 0)

	static func rarity_of(id: String) -> int:
		return clampi(id.get_slice("@", 1).to_int(), 0, 2) if id.contains("@") else 0

	## Normal runes come straight from the catalog; Magic / Rare ones are scaled copies (cached).
	static func get_rune(id: String) -> RuneDef:
		init_catalog()
		if _catalog.has(id):
			return _catalog[id]
		var b := base_of(id)
		var r := rarity_of(id)
		if r <= 0 or not _catalog.has(b):
			return null
		var src: RuneDef = _catalog[b]
		var v: RuneDef = src.duplicate()
		var m: float = RARITY_POWER[r]
		v.id = id
		v.base_id = b
		v.rarity = r
		v.display_name = "%s %s" % [RARITY_NAMES[r], src.display_name]
		v.damage_mult_bonus = src.damage_mult_bonus * m + RARITY_DAMAGE[r]
		if src.cooldown_mult < 1.0:
			v.cooldown_mult = maxf(1.0 - (1.0 - src.cooldown_mult) * m, 0.3)
		v.radius_mult = 1.0 + (src.radius_mult - 1.0) * m
		v.life_leech = src.life_leech * m
		v.execute_bonus = src.execute_bonus * m
		if src.speed_bonus > 0.0:
			v.speed_bonus = src.speed_bonus * m
		if src.more_damage > 0.0:
			v.more_damage = src.more_damage * m   # (a penalty stays what it is)
		_catalog[id] = v
		return v

	## A random rune id with rolled rarity (better odds from bosses and higher rift levels).
	static func random_drop(rift_level: int = 1, boss: bool = false) -> String:
		var odds: Array = BOSS_DROP_ODDS if boss else DROP_ODDS
		var bonus := RIFT_RARITY_BONUS * (rift_level - 1)
		var roll := randf()
		var r := 0
		if roll < float(odds[1]) + bonus:
			r = 2
		elif roll < float(odds[0]) + float(odds[1]) + bonus * 2.0:
			r = 1
		return make_id(base_runes().pick_random().id, r)

	## The Normal version of every rune type.
	static func base_runes() -> Array[RuneDef]:
		init_catalog()
		var list: Array[RuneDef] = []
		for id in _catalog:
			if not String(id).contains("@"):
				list.append(_catalog[id])
		return list

	static func all_runes() -> Array[RuneDef]:
		return base_runes()
