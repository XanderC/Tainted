class_name MapTheme
extends RefCounted
## The looks a map can have (a map file's "theme"): the CraftPix 2D RPG tilesets imported into
## assets/tiles/<theme>/ by tools/import_tilesets.py, with the wall pieces it makes in walls/, and
## which of the theme's pictures dress a map.
## A prop or tile sprite is a picture name in the map's theme ("tree_3"), or "<theme>/<name>" to
## borrow one from another theme ("desert/decor_8", the covered wagon).

const ROOT := "res://assets/tiles/"
const DEFAULT := "desert"

## theme: what MazeMap scatters on its own ("auto_decorate"), and SceneryMap's random scenery.
##   wall_props:    along wall edges that face the floor (picture, scale)
##   floor_props:   now and then on the floor, walk-through (picture, scale)
##   plateau_props: in the middle of wide wall areas (picture, scale)
##   wall_chance, plateau_chance: how often a wall edge / a plateau's middle gets one
##   scatter:       SceneryMap: picture -> [scale, weight, blocker radius in px (0 = walk-through),
##                  base inset fraction]
const THEMES := {
	"desert": {
		"wall_props": [["tree_1", 0.5], ["tree_2", 0.5], ["tree_3", 0.5], ["tree_5", 0.5], ["tree_6", 0.5],
			["tree_9", 0.5], ["tree_10", 0.5], ["tree_12", 0.5], ["stones_5", 0.5], ["stones_6", 0.5],
			["stones_4", 0.5], ["greenery_1", 0.5], ["greenery_4", 0.5]],
		"floor_props": [["greenery_2", 0.45], ["greenery_6", 0.45], ["greenery_7", 0.45], ["greenery_10", 0.45],
			["stones_1", 0.45], ["stones_7", 0.45], ["stones_9", 0.45]],
		"plateau_props": [["stones_10", 0.3], ["stones_11", 0.3], ["stones_12", 0.3], ["tree_8", 0.5],
			["tree_9", 0.5], ["tree_7", 0.5]],
		"wall_chance": 0.45, "plateau_chance": 0.12,
		"scatter": {
			"tree_1": [0.5, 3, 14, 0.9], "tree_2": [0.5, 3, 12, 0.9], "tree_3": [0.5, 3, 12, 0.9],
			"tree_5": [0.5, 3, 12, 0.9], "tree_6": [0.5, 3, 12, 0.9], "tree_9": [0.5, 2, 16, 0.9],
			"tree_4": [0.5, 1, 8, 0.9], "tree_7": [0.5, 2, 22, 0.9], "tree_8": [0.5, 1, 30, 0.9],
			"tree_10": [0.5, 3, 12, 0.9], "tree_11": [0.5, 2, 10, 0.9], "tree_12": [0.5, 2, 12, 0.9],
			"greenery_1": [0.4, 3, 8, 0.93], "greenery_3": [0.4, 3, 10, 0.93], "greenery_4": [0.4, 3, 10, 0.93],
			"greenery_5": [0.4, 3, 8, 0.93], "greenery_9": [0.4, 2, 12, 0.93],
			"greenery_2": [0.5, 3, 0, 0.9], "greenery_7": [0.5, 2, 0, 0.9], "greenery_8": [0.5, 2, 0, 0.9],
			"greenery_6": [0.5, 6, 0, 0.9], "greenery_10": [0.5, 6, 0, 0.9],
			"stones_1": [0.5, 4, 0, 0.85], "stones_7": [0.5, 4, 0, 0.85], "stones_8": [0.5, 3, 0, 0.85],
			"stones_9": [0.5, 3, 0, 0.85], "stones_5": [0.5, 2, 24, 0.85], "stones_6": [0.5, 1, 30, 0.85],
			"stones_4": [0.5, 1, 30, 0.85],
			"decor_6": [0.5, 1, 0, 0.8],
		},
	},
	# Act 1: autumn woods (CraftPix 2D RPG Autumn Tileset). The plateaus are wooded hills.
	"woodland": {
		"wall_props": [["tree_1", 0.55], ["tree_2", 0.55], ["tree_3", 0.55], ["tree_4", 0.55], ["tree_6", 0.55],
			["tree_7", 0.55], ["tree_8", 0.55], ["tree_9", 0.55], ["tree_10", 0.55], ["tree_11", 0.5], ["stones_1", 0.5], ["stones_6", 0.5], ["greenery_9", 0.5],
			["greenery_1", 0.5]],
		"floor_props": [["greenery_2", 0.45], ["greenery_3", 0.45], ["greenery_5", 0.45], ["greenery_6", 0.45],
			["greenery_7", 0.45], ["greenery_8", 0.45], ["tree_13", 0.45], ["tree_14", 0.45], ["tree_15", 0.45],
			["stones_4", 0.4]],
		"plateau_props": [["tree_1", 0.6], ["tree_2", 0.6], ["tree_6", 0.6], ["tree_8", 0.6], ["tree_9", 0.6],
			["tree_10", 0.55], ["tree_12", 0.55], ["stones_5", 0.5]],
		"wall_chance": 0.6, "plateau_chance": 0.4,
		"scatter": {
			"tree_1": [0.55, 3, 14, 0.9], "tree_2": [0.55, 3, 14, 0.9], "tree_3": [0.55, 3, 10, 0.9],
			"tree_4": [0.55, 3, 10, 0.9], "tree_5": [0.55, 2, 8, 0.9], "tree_6": [0.55, 3, 12, 0.9],
			"tree_7": [0.55, 3, 10, 0.9], "tree_8": [0.55, 4, 10, 0.9], "tree_9": [0.55, 4, 10, 0.9],
			"tree_10": [0.5, 3, 10, 0.9], "tree_11": [0.5, 1, 12, 0.9], "tree_12": [0.5, 1, 18, 0.9],
			"tree_13": [0.5, 2, 0, 0.85], "tree_14": [0.5, 2, 0, 0.85], "tree_15": [0.5, 2, 0, 0.85],
			"greenery_1": [0.5, 3, 0, 0.9], "greenery_2": [0.5, 4, 0, 0.9], "greenery_3": [0.5, 4, 0, 0.9],
			"greenery_4": [0.5, 3, 0, 0.9], "greenery_5": [0.5, 4, 0, 0.9], "greenery_6": [0.5, 3, 0, 0.9],
			"greenery_7": [0.5, 4, 0, 0.9], "greenery_8": [0.5, 4, 0, 0.9], "greenery_9": [0.5, 2, 14, 0.9],
			"stones_1": [0.5, 1, 22, 0.85], "stones_2": [0.5, 2, 18, 0.85], "stones_3": [0.5, 2, 16, 0.85],
			"stones_4": [0.5, 3, 0, 0.85], "stones_5": [0.5, 1, 30, 0.85], "stones_6": [0.5, 2, 16, 0.85],
		},
	},
}


static func data(theme: String) -> Dictionary:
	return THEMES.get(theme, THEMES[DEFAULT])


## The folder of a theme's pictures.
static func dir(theme: String) -> String:
	return ROOT + (theme if THEMES.has(theme) else DEFAULT) + "/"


## The file of a picture: `sprite` in `theme`, or "<theme>/<name>" from another theme.
static func sprite_path(theme: String, sprite: String) -> String:
	if "/" in sprite:
		return ROOT + sprite + ".png"
	return dir(theme) + sprite + ".png"


static func load_sprite(theme: String, sprite: String) -> Texture2D:
	if sprite == "":
		return null
	var path := sprite_path(theme, sprite)
	return load(path) if ResourceLoader.exists(path) else null
