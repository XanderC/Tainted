class_name Pet
extends CharacterBody2D
## Your pet (PetDB): a small animal that trots along beside you and fetches the currency lying about
## (CurrencyPickup: orbs, shards, plans, runes, gems, bundles of them): it runs to what lies near you and
## takes it, and what it takes goes where tapping it would put it. Gear is left for you to choose, and
## so is a Town Portal scroll when you carry all you can. It has no life and no attack; enemies ignore
## it and it never blocks anything (walls only stop it). It keeps up with you through portals and leaps
## by catching up at once.
## Its art: one sprite sheet per animation (idle, walk, run: a row of frames, assets/pets/<id>), facing
## right and flipped for left. A pet with no walk (the bee and bird) hovers and bobs instead.

const FOLLOW_DIST := 130.0
const SPEED := 250.0        ## beside you at speed 1.0 (you run at about 220)
const FETCH_SPEED := 340.0
const SEEK := 750.0         ## fetches what lies this close to you
const TAKE_REACH := 46.0
const WARP := 1000.0        ## further from you than this it catches up at once
const SCAN_EVERY := 0.3
const GIVE_UP := 5.0        ## seconds on one fetch before it leaves that one alone for a while
const IGNORE_FOR := 25.0
const FPS := 18.0
const HOVER_LIFT := 34.0    ## how high a flyer floats above its shadow

var owner_player: Player
var id := ""

var _sprite: Sprite2D
var _meta := {}
var _sheets := {}  # "idle" / "walk" / "run" -> its texture
var _anim := ""
var _rate := 1.0
var _t := 0.0
var _hover := false
var _speed := 1.0
var _size := 62.0
var _target: CurrencyPickup = null
var _scan_t := 0.0
var _fetch_t := 0.0
var _warped := false
var _ignore := {}  # instance id of a pickup it could not reach -> seconds left


func _ready() -> void:
	add_to_group("pet")
	# Walls stop it; nothing bumps into it (it never blocks you, enemies or other things)
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 10.0
	shape.shape = c
	shape.position = Vector2(0, -4)
	add_child(shape)

	var info: Dictionary = PetDB.PETS[id]
	_hover = bool(info.get("hover", false))
	_speed = float(info.speed)
	_size = float(info.size)
	var dir := "res://assets/pets/%s/" % id
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "meta.json"))
	_meta = parsed if parsed is Dictionary else {"fw": 160, "fh": 120, "idle": 1, "walk": 0, "run": 0}
	for a in ["idle", "walk", "run"]:
		if int(_meta.get(a, 0)) > 0:
			_sheets[a] = load(dir + a + ".png")

	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # drawn small from big art
	var k := _size / PetDB.FRAME_LONG
	_sprite.scale = Vector2(k, k)
	# The origin is its feet (middle, bottom)
	_sprite.offset = Vector2(-float(_meta.fw) * 0.5, -float(_meta.fh))
	add_child(_sprite)
	_play("idle")
	_t = randf() * 3.0  # pets side by side don't move in step


func _draw() -> void:
	RigSprite.draw_shadow(self, _size * (0.30 if _hover else 0.36))


func _process(delta: float) -> void:
	if _sprite == null or _anim == "":
		return
	_t += delta
	var n := int(_meta.get(_anim, 1))
	_sprite.frame = int(_t * FPS * _rate) % maxi(n, 1)
	var y := 0.0
	if _hover:
		y = -HOVER_LIFT - sin(_t * 5.0) * 4.0
	_sprite.position.y = y


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_player):
		return
	if not _warped or global_position.distance_to(owner_player.global_position) > WARP:
		_warp_to_owner()
	for key in _ignore.keys():
		_ignore[key] -= delta
		if _ignore[key] <= 0.0:
			_ignore.erase(key)

	if not owner_player.dead:
		_scan_t -= delta
		if _target != null and (not is_instance_valid(_target) or _target.is_queued_for_deletion()):
			_target = null
		if _target == null and _scan_t <= 0.0:
			_scan_t = SCAN_EVERY
			_target = _find()
			_fetch_t = 0.0
		if _target != null:
			_fetch(delta)
			return
	_follow()


## The nearest thing lying near you that it may take.
func _find() -> CurrencyPickup:
	var best: CurrencyPickup = null
	var best_d := INF
	for c in get_tree().get_nodes_in_group("currency_pickups"):
		if not c is CurrencyPickup or c.is_queued_for_deletion() or _ignore.has(c.get_instance_id()):
			continue
		if not c.pet_can_take() or c.global_position.distance_to(owner_player.global_position) > SEEK:
			continue
		var d: float = c.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _fetch(delta: float) -> void:
	_fetch_t += delta
	if global_position.distance_to(_target.global_position) <= TAKE_REACH:
		var what := _target
		_target = null
		_cheer()
		what.take_by_pet(String(PetDB.PETS[id].name))
		return
	if _fetch_t > GIVE_UP:  # stuck behind something: leave that one for a while and come back to you
		_ignore[_target.get_instance_id()] = IGNORE_FOR
		_target = null
		_warp_to_owner()
		return
	_walk_to(_target.global_position, FETCH_SPEED * _speed, true)


func _follow() -> void:
	# A boss's ring has sealed with you inside and the pet out (or the other way round): it comes to you
	var arena := BossArena.current
	if arena != null and is_instance_valid(arena) and \
			(global_position.distance_to(arena.global_position) > arena.radius) != (owner_player.global_position.distance_to(arena.global_position) > arena.radius):
		global_position = owner_player.global_position
	var goal := owner_player.global_position + Vector2(FOLLOW_DIST * 0.6, FOLLOW_DIST * 0.4)
	var d := global_position.distance_to(goal)
	if d < 40.0:
		velocity = Vector2.ZERO
		_play("idle")
		return
	_walk_to(goal, SPEED * _speed * (1.4 if d > 280.0 else 1.0), d > 280.0)


## A little jump of pleasure at what it has just picked up.
func _cheer() -> void:
	var k := _size / PetDB.FRAME_LONG
	var t := create_tween()
	t.tween_property(_sprite, "scale", Vector2(k, k) * 1.3, 0.12)
	t.tween_property(_sprite, "scale", Vector2(k, k), 0.2)


## Beside you: when it first arrives in a scene, and whenever you get far ahead (a leap, a portal).
func _warp_to_owner() -> void:
	_warped = true
	var spot := owner_player.global_position + Vector2(FOLLOW_DIST * 0.6, FOLLOW_DIST * 0.4)
	var maze := _maze()
	if maze != null and maze.is_wall(maze.world_to_cell(spot)):
		spot = owner_player.global_position
	global_position = spot


func _maze() -> MazeMap:
	var scene := get_tree().current_scene
	return scene.get("maze") if scene != null else null


func _walk_to(goal: Vector2, spd: float, hurry: bool) -> void:
	var maze := _maze()
	var step := maze.path_next(global_position, goal) if maze != null else goal
	var move := step - global_position
	velocity = move.normalized() * spd if move.length() > 2.0 else Vector2.ZERO
	move_and_slide()
	if absf(move.x) > 1.0:
		_sprite.flip_h = move.x < 0.0
	_play(("run" if hurry else "walk") if velocity != Vector2.ZERO else "idle")


## Plays an animation: what it has, or the nearest it has (no run: the walk faster; no walk, as a flyer:
## the idle faster).
func _play(want: String) -> void:
	var name_ := want
	var rate := 1.0
	if name_ == "run" and not _sheets.has("run"):
		name_ = "walk"
		rate = 1.35
	if name_ == "walk" and not _sheets.has("walk"):
		name_ = "idle"
		rate = 1.5 if _hover else 1.0
	if name_ == "walk":
		rate *= clampf(_speed, 0.6, 1.2)  # a snail's feet go slowly too
	if name_ == _anim and is_equal_approx(rate, _rate):
		return
	if name_ != _anim:
		_anim = name_
		_sprite.texture = _sheets[_anim]
		_sprite.hframes = maxi(int(_meta.get(_anim, 1)), 1)
		_sprite.frame = 0
	_rate = rate
