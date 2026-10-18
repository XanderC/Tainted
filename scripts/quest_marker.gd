class_name QuestMarker
extends Node2D
## A gold "!" (has a quest for you) or "?" (a quest to hand in or talk about) over an NPC's head.

var npc_id := ""
var _mark := ""
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	var m := Quests.npc_marker(npc_id)
	if m != _mark or m != "":
		_mark = m
		queue_redraw()


func _draw() -> void:
	if _mark == "":
		return
	var f := ThemeDB.fallback_font
	var y := sin(_t * 3.0) * 4.0
	var col := Color(1.0, 0.82, 0.25) if _mark == "!" else Color(0.55, 1.0, 0.6)
	draw_string_outline(f, Vector2(-20, y), _mark, HORIZONTAL_ALIGNMENT_CENTER, 40, 40, 8, Color(0, 0, 0, 0.9))
	draw_string(f, Vector2(-20, y), _mark, HORIZONTAL_ALIGNMENT_CENTER, 40, 40, col)
