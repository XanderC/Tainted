class_name MiniDungeons
extends RefCounted
## The spawning mini-dungeons of Act I (ACT1_DESIGN.md): now and then (not every visit) one of the open zones has a way down off the
## beaten track, a trapdoor, a cave mouth or a stone grate, to a small place of its own (each a zone: ActDB "mini_*", and what
## happens in it is MiniDungeon). Not in the towns, the Ossuary or the Sepulcher, and not in a party's zone.
##   Rot-Damp Cellar    - a root cellar swarming with blood maggots, and a mimic chest on a hoard
##   Forgotten Bone Pit - bone-strewn caverns; the centre shuts you in with an elite skeleton champion
##   Hermit's Sanctum   - a quiet cave with an abandoned crafting bench: one free reroll
##   Weeping Fissure    - black, crowded, a Tainted Chest chained to its elite guardians
## Going down starts the place afresh; coming up puts you back at the entrance, in the zone as you left it.

const CHANCE := 0.4  # per fresh visit to a zone that can have one
const ZONES := ["dune_wastes", "weeping_hollow", "sunken_fen", "ashen_verge"]
const DUNGEONS := ["mini_cellar", "mini_bonepit", "mini_sanctum", "mini_fissure"]
const LOOKS := {
	"mini_cellar": {"label": "Rot-Damp Cellar", "prompt": "Lift the trapdoor to the Rot-Damp Cellar", "art": "trapdoor"},
	"mini_bonepit": {"label": "Forgotten Bone Pit", "prompt": "Climb down into the Forgotten Bone Pit", "art": "cave"},
	"mini_sanctum": {"label": "Hermit's Sanctum", "prompt": "Enter the Hermit's Sanctum", "art": "cave"},
	"mini_fissure": {"label": "Weeping Fissure", "prompt": "Descend into the Weeping Fissure", "art": "grate"},
}


## Rolls whether this zone has an entrance (`force` names a dungeon to have), and places it away from `keep_away` (the encounter's spot).
## Returns the entrance (an Interactable), or null.
static func roll(zone: Zone, keep_away := Vector2(INF, INF), force := "") -> Interactable:
	if not zone.zone_id in ZONES:
		return null
	if force == "" and randf() >= CHANCE:
		return null
	var dungeon := force if force != "" else String(DUNGEONS[randi() % DUNGEONS.size()])
	var also: Array = []
	if keep_away.is_finite():
		also.append(keep_away)
	var at := ZoneEncounters.spot(zone, also)
	if not at.is_finite():
		return null
	return place(zone, dungeon, at)


static func place(zone: Zone, dungeon: String, at: Vector2) -> Interactable:
	var look: Dictionary = LOOKS[dungeon]
	var it := Interactable.new()
	it.position = at
	it.prompt = String(look.prompt)
	it.radius = 150.0
	it.set_meta("dungeon", dungeon)
	it.set_meta("visited", false)
	zone.add_child(it)
	var art := Node2D.new()
	art.z_index = -1
	art.draw.connect(func(): _draw_entrance(art, String(look.art)))
	it.add_child(art)
	zone._label(it, String(look.label), Color(0.85, 0.8, 0.95), -90.0)
	it.action = func():
		var visited: bool = it.get_meta("visited")
		it.set_meta("visited", true)
		zone.enter_mini(dungeon, it.global_position, visited)
	return it


static func _draw_entrance(n: Node2D, art: String) -> void:
	match art:
		"trapdoor":  # wooden planks in the ground, an iron ring
			n.draw_rect(Rect2(-62, -34, 124, 68), Color(0.2, 0.12, 0.07))
			for i in 5:
				n.draw_rect(Rect2(-58 + i * 24, -30, 22, 60), Color(0.42, 0.28, 0.15) if i % 2 else Color(0.38, 0.25, 0.13))
			n.draw_arc(Vector2(0, 0), 11.0, 0.0, TAU, 20, Color(0.7, 0.7, 0.75), 4.0)
			n.draw_rect(Rect2(-62, -34, 124, 68), Color(0.08, 0.05, 0.03), false, 4.0)
		"cave":  # a dark mouth in a heap of stone
			n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.7))
			n.draw_circle(Vector2(0, 0), 86.0, Color(0.30, 0.29, 0.31))
			n.draw_circle(Vector2(0, 4), 62.0, Color(0.04, 0.03, 0.05))
			n.draw_set_transform(Vector2.ZERO)
			for i in 7:
				var a := PI + PI * float(i) / 6.0
				n.draw_circle(Vector2.from_angle(a) * 74.0 * Vector2(1.0, 0.7) + Vector2(0, -6), 15.0, Color(0.42, 0.41, 0.44))
		"grate":  # iron bars over a red glow
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 400.0)
			n.draw_rect(Rect2(-56, -40, 112, 80), Color(0.5, 0.05, 0.1, 0.5 + 0.25 * pulse))
			n.draw_rect(Rect2(-56, -40, 112, 80), Color(0.15, 0.15, 0.17), false, 6.0)
			for i in 6:
				n.draw_line(Vector2(-46 + i * 18.0, -38), Vector2(-46 + i * 18.0, 38), Color(0.3, 0.3, 0.33), 4.0)
