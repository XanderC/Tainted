extends Node2D
## Screenshots of the two random encounters in the Ashwood (scratch/enc_cottage.png, enc_ritual.png).
## Needs a window:  godot --path . --resolution 1280x720 res://scratch/capture_encounters.tscn


func shot(n: String) -> void:
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/enc_%s.png" % n))


func _ready() -> void:
	GameState.tutorial_stage = GameState.TUTORIAL_DONE
	GameState.current_zone = "dune_wastes"
	GameState.zone_entry = "start"
	var zone: Zone = load("res://scenes/zone.tscn").instantiate()
	add_child(zone)
	for i in 6:
		await get_tree().process_frame
	for e in zone.get_children().filter(func(n): return n is ZoneEncounters):
		e.queue_free()
	var cot := ZoneEncounters.roll(zone, "cottage")
	zone.player.global_position = cot.pos + Vector2(0, 520)
	await shot("cottage")
	zone.player.global_position = cot.pos + Vector2(0, 300)
	await shot("cottage_open")
	cot.queue_free()
	var rit := ZoneEncounters.roll(zone, "ritual")
	zone.player.global_position = rit.pos + Vector2(0, 520)
	await shot("ritual")
	get_tree().quit()
