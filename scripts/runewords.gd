class_name Runewords
extends RefCounted
## Runewords, Diablo II style. Put exactly a runeword's runes, in order, into a Normal item of a
## kind it allows with exactly that many sockets, and the item becomes that runeword: it takes the
## runeword's name and colour (ItemInstance.Rarity.RUNEWORD) and rolls its bonuses, on top of what
## each rune gives in its socket (SocketRune). Once formed it is permanent, Diablo II style: its
## runes can't be taken out or swapped (GameState.socket_gem / unsocket_gem refuse), orbs can't
## alter it, and selling it sells its runes with it.
##
## Bonuses:
##   powers - passive stat keys (PassiveTree.stat_text), [min, max], summed through Player.item_powers
##            like a Legendary's power
##   mods   - item stats with no passive key (flat damage, flat armour): [stat, mod, min, max]
## Rolls land higher in the range at higher item levels (ItemInstance.ilvl_roll).
##
## `types` lists the item kinds it fits: "weapon", "one_handed", "two_handed", a weapon type
## ("sword", "axe", "mace", "staff", "bow", "dagger"), "shield", "helmet", "chest", "gloves",
## "boots", or "armour" (any of helmet, chest, gloves, boots, shield).

const F := StatBlock.ModType.FLAT

const LIST := {
	# --- two runes ---
	"steel": {"name": "Steel", "runes": ["tir", "el"], "types": ["weapon"],
		"powers": {"damage_inc": [0.20, 0.30], "attack_speed_inc": [0.10, 0.15]},
		"mods": [["damage", F, 4.0, 8.0]]},
	"stealth": {"name": "Stealth", "runes": ["tal", "eth"], "types": ["chest"],
		"powers": {"move_inc": [0.10, 0.15], "attack_speed_inc": [0.05, 0.08]},
		"mods": [["armor", F, 20.0, 35.0]]},
	"nadir": {"name": "Nadir", "runes": ["nef", "tir"], "types": ["helmet"],
		"powers": {"armor_inc": [0.30, 0.50], "life_flat": [20.0, 30.0]}},
	"lore": {"name": "Lore", "runes": ["ort", "sol"], "types": ["helmet"],
		"powers": {"gem_level": [1.0, 1.0], "power_max": [10.0, 15.0]}},
	"rhyme": {"name": "Rhyme", "runes": ["shael", "eth"], "types": ["shield"],
		"powers": {"armor_inc": [0.25, 0.40], "regen": [1.0, 2.0]}},
	"smoke": {"name": "Smoke", "runes": ["nef", "lum"], "types": ["chest"],
		"powers": {"armor_inc": [0.40, 0.60], "life_inc": [0.05, 0.08]}},
	"strength": {"name": "Strength", "runes": ["amn", "tir"], "types": ["weapon"],
		"powers": {"damage_inc": [0.25, 0.35], "leech": [0.03, 0.04], "life_flat": [15.0, 20.0]}},
	"grip": {"name": "Iron Grip", "runes": ["ort", "shael"], "types": ["gloves"],
		"powers": {"attack_speed_inc": [0.10, 0.15], "crit": [0.02, 0.03]}},
	"haste": {"name": "Haste", "runes": ["eld", "amn"], "types": ["boots"],
		"powers": {"move_inc": [0.12, 0.18], "life_flat": [15.0, 25.0]}},
	# --- three runes ---
	"malice": {"name": "Malice", "runes": ["ith", "el", "eth"], "types": ["weapon"],
		"powers": {"damage_inc": [0.30, 0.45], "leech": [0.02, 0.03]}},
	"ancients_pledge": {"name": "Ancient's Pledge", "runes": ["ral", "ort", "tal"], "types": ["shield"],
		"powers": {"armor_inc": [0.40, 0.60], "thorns": [15.0, 25.0]}},
	"treachery": {"name": "Treachery", "runes": ["shael", "thul", "lem"], "types": ["chest"],
		"powers": {"attack_speed_inc": [0.15, 0.20], "crit": [0.03, 0.05], "move_inc": [0.05, 0.05]}},
	"enigma": {"name": "Enigma", "runes": ["jah", "ith", "ber"], "types": ["chest"],
		"powers": {"gem_level": [2.0, 2.0], "move_inc": [0.25, 0.35], "life_inc": [0.15, 0.20], "armor_inc": [0.50, 0.80]}},
	"dream": {"name": "Dream", "runes": ["io", "jah", "pul"], "types": ["helmet", "shield"],
		"powers": {"life_inc": [0.10, 0.15], "crit": [0.03, 0.03], "damage_inc": [0.20, 0.20]}},
	# --- four runes ---
	"spirit": {"name": "Spirit", "runes": ["tal", "thul", "ort", "amn"], "types": ["one_handed", "shield"],
		"powers": {"gem_level": [1.0, 1.0], "cost_red": [0.10, 0.15], "power_max": [20.0, 30.0], "attack_speed_inc": [0.10, 0.15]}},
	"insight": {"name": "Insight", "runes": ["ral", "tir", "tal", "sol"], "types": ["two_handed"],
		"powers": {"cost_red": [0.15, 0.25], "regen": [3.0, 5.0], "crit": [0.05, 0.08], "damage_inc": [0.20, 0.30]}},
	"heart_of_the_oak": {"name": "Heart of the Oak", "runes": ["ko", "vex", "pul", "thul"], "types": ["mace", "staff"],
		"powers": {"gem_level": [1.0, 1.0], "attack_speed_inc": [0.30, 0.40], "regen": [4.0, 6.0], "life_inc": [0.10, 0.15]}},
	"fortitude": {"name": "Fortitude", "runes": ["el", "sol", "dol", "lo"], "types": ["chest", "weapon"],
		"powers": {"damage_inc": [0.40, 0.60], "life_inc": [0.10, 0.15], "armor_inc": [0.40, 0.60]}},
	"chains_of_honor": {"name": "Chains of Honor", "runes": ["dol", "um", "ber", "ist"], "types": ["chest"],
		"powers": {"gem_level": [2.0, 2.0], "damage_inc": [0.25, 0.35], "leech": [0.03, 0.05], "life_flat": [40.0, 60.0]}},
	"infinity": {"name": "Infinity", "runes": ["ber", "mal", "ber", "ist"], "types": ["two_handed"],
		"powers": {"damage_inc": [0.60, 0.90], "crit": [0.08, 0.12], "execute": [0.30, 0.50]}},
	"phoenix": {"name": "Phoenix", "runes": ["vex", "vex", "lo", "jah"], "types": ["weapon", "shield"],
		"powers": {"life_flat": [50.0, 70.0], "damage_inc": [0.40, 0.60], "regen": [5.0, 8.0]}},
	"exile": {"name": "Exile", "runes": ["vex", "ohm", "ist", "dol"], "types": ["shield"],
		"powers": {"armor_inc": [0.90, 1.20], "regen": [6.0, 10.0], "thorns": [50.0, 80.0]}},
	# --- five runes ---
	"grief": {"name": "Grief", "runes": ["eth", "tir", "lo", "mal", "ral"], "types": ["sword", "axe"],
		"powers": {"attack_speed_inc": [0.30, 0.40], "crit": [0.05, 0.05]},
		"mods": [["damage", F, 40.0, 60.0]]},
	"doom": {"name": "Doom", "runes": ["hel", "ohm", "um", "lo", "cham"], "types": ["two_handed"],
		"powers": {"damage_inc": [0.50, 0.70], "attack_speed_inc": [0.20, 0.30], "rampage": [0.30, 0.50]}},
	"beast": {"name": "Beast", "runes": ["ber", "tir", "um", "mal", "lum"], "types": ["axe", "mace", "staff"],
		"powers": {"damage_inc": [0.70, 0.90], "life_flat": [60.0, 80.0], "rampage": [0.30, 0.30]}},
	# --- six runes: two-handed weapons and body armour only ---
	"wraithweave": {"name": "Wraithweave", "runes": ["thul", "eth", "sol", "ral", "ort", "tal"], "types": ["chest"],
		"powers": {"life_inc": [0.12, 0.18], "armor_inc": [0.50, 0.80], "regen": [3.0, 5.0], "thorns": [30.0, 50.0]}},
	"last_wish": {"name": "Last Wish", "runes": ["jah", "mal", "jah", "sur", "jah", "ber"], "types": ["sword", "axe", "mace"],
		"powers": {"damage_inc": [1.00, 1.40], "crit": [0.10, 0.15], "execute": [0.50, 0.80], "attack_speed_inc": [0.25, 0.35]}},
	"breath_of_the_dying": {"name": "Breath of the Dying", "runes": ["vex", "hel", "el", "eld", "zod", "eth"], "types": ["weapon"],
		"powers": {"damage_inc": [0.90, 1.30], "leech": [0.05, 0.08], "rampage": [0.50, 0.80], "attack_speed_inc": [0.25, 0.30]}},
}

## Passive keys whose values are whole numbers.
const WHOLE_KEYS := ["gem_level", "power_max", "thorns", "life_flat"]


## Whether an item of this base is a kind the runeword fits.
static func fits(rw: Dictionary, b: ItemBase) -> bool:
	for t in rw.types:
		match String(t):
			"weapon":
				if b.slot == "weapon": return true
			"one_handed":
				if b.slot == "weapon" and not b.two_handed: return true
			"two_handed":
				if b.slot == "weapon" and b.two_handed: return true
			"shield":
				if b.weapon_type == "shield": return true
			"armour":
				if b.slot in ["helmet", "shoulders", "chest", "gloves", "boots"] or b.weapon_type == "shield": return true
			"helmet", "chest", "gloves", "boots":
				if b.slot == String(t): return true
			_:
				if b.slot == "weapon" and b.weapon_type == String(t): return true
	return false


## The runeword an item's runes spell, or "". It must be a plain (Normal or already runeword),
## identified item with exactly as many sockets as the runeword has runes, every one filled with
## them in order, and of a kind the runeword fits.
static func match_item(item: ItemInstance) -> String:
	if item == null or item.base == null or item.is_unique() or item.is_flask() or not item.identified:
		return ""
	if item.rarity != ItemInstance.Rarity.NORMAL and item.rarity != ItemInstance.Rarity.RUNEWORD:
		return ""
	if item.sockets <= 0 or item.gems.size() != item.sockets:
		return ""
	var keys: Array[String] = []
	for gid in item.gems:
		if not SocketRune.is_rune(gid):
			return ""
		keys.append(SocketRune.key_of(gid))
	for id in LIST:
		var rw: Dictionary = LIST[id]
		if rw.runes.size() == keys.size() and Array(rw.runes) == Array(keys) and fits(rw, item.base):
			return String(id)
	return ""


## When an item's runes spell a runeword (in order, from the first socket) but the item can't
## become it, why: "Steel needs a Normal (white) item; this is Legendary". "" otherwise, including
## when it already is that runeword. Keeps a runeword that silently fails to form from looking broken.
static func why_not(item: ItemInstance) -> String:
	if item == null or item.base == null or item.is_runeword():
		return ""
	var keys: Array = []
	for gid in item.gems:
		if not SocketRune.is_rune(gid):
			return ""
		keys.append(SocketRune.key_of(gid))
	if keys.is_empty():
		return ""
	# Part-way through a longer runeword that starts with these runes: nothing to warn about yet
	if item.gems.size() < item.sockets:
		for id in LIST:
			var longer: Array = LIST[id].runes
			if longer.size() > keys.size() and longer.slice(0, keys.size()) == keys:
				return ""
	for id in LIST:
		var rw: Dictionary = LIST[id]
		if Array(rw.runes) != keys:
			continue
		if item.is_unique() or item.rarity != ItemInstance.Rarity.NORMAL:
			# A Magic or Rare base can be made Normal; a Legendary or Set item can't
			var hint := "" if item.is_unique() else " An Orb of Scouring makes it Normal."
			return "%s needs a Normal (white) item; this one is %s.%s" % [rw.name,
				ItemInstance.Rarity.keys()[item.rarity].capitalize(), hint]
		if not fits(rw, item.base):
			return "%s only goes in a %s." % [rw.name, types_text(id)]
		if item.sockets != rw.runes.size():
			return "%s needs exactly %d sockets; this item has %d." % [rw.name, rw.runes.size(), item.sockets]
		if not item.identified:
			return "Identify the item first."
	return ""


## Makes the item what its runes now spell: a runeword forms, breaks, or stays as it is.
## Returns "formed", "broken" or "".
static func refresh(item: ItemInstance) -> String:
	var want := match_item(item)
	if want == item.runeword_id:
		return ""
	var was := item.is_runeword()
	if was:
		_clear(item)
	if want != "":
		_form(item, want)
		return "formed"
	return "broken" if was else ""


static func _form(item: ItemInstance, id: String) -> void:
	var rw: Dictionary = LIST[id]
	item.runeword_id = id
	item.rarity = ItemInstance.Rarity.RUNEWORD
	item.display_name = String(rw.name)
	item.powers.clear()
	var pw: Dictionary = rw.get("powers", {})
	for k in pw:
		var v := lerpf(float(pw[k][0]), float(pw[k][1]), ItemInstance.ilvl_roll(item.ilvl))
		item.powers[k] = roundf(v) if WHOLE_KEYS.has(k) else snappedf(v, 0.01)
	item.rw_mods.clear()
	for m in rw.get("mods", []):
		var v := roundf(lerpf(float(m[2]), float(m[3]), ItemInstance.ilvl_roll(item.ilvl)))
		item.rw_mods.append({"stat": String(m[0]), "mod_type": int(m[1]), "value": v,
			"text": SocketRune.stat_text([m[0], m[1], v])})


static func _clear(item: ItemInstance) -> void:
	item.runeword_id = ""
	item.rarity = ItemInstance.Rarity.NORMAL
	item.display_name = item.base.display_name
	item.powers.clear()
	item.rw_mods.clear()


# ---------- describing ----------

## "Tal • Eth"
static func rune_names(id: String) -> String:
	var rw: Dictionary = LIST.get(id, {})
	var names: Array[String] = []
	for k in rw.get("runes", []):
		names.append(String(SocketRune.info(SocketRune.id_of(String(k))).get("short", String(k).capitalize())))
	return " • ".join(PackedStringArray(names))


## "Body Armour", "Two-Handed Weapon or Shield" -- what it fits.
static func types_text(id: String) -> String:
	const NAMES := {"weapon": "Weapon", "one_handed": "One-Handed Weapon", "two_handed": "Two-Handed Weapon",
		"shield": "Shield", "armour": "Armour", "helmet": "Helmet", "chest": "Body Armour", "gloves": "Gloves",
		"boots": "Boots", "sword": "Sword", "axe": "Axe", "mace": "Mace", "staff": "Staff", "bow": "Bow",
		"crossbow": "Crossbow", "dagger": "Dagger"}
	var parts: Array[String] = []
	for t in LIST.get(id, {}).get("types", []):
		parts.append(String(NAMES.get(String(t), String(t).capitalize())))
	return " or ".join(PackedStringArray(parts))


## The runewords a rune is part of, for showing players what to make with it.
static func using_rune(rune_id: String) -> Array[String]:
	var key := SocketRune.key_of(rune_id)
	var out: Array[String] = []
	for id in LIST:
		if Array(LIST[id].runes).has(key):
			out.append(String(id))
	return out


## BBCode for a runeword item's card: its runes, rolled stat bonuses and powers.
static func card_bbcode(item: ItemInstance) -> String:
	if not item.is_runeword():
		return ""
	var t := "[color=#c7b377]Runeword: %s[/color]\n" % rune_names(item.runeword_id)
	for m in item.rw_mods:
		t += "[color=#c7b377]✦ %s[/color]\n" % m.text
	if not item.powers.is_empty():
		for part in PassiveTree.stat_text(item.powers).split(", "):
			t += "[color=#c7b377]✦ %s[/color]\n" % part
	return t


## A recipe line: "Stealth: Tal • Eth  (Body Armour, 2 sockets)".
static func recipe_text(id: String) -> String:
	var rw: Dictionary = LIST[id]
	return "%s: %s  (%s, %d sockets)" % [rw.name, rune_names(id), types_text(id), rw.runes.size()]
