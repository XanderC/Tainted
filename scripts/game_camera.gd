class_name GameCamera
extends RefCounted
## The one camera every world scene uses (rift, zone, town, tutorial), so how far the world is drawn
## out is set in one place. Below 1.0 shows more of the map around you; ZOOM 0.75 is a third wider
## and taller than the engine's default view.
## Text that lives in the world (name plates, damage numbers) shrinks with it, so text() gives the
## size that reads as `px` on screen.

const ZOOM := 0.75


static func make() -> Camera2D:
	var cam := Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	return cam


## A world-space font size (or outline width) that looks `px` big on screen.
static func text(px: int) -> int:
	return int(round(float(px) / ZOOM))
