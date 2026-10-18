class_name Appearance
extends RefCounted
## How a character looks, picked when creating it: gender, face, hairstyle and colour, facial hair
## and colour, skin tone and starter outfit. Stored as a plain Dictionary (saved with the
## character); the art is in assets/appearance, made by tools/build_appearance.py, which cuts the
## hair and beards out of the CraftPix heads so any style goes with any colour.

const DIR := "res://assets/appearance/"
const NONE := ""  # no hair (bald) / no facial hair

const HAIR_COLORS := {
	"black": Color(0.20, 0.18, 0.18), "dark_brown": Color(0.36, 0.24, 0.16), "brown": Color(0.55, 0.36, 0.22),
	"auburn": Color(0.62, 0.24, 0.12), "ginger": Color(0.90, 0.45, 0.18), "blond": Color(1.0, 0.84, 0.45),
	"ash": Color(0.78, 0.72, 0.60), "grey": Color(0.62, 0.62, 0.64), "white": Color(0.98, 0.98, 1.0),
	"raven_blue": Color(0.26, 0.32, 0.52),
}
## The skin colour itself (the head and hands art is divided by its own skin colour, "fair")
const SKIN_TONES := {
	"pale": Color(0.95, 0.80, 0.68), "fair": Color(0.859, 0.722, 0.592), "tan": Color(0.76, 0.58, 0.42),
	"brown": Color(0.58, 0.40, 0.27), "dark": Color(0.40, 0.27, 0.19),
}
const GENDERS := ["male", "female"]

static var _data := {}
static var _tex := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var res = load(DIR + "appearance.json")
		_data = res.data if res != null else {"hair": [], "beards": [], "faces": [], "outfits": []}
	return _data


## Option ids for `kind` ("hair", "beards", "faces", "outfits"); faces only of `gender`.
## Hair and beards start with NONE (bald / clean-shaven).
static func options(kind: String, gender := "") -> Array:
	var out: Array = []
	if kind in ["hair", "beards"]:
		out.append(NONE)
	for o in data().get(kind, []):
		if kind == "faces" and gender != "" and o.get("gender", "") != gender:
			continue
		out.append(String(o["id"]))
	return out


static func label(kind: String, id: String) -> String:
	if id == NONE:
		return "Bald" if kind == "hair" else "None"
	for o in data().get(kind, []):
		if o["id"] == id:
			return String(o["label"])
	return id.capitalize()


static func default_look(gender := "male") -> Dictionary:
	var female := gender == "female"
	return {
		"gender": gender,
		"face": "bright" if female else "stern",
		"hair": "bob" if female else "short",
		"hair_color": "brown",
		"beard": NONE,
		"beard_color": "brown",
		"skin": "fair",
		"outfit": "dress" if female else "peasant",
	}


static func random_look(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var g: String = GENDERS[rng.randi() % 2]
	var pick := func(a: Array): return a[rng.randi() % a.size()]
	var look := default_look(g)
	look["face"] = pick.call(options("faces", g))
	look["hair"] = pick.call(options("hair").slice(1))  # always some hair
	look["hair_color"] = pick.call(HAIR_COLORS.keys())
	look["beard"] = pick.call(options("beards")) if g == "male" and rng.randf() < 0.6 else NONE
	look["beard_color"] = look["hair_color"]
	look["skin"] = pick.call(SKIN_TONES.keys())
	look["outfit"] = pick.call(options("outfits"))
	return look


## `look` with anything missing or unknown replaced by the default (old saves, removed options).
static func sanitize(look) -> Dictionary:
	var g: String = look.get("gender", "male") if look is Dictionary else "male"
	if g not in GENDERS:
		g = "male"
	var out := default_look(g)
	if not (look is Dictionary):
		return out
	for k in ["face", "hair", "beard", "outfit"]:
		var kind: String = {"face": "faces", "hair": "hair", "beard": "beards", "outfit": "outfits"}[k]
		var v := String(look.get(k, out[k]))
		if v in options(kind, g if k == "face" else ""):
			out[k] = v
	for k in ["hair_color", "beard_color"]:
		if HAIR_COLORS.has(look.get(k, "")):
			out[k] = look[k]
	if SKIN_TONES.has(look.get("skin", "")):
		out["skin"] = look["skin"]
	return out


static func _t(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(DIR + path + ".png") if ResourceLoader.exists(DIR + path + ".png") else null
	return _tex[path]


## Dress `rig` as `look`: the bald head and hands in the skin tone, the face, the hair and beard
## layers in their colours (the eyebrows take the hair colour), and the outfit's body, arms and legs.
static func apply(rig: RigSprite, look: Dictionary) -> void:
	if rig == null or rig.rig == null:
		return
	look = sanitize(look)
	var parts := {"Head": _t("base_" + String(look["gender"])),
		"Left Hand": _t("hands/Left Hand"), "Right Hand": _t("hands/Right Hand")}
	var brows := {}
	for n in ["01", "02", "03"]:
		parts["Face " + n] = _t("face/%s/Face %s" % [look["face"], n])
		brows["Face " + n] = _t("face/%s/Brows %s" % [look["face"], n])
	for p in ["Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]:
		parts[p] = _t("outfit/%s/%s" % [look["outfit"], p])
	for k in parts.keys():
		if parts[k] == null:
			parts.erase(k)
	rig.set_part_overrides(parts)
	var skin: Color = SKIN_TONES[look["skin"]]
	rig.set_object_tints({"Head": skin, "Left Hand": skin, "Right Hand": skin})
	var hair_col: Color = HAIR_COLORS[look["hair_color"]]
	var layers: Array = [{"obj": "Face 01", "by_file": brows, "tint": hair_col}]
	if look["beard"] != NONE:
		var b := _t("beard/" + String(look["beard"]))
		layers.append({"obj": "Head", "by_file": {"Head": b}, "tint": HAIR_COLORS[look["beard_color"]], "order": 0})
	if look["hair"] != NONE:
		var h := _t("hair/" + String(look["hair"]))
		layers.append({"obj": "Head", "by_file": {"Head": h}, "tint": hair_col, "order": 1, "hair": true})
	rig.set_look_layers(layers)
