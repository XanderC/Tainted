class_name GameCamera
extends RefCounted
## The one camera every world scene uses (rift, zone, town, tutorial), so how far the world is drawn
## out is set in one place. Below 1.0 shows more of the map around you. The player picks it in the
## Options window (OptionsUI), between MIN_ZOOM and MAX_ZOOM; DEFAULT_ZOOM 0.75 is a third wider and
## taller than the engine's default view. It is kept on the device (Options).
## Text that lives in the world (name plates, damage numbers) shrinks with it, so text() gives the
## size that reads as `px` on screen. Text already on screen keeps its size until the next area.

const MIN_ZOOM := 0.5
const MAX_ZOOM := 1.0
const DEFAULT_ZOOM := 0.75
const STEP := 0.05
const GROUP := "game_camera"

static var _zoom := -1.0


## The zoom in use (1.0 = the engine's default view; less shows more).
static func zoom() -> float:
	if _zoom < 0.0:
		_zoom = clampf(float(Options.get_value("view", "zoom", DEFAULT_ZOOM)), MIN_ZOOM, MAX_ZOOM)
	return _zoom


## Zooms every camera now, without saving it (a slider being dragged).
static func apply_zoom(z: float) -> void:
	_zoom = clampf(snappedf(z, 0.01), MIN_ZOOM, MAX_ZOOM)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for c in tree.get_nodes_in_group(GROUP):
			(c as Camera2D).zoom = Vector2(_zoom, _zoom)


## Zooms every camera now and keeps it for next time.
static func set_zoom(z: float) -> void:
	apply_zoom(z)
	save()


static func save() -> void:
	Options.set_value("view", "zoom", zoom())


static func make() -> Camera2D:
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom(), zoom())
	cam.add_to_group(GROUP)
	return cam


## A world-space font size (or outline width) that looks `px` big on screen.
static func text(px: int) -> int:
	return int(round(float(px) / zoom()))
