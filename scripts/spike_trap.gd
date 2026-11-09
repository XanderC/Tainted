class_name SpikeTrap
extends Node2D
## Spikes that rise from the Grand Ossuary's floor (a map "trap" object): sunk and quiet, then a warning as the stone
## shivers and the points show, then up for a moment, and the player standing over them is hurt, once per rising.
## Each trap keeps its own time (its position sets where in the cycle it starts), so a hallway of them is a rhythm to learn.

const CYCLE := 3.4
const QUIET := 1.9     # sunk
const WARN := 0.6      # shivering, the points just showing
const UP := 0.55       # risen; the hit lands as they come up
const REACH := 78.0
const HIT := 0.14      # of the victim's maximum Life, before armour

var theme := "crypt"
var _hole: Texture2D
var _spikes: Texture2D
var _hurt := false
var _offset := 0.0


func _ready() -> void:
	z_index = -1
	_hole = MapTheme.load_sprite(theme, "crypt/decor_31")
	_spikes = MapTheme.load_sprite(theme, "crypt/decor_33")
	_offset = fposmod(position.x * 0.0071 + position.y * 0.0113, 1.0) * CYCLE


func _t() -> float:
	return fposmod(Time.get_ticks_msec() / 1000.0 + _offset, CYCLE)


## How far the spikes are out: 0 sunk .. 1 up.
func rise() -> float:
	var t := _t()
	if t < QUIET:
		return 0.0
	if t < QUIET + WARN:
		return 0.25 + 0.1 * sin(t * 40.0)
	if t < QUIET + WARN + UP:
		return 1.0
	return 0.0


func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p) or p.global_position.distance_to(global_position) > 900.0:
		return
	queue_redraw()
	var up := rise() >= 1.0
	if not up:
		_hurt = false
	elif not _hurt and p.global_position.distance_to(global_position) < REACH and not p.dead:
		_hurt = true
		p.take_damage(float(p.stats.get_stat("max_life")) * HIT)


func _draw() -> void:
	if _hole != null:
		var hs := Vector2(_hole.get_size()) * 0.6
		draw_texture_rect(_hole, Rect2(-hs / 2.0, hs), false)
	var r := rise()
	if _spikes != null and r > 0.0:
		var s := Vector2(_spikes.get_size()) * 0.5
		# The points come up out of the hole: only the top part of the row shows at first
		var shown := s.y * r
		var src := Rect2(0, _spikes.get_height() * (1.0 - r), _spikes.get_width(), _spikes.get_height() * r)
		draw_texture_rect_region(_spikes, Rect2(-s.x / 2.0, s.y * 0.3 - shown, s.x, shown), src, Color(1, 0.8, 0.8) if r < 1.0 else Color.WHITE)
