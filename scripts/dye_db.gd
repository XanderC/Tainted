class_name DyeDB
extends RefCounted
## Dyes (paints) for helmets, body armour, gloves and boots, applied by the Dyer in Ashfall. A dye recolours a piece of
## gear's art, worn on a character and in the bag, keeping its shading and dark outlines (see
## SHADER). The icons are the CraftPix paint icons (tools/import_paints.py).
## An item remembers its dye (ItemInstance.dye, a DyeDB id); "" is its own colours.

## [id, name, colour], in the order they are shown: ten colours across in rows of bright, deep, muted.
const PALETTE := [
	["crimson", "Crimson", Color(0.85, 0.10, 0.12)], ["emerald", "Emerald", Color(0.12, 0.72, 0.25)],
	["sapphire", "Sapphire", Color(0.15, 0.25, 0.90)], ["jet", "Jet", Color(0.16, 0.16, 0.18)],
	["ivory", "Ivory", Color(0.93, 0.92, 0.88)], ["sunflower", "Sunflower", Color(1.00, 0.85, 0.10)],
	["rose", "Rose", Color(1.00, 0.25, 0.50)], ["amethyst", "Amethyst", Color(0.70, 0.15, 0.90)],
	["tangerine", "Tangerine", Color(1.00, 0.55, 0.10)], ["cyan", "Cyan", Color(0.10, 0.80, 0.85)],
	["blood", "Blood", Color(0.45, 0.05, 0.07)], ["forest", "Forest", Color(0.06, 0.38, 0.12)],
	["navy", "Navy", Color(0.08, 0.12, 0.50)], ["onyx", "Onyx", Color(0.06, 0.06, 0.08)],
	["silver", "Silver", Color(0.70, 0.72, 0.76)], ["amber", "Amber", Color(0.80, 0.55, 0.05)],
	["ruby", "Ruby", Color(0.80, 0.05, 0.30)], ["violet", "Violet", Color(0.45, 0.08, 0.65)],
	["ember", "Ember", Color(0.85, 0.30, 0.05)], ["teal", "Teal", Color(0.05, 0.45, 0.48)],
	["brick", "Brick", Color(0.65, 0.22, 0.20)], ["moss", "Moss", Color(0.38, 0.55, 0.25)],
	["steel", "Steel Blue", Color(0.30, 0.42, 0.65)], ["charcoal", "Charcoal", Color(0.28, 0.28, 0.30)],
	["ash", "Ash", Color(0.82, 0.84, 0.86)], ["olive", "Olive", Color(0.58, 0.55, 0.18)],
	["dusty_rose", "Dusty Rose", Color(0.75, 0.40, 0.50)], ["indigo", "Indigo", Color(0.30, 0.20, 0.55)],
	["copper", "Copper", Color(0.75, 0.45, 0.25)], ["sea", "Sea Green", Color(0.30, 0.65, 0.70)],
]
const COLUMNS := 10  ## colours across (a row of PALETTE)
## What dyeing a piece costs, in orbs (taking a dye off is free).
const PRICE := {"transmute": 1}
## Slots whose gear can be dyed: the armour you can see worn.
const SLOTS := ["helmet", "shoulders", "chest", "gloves", "boots"]

## Recolours art: shading and outlines stay, the colour is the dye's. Dark stays dark, the item's
## average brightness becomes the dye itself, and highlights go to a lighter shade of it. `mean_lum` is the art's
## own average brightness (DyeDB.mean_lum), so dark leather and bright steel come out alike.
const SHADER := """
shader_type canvas_item;
uniform vec3 dye : source_color = vec3(1.0);
uniform float mean_lum = 0.5;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp(l / max(mean_lum, 0.05) * 0.5, 0.0, 1.0);
	float dl = dot(dye, vec3(0.299, 0.587, 0.114));
	// Shadows go dark, the average is the dye, highlights a lighter shade of it (a dark dye stays dark)
	vec3 hi = clamp(dye * 1.45 + vec3(0.05), 0.0, 1.0);
	vec3 col = t < 0.5 ? dye * (t * 2.0) : mix(dye, hi, (t - 0.5) * 2.0);
	// the brightest glints (rivets, shine) stay whitish, less on a dark dye
	col = mix(col, vec3(1.0), smoothstep(0.85, 1.0, t) * 0.5 * clamp(dl * 2.0, 0.0, 1.0));
	COLOR = vec4(col, c.a) * tint;
}
"""

static var _shader: Shader
static var _lum := {}  # texture path -> mean brightness
static var _icons := {}


static func ids() -> Array:
	return PALETTE.map(func(d): return d[0])


static func info(id: String) -> Dictionary:
	for d in PALETTE:
		if d[0] == id:
			return {"id": d[0], "name": d[1], "color": d[2]}
	return {}


static func has(id: String) -> bool:
	return not info(id).is_empty()


static func dye_name(id: String) -> String:
	return String(info(id).get("name", ""))


static func color(id: String) -> Color:
	return info(id).get("color", Color.WHITE)


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://assets/icons/paints/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


## Whether `item` is dyed with a dye that exists.
static func dyed(item: ItemInstance) -> bool:
	return item != null and has(item.dye)


## The art's average brightness over the picture (not its transparent background), for SHADER.
static func mean_lum(tex: Texture2D) -> float:
	if tex == null:
		return 0.5
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _lum.has(key):
		return _lum[key]
	var img := tex.get_image()
	var m := 0.5
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var sum := 0.0
		var n := 0
		for y in 32:
			for x in 32:
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					sum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
					n += 1
		if n > 0:
			m = sum / n
	_lum[key] = m
	return m


## A material that draws `tex` in dye `id`, or null for no dye (draw it as it is).
static func material(id: String, tex: Texture2D) -> ShaderMaterial:
	if not has(id):
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("dye", color(id))
	m.set_shader_parameter("mean_lum", mean_lum(tex))
	return m
