class_name Interactable
extends Node2D
## Something in town you can walk up to and tap "Talk" on: an NPC or the dungeon gate.

var prompt := "Talk"
var radius := 130.0
var action: Callable


func _ready() -> void:
	add_to_group("interactables")
