class_name SkillIcons
extends RefCounted
## Painted icons for skills and support gems (assets/icons/skills/<id>.png, copied from the CraftPix
## skill icon packs by tools/import_skill_icons.py). null for an id with no icon yet, so callers can
## fall back to the drawn gem.

const DIR := "res://assets/icons/skills/"

static var _cache := {}


static func texture(id: String) -> Texture2D:
	if not _cache.has(id):
		var path := DIR + id + ".png"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]


## Draws `tex` filling a circle of radius `r` at `c` (the round HUD buttons), tinted by `tint`.
static func draw_round(ci: CanvasItem, tex: Texture2D, c: Vector2, r: float, tint := Color.WHITE) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var d := Vector2.from_angle(TAU * i / 40.0)
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	ci.draw_polygon(pts, PackedColorArray([tint]), uvs, tex)
