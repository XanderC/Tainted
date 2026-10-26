class_name HirelingPortrait
extends Control
## Your hireling at the top left of the HUD, Diablo II style: its face (its own figure, close up,
## helmet and all), name and level, life bar and its two flasks' cooldowns. Fallen, it shows grey
## with a skull. Tap it to open its equipment (the inventory's Hireling tab). Hidden with no hireling.

const SIZE := Vector2(250, 64)
const FACE := 58.0

var on_open: Callable  ## opens the Hireling tab

var _face_box: Panel
var _rig: RigSprite
var _look_key := ""  # what the face was drawn as, to redraw it when the hireling changes


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Your hireling: tap to open their equipment"
	_face_box = Panel.new()
	_face_box.clip_contents = true
	_face_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_box.position = Vector2(3, 3)
	_face_box.size = Vector2(FACE, FACE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.10)
	_face_box.add_theme_stylebox_override("panel", sb)
	add_child(_face_box)


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
		or (event is InputEventScreenTouch and not event.pressed)
	if tapped and Hirelings.has() and on_open.is_valid():
		accept_event()
		on_open.call()


func _process(_delta: float) -> void:
	visible = Hirelings.has()
	if not visible:
		return
	_update_face()
	queue_redraw()


## Its figure, scaled up so its head fills the frame: rebuilt when a different hireling (or other gear) shows.
func _update_face() -> void:
	var h := GameState.hireling
	var helm: ItemInstance = GameState.hireling_gear.get("helmet")
	var key := "%s|%s|%s|%s" % [String(h.get("name", "")), String(h.get("skin", "")), str(h.get("look", {})),
		(Wardrobe.look_of(helm) + helm.dye) if helm != null else ""]
	if key == _look_key and _rig != null:
		_rig.modulate = Color(0.45, 0.45, 0.45) if not Hirelings.alive() else Color.WHITE
		return
	_look_key = key
	if _rig != null:
		_rig.queue_free()
	_rig = RigSprite.new()
	_rig.base_scale = 0.21
	_rig.weapon_from_gear = true
	var skin := String(h.get("skin", ""))
	if skin != "":
		_rig.skin = skin
	_face_box.add_child(_rig)
	if skin == "":
		Appearance.apply(_rig, h.get("look", Appearance.default_look()))
		_rig.set_gear("helmet", Wardrobe.look_of(helm) if helm != null else "", helm.dye if helm != null else "")
	_rig.position = Vector2(FACE * 0.5 - 2.0, FACE * 0.5 + 54.0)  # feet far below: the whole head sits in the frame
	_rig.set_facing(1.0)
	_rig.play_loop("Idle")


func _draw() -> void:
	if not Hirelings.has():
		return
	var alive := Hirelings.alive()
	# Backing plate and the face's frame
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.06, 0.05, 0.06, 0.78))
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.62, 0.50, 0.30, 0.95), false, 2.0)
	draw_rect(Rect2(Vector2(2, 2), Vector2(FACE + 2, FACE + 2)), Color(0.85, 0.70, 0.40), false, 2.0)
	var x0 := FACE + 12.0
	var w := SIZE.x - x0 - 8.0
	var h := GameState.hireling
	var title := "%s  Lv %d" % [String(h.get("name", "")), Hirelings.level()]
	HudArt.label(self, Vector2(x0, 20), title, 15, Color(0.65, 0.95, 0.70) if alive else Color(0.75, 0.70, 0.65), w, HORIZONTAL_ALIGNMENT_LEFT)
	if not alive:
		HudArt.label(self, Vector2(FACE * 0.5 - 12, FACE * 0.5 + 12), "☠", 26, Color(0.95, 0.85, 0.80), 30)
		HudArt.label(self, Vector2(x0, 44), "Fallen: revive in town", 13, Color(0.95, 0.50, 0.45), w, HORIZONTAL_ALIGNMENT_LEFT)
		return
	# Life bar
	var node := Hirelings.node
	var frac := 1.0
	if is_instance_valid(node):
		frac = node.hp / maxf(node.stats.get_stat("max_life"), 1.0)
	var bar := Rect2(x0, 28, w, 11)
	draw_rect(bar.grow(1.5), Color(0.02, 0.02, 0.02, 0.9))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0.0, 1.0), bar.size.y)), Color(0.30, 0.80, 0.35))
	# Its flasks: icon, darkened from the top while cooling down
	for i in Hirelings.FLASK_SLOTS:
		var r := Rect2(x0 + i * 22.0, 43, 16, 18)
		var f := Hirelings.flask(i)
		if f == null:
			draw_rect(r, Color(0.25, 0.22, 0.25, 0.6), false, 1.0)
			continue
		draw_texture_rect(f.base.icon, r, false)
		var cd := node.flask_cooldown_fraction(i) if is_instance_valid(node) else 0.0
		if cd > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * cd)), Color(0, 0, 0, 0.65))
