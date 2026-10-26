class_name Wardrobe
extends RefCounted
## Appearances (transmog): a helmet, body armour, gloves, boots, weapon or shield can be made to look
## like any other piece of its group you have unlocked, changed by the Dyer in Ashfall (DyeUI's
## Appearance tab). It's only how the piece looks: its stats stay its own. An item keeps the look it
## was given (ItemInstance.look, "" for its own).
## Groups: each armour slot is one; weapons are "melee" (any melee weapon looks like any other: the
## rig holds them all the same way), "bow" (bows and two-handed crossbows, drawn on the archer rig) or
## "handxbow" (one-handed crossbows); shields are "shield".
## A look is a piece of gear art, assets/gear/<folder>/<id>/ (listed in that folder's catalog.json;
## weapons' folder is weapon, shields' offhand): an item's own look is its base's, or its Legendary or
## Set item's (UniqueItems "look").
## Picking up, buying or wearing a piece unlocks its own look for every character of the account
## (GameState.wardrobe: group -> [look ids]); a unique's only once it's identified.

const ARMOUR := ["helmet", "shoulders", "chest", "gloves", "boots"]
const GROUPS := ["helmet", "shoulders", "chest", "gloves", "boots", "melee", "bow", "handxbow", "shield"]
const ROOT := "res://assets/gear/"

static var _catalogs := {}
static var _icons := {}


## A group's gear folder.
static func folder(group: String) -> String:
	return {"melee": "weapon", "bow": "weapon", "handxbow": "weapon", "shield": "offhand"}.get(group, group)


## The look group of a base ("" if it has no looks: jewellery, belts, flasks).
static func group_of_base(b: ItemBase) -> String:
	if b == null:
		return ""
	if b.slot in ARMOUR:
		return b.slot
	if b.slot == "offhand" and b.weapon_type == "shield":
		return "shield"
	if b.slot == "weapon":
		if b.weapon_type == "crossbow" and not b.two_handed:
			return "handxbow"  # held its own way (the hand crossbow rig)
		return "bow" if b.weapon_type in ["bow", "crossbow"] else "melee"
	return ""


static func group(it: ItemInstance) -> String:
	return group_of_base(it.base) if it != null else ""


## Whether an item can be given another look.
static func can_restyle(it: ItemInstance) -> bool:
	return group(it) != ""


## The art in a folder: id -> {name, group (weapons and shields), ...}.
static func catalog(folder_name: String) -> Dictionary:
	if not _catalogs.has(folder_name):
		var path := ROOT + folder_name + "/catalog.json"
		var res = load(path) if ResourceLoader.exists(path) else null
		_catalogs[folder_name] = res.data if res != null and res.data is Dictionary else {}
	return _catalogs[folder_name]


## Whether `id` is a look of `group`.
static func exists(grp: String, id: String) -> bool:
	if not grp in GROUPS:
		return false
	var e = catalog(folder(grp)).get(id)
	return e is Dictionary and (grp in ARMOUR or String(e.get("group", "")) == grp)


## Whether weapon art `id` is a bow's or crossbow's (drawn on the archer rig).
static func is_bow_art(id: String) -> bool:
	return exists("bow", id)


## What the art in a piece looks like it is: a unique's name, a base's name, or the art's own.
static func look_name(grp: String, id: String) -> String:
	var u := UniqueItems.with_look(id)
	if u != "":
		return UniqueItems.item_name(u)
	var b := LootGenerator.base_by_id(id)
	if b != null:
		return b.display_name
	return String(catalog(folder(grp)).get(id, {}).get("name", id.capitalize()))


static func icon(grp: String, id: String) -> Texture2D:
	var path := "%s%s/%s/icon.png" % [ROOT, folder(grp), id]
	if not _icons.has(path):
		_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _icons[path]


## The look an item has of its own: its unique's (once identified), else its base's.
static func own_look(it: ItemInstance) -> String:
	if it == null or it.base == null:
		return ""
	if it.is_unique() and it.identified:
		var u := UniqueItems.look_of(it.unique_id)
		if u != "":
			return u
	return it.base.id


## The look an item is drawn with: the one it was given, else its own.
static func look_of(it: ItemInstance) -> String:
	if it == null:
		return ""
	return it.look if it.look != "" else own_look(it)


static func unlocked(grp: String) -> Array:
	return GameState.wardrobe.get(grp, [])


static func has(grp: String, id: String) -> bool:
	return id in unlocked(grp)


## Unlocks the looks of these items; the newly unlocked ones as [[group, id]].
static func unlock(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if not it is ItemInstance:
			continue
		var grp := group(it)
		var id := own_look(it)
		if grp == "" or id == "" or not exists(grp, id) or has(grp, id):
			continue
		if not GameState.wardrobe.has(grp):
			GameState.wardrobe[grp] = []
		GameState.wardrobe[grp].append(id)
		out.append([grp, id])
	return out


## The wardrobe as saved, keeping only looks that still exist.
static func sanitize(d) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for grp in GROUPS:
			var ids = d.get(grp, [])
			if ids is Array:
				var keep: Array = []
				for id in ids:
					if id is String and exists(grp, id) and not id in keep:
						keep.append(id)
				out[grp] = keep
	return out
