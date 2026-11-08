class_name PetDB
extends RefCounted
## The pets a character can have, and putting yours in the scene. A pet is just for show and for
## fetching currency (Pet): it has no stats and takes no part in a fight. Which one a character has is
## GameState.pet ("" = none), chosen in the Options window (OptionsUI) and kept with the character.
## A pet's art is a sprite sheet per animation (assets/pets/<id>, made from the CraftPix animal packs by
## tools/import_pets.py): add one with a line in PETS, a line in that tool's table and a run of it.

## The longer side of a pet's stored frames, in pixels (tools/import_pets.py STORE_LONG).
const FRAME_LONG := 160.0

## id: name, size (the longer side as drawn, in pixels; the player is about 100 tall), speed (how fast
## it goes beside you, 1.0 about your pace), hover (flies: it floats above its shadow, bobbing, and has
## only the one animation).
const PETS := {
	"hedgehog": {"name": "Hedgehog", "size": 74, "speed": 1.0},
	"snail": {"name": "Snail", "size": 74, "speed": 0.6},
	"turtle": {"name": "Turtle", "size": 82, "speed": 0.75},
	"boar": {"name": "Boar", "size": 104, "speed": 1.1},
	"monkey": {"name": "Monkey", "size": 98, "speed": 1.0},
	"mouse": {"name": "Mouse", "size": 86, "speed": 1.15},
	"crab": {"name": "Crab", "size": 80, "speed": 0.95},
	"bee": {"name": "Bee", "size": 66, "speed": 1.25, "hover": true},
	"bird": {"name": "Bird", "size": 76, "speed": 1.2, "hover": true},
}
## The order the Options window steps through them in; "" is no pet.
const ORDER := ["", "hedgehog", "snail", "turtle", "boar", "monkey", "mouse", "crab", "bee", "bird"]

static var node: Pet = null  ## the pet in the current scene, if any


static func name_of(id: String) -> String:
	return String(PETS[id].name) if PETS.has(id) else "None"


## The next pet in ORDER from `id`, `by` steps on (negative: back), wrapping round.
static func step(id: String, by: int) -> String:
	var i := ORDER.find(id)
	return ORDER[posmod(i + by, ORDER.size())]


## Puts the character's pet in the player's scene (beside them), if they have one; the one there is
## replaced. Not in the tutorial. The pet changes with GameState.pet_changed (the Options window).
static func spawn(player: Player) -> void:
	if is_instance_valid(node):
		node.queue_free()
	node = null
	if player == null or not PETS.has(GameState.pet) or GameState.tutorial_stage != GameState.TUTORIAL_DONE:
		return
	var parent := player.get_parent()
	if parent == null:
		return
	var p := Pet.new()
	p.owner_player = player
	p.id = GameState.pet
	p.position = player.position + Vector2(70, 40)
	node = p
	parent.add_child.call_deferred(p)


## Keeps `player`'s scene's pet in step with GameState.pet while the player is there.
static func follow_choice(player: Player) -> void:
	var cb := func(): spawn(player)
	GameState.pet_changed.connect(cb)
	player.tree_exiting.connect(func(): GameState.pet_changed.disconnect(cb))
