class_name IconFactory
extends RefCounted
## Procedural placeholder icons so every item has its own distinct picture until real art exists.
## Each icon is a silhouette (by slot / rune category) tinted with the item's colour and stamped
## with a mark derived from its id, so no two items look the same. Textures are cached.

const SIZE := 64

static var _cache := {}


## Icon for a gear base (used only when the base has no art of its own).
static func item_icon(id: String, slot: String, col: Color) -> Texture2D:
	var key := "item:" + id
	if not _cache.has(key):
		_cache[key] = _render(id, "gear_" + slot, col)
	return _cache[key]


static func rune_icon(r: RuneDef) -> Texture2D:
	var painted := SkillIcons.texture(r.id)  # support gems with a painted icon
	if painted != null:
		return painted
	var key := "rune:" + r.id
	if not _cache.has(key):
		var shape := "rune_form"
		match r.category:
			RuneDef.Category.TRANSMUTATION: shape = "rune_trans"
			RuneDef.Category.MODIFIER: shape = "rune_mod"
		_cache[key] = _render(r.id, shape, r.color)
	return _cache[key]


## Gems grow larger with tier so Chipped vs Perfect is visible at a glance.
static func gem_icon(id: String, col: Color, tier: int) -> Texture2D:
	if id.begins_with("skill:"):  # a skill gem shows its skill's painted icon
		var painted := SkillIcons.texture(id.trim_prefix("skill:"))
		if painted != null:
			return painted
	var key := "gem:" + id
	if not _cache.has(key):
		_cache[key] = _render(id, "gem_t%d" % tier, col)
	return _cache[key]


## A rune (SocketRune): a rounded stone with a carved glyph unique to the rune.
static func socket_rune_icon(id: String, col: Color) -> Texture2D:
	var key := "srune:" + id
	if not _cache.has(key):
		_cache[key] = _render(id, "socket_rune", col)
	return _cache[key]


static func recipe_icon(id: String) -> Texture2D:
	var key := "recipe:" + id
	if not _cache.has(key):
		_cache[key] = _render(id, "scroll", Color(0.92, 0.82, 0.58))
	return _cache[key]


## A Scroll of Town Portal (the Merchant's): a page in the portal's blue.
static func scroll_icon() -> Texture2D:
	if not _cache.has("town_portal"):
		var path := "res://assets/icons/materials/portal_scroll.png"  # (tools/import_currency_icons.py)
		_cache["town_portal"] = load(path) if ResourceLoader.exists(path) else _render("town_portal", "scroll", Color(0.62, 0.80, 1.0))
	return _cache["town_portal"]


## Round flask; bigger bottle for higher tiers.
static func potion_icon(id: String, col: Color, tier: int) -> Texture2D:
	var key := "potion:" + id
	if not _cache.has(key):
		_cache[key] = _render(id, "potion_t%d" % tier, col)
	return _cache[key]


static func material_icon(id: String, col: Color) -> Texture2D:
	var key := "mat:" + id
	if not _cache.has(key):
		_cache[key] = _render(id, "material", col)
	return _cache[key]


static func skill_icon_color(id: String) -> Color:
	return Color.from_hsv(float(absi(id.hash()) % 360) / 360.0, 0.55, 0.9)


# ---------- rendering ----------

static func _render(id: String, shape: String, col: Color) -> ImageTexture:
	var h := absi(id.hash())
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var mask := PackedByteArray()
	mask.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) / SIZE * 2.0 - 1.0, (y + 0.5) / SIZE * 2.0 - 1.0)
			mask[y * SIZE + x] = 1 if _inside(shape, id, p) else 0

	var light := col.lightened(0.25)
	var dark := col.darkened(0.45)
	var accent := Color.from_hsv(fmod(col.h + 0.5, 1.0), 0.55, 0.95)
	for y in SIZE:
		for x in SIZE:
			if mask[y * SIZE + x] == 0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Outline where a neighbour is empty
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE or mask[ny * SIZE + nx] == 0:
					edge = true
					break
			if edge:
				img.set_pixel(x, y, dark)
			else:
				img.set_pixel(x, y, col.lerp(light, float(y) / SIZE))

	_stamp_mark(img, mask, h, accent)
	return ImageTexture.create_from_image(img)


## A small id-derived mark (1-4 dots in a pattern) so same-shaped items still differ.
static func _stamp_mark(img: Image, mask: PackedByteArray, h: int, accent: Color) -> void:
	var count := 1 + (h % 4)
	var pattern := (h / 4) % 3
	var cx := 32 + ((h / 12) % 9) - 4
	var cy := 32 + ((h / 108) % 9) - 4
	for i in count:
		var ox := 0
		var oy := 0
		match pattern:
			0: ox = (i - count / 2) * 7
			1: oy = (i - count / 2) * 7
			2:
				ox = (i - count / 2) * 6
				oy = (i - count / 2) * 6
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy > 5:
					continue
				var px: int = cx + ox + dx
				var py: int = cy + oy + dy
				if px < 0 or py < 0 or px >= SIZE or py >= SIZE:
					continue
				if mask[py * SIZE + px] == 1:
					img.set_pixel(px, py, accent)


static func _rect(p: Vector2, x0: float, x1: float, y0: float, y1: float) -> bool:
	return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1


static func _rot(p: Vector2, deg: float) -> Vector2:
	return p.rotated(deg_to_rad(deg))


static func _inside(shape: String, id: String, p: Vector2) -> bool:
	if shape.begins_with("potion_t"):
		var r := 0.48 + 0.07 * float(shape.substr(8).to_int())
		var bulb := Vector2(p.x, p.y - 0.25).length() < r
		var neck := _rect(p, -0.16, 0.16, -0.75, 0.0)
		var cork := _rect(p, -0.22, 0.22, -0.92, -0.72)
		return bulb or neck or cork
	if shape.begins_with("gem_t"):
		var r := 0.40 + 0.11 * float(shape.substr(5).to_int())
		return maxf(maxf(absf(p.x), absf(p.y)), (absf(p.x) + absf(p.y)) * 0.75) < r
	match shape:
		"gear_offhand":
			# Heater shield: flat top, pointed bottom, with a boss
			var w := 0.75 if p.y < 0.1 else 0.75 * (1.0 - (p.y - 0.1) / 0.8)
			var body := p.y > -0.8 and p.y < 0.9 and absf(p.x) < w
			var boss := Vector2(p.x, p.y + 0.1).length() < 0.16
			return body and not (Vector2(p.x, p.y + 0.1).length() < 0.24 and not boss)
		"gear_weapon":
			if id.contains("mace") or id.contains("maul"):
				var q := _rot(p, 40.0)
				var head := Vector2(q.x, q.y + 0.5).length() < (0.42 if id.contains("maul") else 0.32)
				return head or _rect(q, -0.07, 0.07, -0.5, 0.85)
			if id.contains("staff"):
				var q := _rot(p, 35.0)
				return _rect(q, -0.06, 0.06, -0.8, 0.9) or Vector2(q.x, q.y + 0.82).length() < 0.16
			if id.contains("bow"):
				var r := Vector2(p.x + 0.35, p.y).length()
				var arc := r > 0.72 and r < 0.84 and p.x > -0.35
				var string := absf(p.x + 0.35) < 0.03 and absf(p.y) < 0.78
				return arc or string
			if id.contains("dagger"):
				var q := _rot(p, 45.0)
				return _rect(q, -0.09, 0.09, -0.55, 0.25) or _rect(q, -0.28, 0.28, 0.25, 0.35) or _rect(q, -0.06, 0.06, 0.35, 0.65)
			if id.contains("axe"):
				var q := _rot(p, 40.0)
				if _rect(q, -0.07, 0.07, -0.85, 0.85):
					return true
				var in_head := Vector2(q.x - 0.28, q.y + 0.45).length() < 0.42
				var cut := Vector2(q.x + 0.02, q.y + 0.45).length() < 0.38
				return in_head and not cut
			var s := _rot(p, 45.0)
			return _rect(s, -0.12, 0.12, -0.9, 0.35) or _rect(s, -0.4, 0.4, 0.35, 0.47) \
				or _rect(s, -0.07, 0.07, 0.47, 0.78) or Vector2(s.x, s.y - 0.86).length() < 0.13
		"gear_helmet":
			var dome := p.x * p.x + (p.y + 0.1) * (p.y + 0.1) < 0.62 and p.y < 0.35
			var brim := _rect(p, -0.8, 0.8, 0.35, 0.52)
			var slit := _rect(p, -0.5, 0.5, 0.08, 0.2)
			return (dome or brim) and not slit
		"gear_chest":
			var body := absf(p.x) < 0.5 + p.y * 0.12 and p.y > -0.7 and p.y < 0.85
			var shoulders := _rect(p, -0.88, 0.88, -0.72, -0.4)
			var neck := Vector2(p.x, p.y + 0.72).length() < 0.24
			return (body or shoulders) and not neck
		"gear_gloves":
			var palm := _rect(p, -0.42, 0.42, -0.1, 0.72)
			var fingers := false
			for i in 4:
				var fx := -0.36 + i * 0.24
				fingers = fingers or _rect(p, fx - 0.08, fx + 0.08, -0.72, -0.1)
			var thumb := _rect(_rot(p, 25.0), -0.75, -0.42, -0.05, 0.3)
			return palm or fingers or thumb
		"gear_boots":
			var leg := _rect(p, -0.38, 0.08, -0.8, 0.35)
			var foot := _rect(p, -0.38, 0.8, 0.3, 0.72) or Vector2(p.x - 0.8, p.y - 0.51).length() < 0.21
			return leg or foot
		"gear_ring":
			var d := Vector2(p.x, p.y - 0.2).length()
			var band := d > 0.42 and d < 0.66
			var gem := Vector2(p.x, p.y + 0.55).length() < 0.22
			return band or gem
		"gear_amulet":
			var chain := absf(absf(p.x) - (0.7 - (p.y + 0.85) * 0.5)) < 0.06 and p.y > -0.85 and p.y < -0.05
			var pend := Vector2(p.x, p.y - 0.4).length() < 0.42
			var core := Vector2(p.x, p.y - 0.4).length() < 0.16
			return (chain or pend) and not core
		"gear_belt":
			# A strap with a square buckle
			var strap := _rect(p, -0.95, 0.95, -0.22, 0.22)
			var buckle := _rect(p, -0.34, 0.34, -0.42, 0.42)
			var hole := _rect(p, -0.2, 0.2, -0.28, 0.28)
			return (strap or buckle) and not hole
		"rune_trans":
			return absf(p.x) + absf(p.y) < 0.88
		"rune_form":
			return maxf(absf(p.x) * 0.866 + absf(p.y) * 0.5, absf(p.y)) < 0.82
		"rune_mod":
			return p.length() < 0.82
		"socket_rune":
			# A rounded stone tablet with a glyph cut into it: a stave plus two strokes picked
			# by the rune's id, so every rune reads differently.
			var stone := absf(p.x) < 0.62 and absf(p.y) < 0.82 \
				and Vector2(maxf(absf(p.x) - 0.36, 0.0), maxf(absf(p.y) - 0.56, 0.0)).length() < 0.26
			var h := absi(id.hash())
			var stave := absf(p.x) < 0.06 and absf(p.y) < 0.55
			var a1 := _rot(p, 35.0 + float(h % 4) * 25.0)
			var a2 := _rot(p, -35.0 - float((h / 4) % 4) * 25.0)
			var y1 := -0.3 + float((h / 16) % 3) * 0.25
			var stroke1 := absf(a1.x) < 0.05 and absf(a1.y - y1) < 0.28 and p.x > -0.02
			var stroke2 := absf(a2.x) < 0.05 and absf(a2.y + y1 * 0.6) < 0.28 and p.x < 0.02
			return stone and not (stave or stroke1 or stroke2)
		"scroll":
			# Parchment with rolled ends
			var sheet := _rect(p, -0.55, 0.55, -0.62, 0.62)
			var rolls := _rect(p, -0.7, 0.7, -0.78, -0.6) or _rect(p, -0.7, 0.7, 0.6, 0.78)
			return sheet or rolls
		"material":
			# Chunky crystal
			return absf(p.x) < 0.55 - maxf(0.0, p.y) * 0.55 and p.y > -0.85 and p.y < 0.8 \
				and absf(p.x) < 0.9 - absf(p.y + 0.1) * 0.55
	# Fallback: rounded square
	return absf(p.x) < 0.8 and absf(p.y) < 0.8
