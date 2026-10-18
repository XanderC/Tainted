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
	MODIFIER        ## Stat enhancements and utility (Vampiric, Brutality, Alacrity, Execute)
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
@export var rarity: int = 0                  ## ItemInstance.Rarity
@export var base_id: String = ""             ## id without the rarity suffix

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
	if ailment != "":
		t += "[color=#%s]• Inflicts %s (%d%% chance)[/color]\n" % [color.to_html(false), ailment.to_upper(), int(ailment_chance * 100)]
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
