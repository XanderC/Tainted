class_name SkillTreeCanvas
extends Control
## Draws the passive tree (PassiveTree graph) and lets you pan (drag), zoom (mouse wheel, pinch, or
## the zoom buttons) and tap nodes (node_selected). Allocated nodes and the links between them are
## gold; nodes you can take next are outlined green. The rest are tinted by the attribute they lean
## to (Strength red, Dexterity green, Vitality pink, Energy blue), and each branch is named.

signal node_selected(node_id: String)

const GOLD := Color(0.95, 0.78, 0.30)
const REACH := Color(0.40, 0.85, 0.45)
const DARK := Color(0.32, 0.29, 0.34)
const RADIUS := {"start": 30.0, "keystone": 26.0, "notable": 19.0, "small": 11.0}
const MIN_ZOOM := 0.18
const MAX_ZOOM := 1.8

var class_id := "warrior"
var selected_id := ""
var zoom := 0.8
var pan := Vector2.ZERO  # screen offset of the tree's centre from the view's centre

var _press := false
var _press_pos := Vector2.ZERO
var _moved := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func rebuild() -> void:
	queue_redraw()


func center() -> void:
	pan = Vector2.ZERO
	queue_redraw()


func zoom_by(factor: float, at: Vector2 = Vector2(-1, -1)) -> void:
	if at.x < 0.0:
		at = size * 0.5
	var before := _to_tree(at)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	pan += at - _to_screen(before)  # keep the point under the cursor still
	queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + pan + p * zoom


func _to_tree(s: Vector2) -> Vector2:
	return (s - size * 0.5 - pan) / zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_by(1.12, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_by(1.0 / 1.12, event.position)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press = true
					_press_pos = event.position
					_moved = 0.0
				else:
					if _press and _moved < 12.0:
						var hit := _node_at(event.position)
						if hit != "":
							node_selected.emit(hit)
					_press = false
		accept_event()
	elif event is InputEventMouseMotion and _press:
		pan += event.relative
		_moved += event.relative.length()
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
		accept_event()


func _node_at(screen_pos: Vector2) -> String:
	var tree := PassiveTree.get_tree(class_id)
	var best := ""
	var best_d := INF
	for id in tree.nodes:
		var n: Dictionary = tree.nodes[id]
		var d := _to_screen(n.pos).distance_to(screen_pos)
		var r: float = maxf(RADIUS[n.kind] * zoom, 16.0) + 6.0  # generous touch target
		if d < r and d < best_d:
			best_d = d
			best = id
	return best


## The attribute a node leans to: the one it gives the most of, or by what it does; "" for none.
static func node_attribute(n: Dictionary) -> String:
	var best := ""
	var most := 0
	for k in Attributes.KEYS:
		if int(n.stats.get(k, 0)) > most:
			most = int(n.stats.get(k, 0))
			best = k
	if best != "":
		return best
	for k in n.stats:
		match String(k):
			"attack_inc", "power_max", "execute", "rampage", "no_decay", "no_crit":
				return "str"
			"crit", "attack_speed_inc", "move_inc", "bow_inc":
				return "dex"
			"life_flat", "life_inc", "armor_inc", "regen", "thorns", "blood_magic", "res_all", "res_fire", "res_cold", \
					"res_lightning", "res_chaos":
				return "vit"
			"spell_inc", "mana_max", "mana_regen_inc", "cost_red", "mana_shield", "gem_level":
				return "ene"
	return ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.04, 0.06))
	var tree := PassiveTree.get_tree(class_id)
	var nodes: Dictionary = tree.nodes
	# the branches' names, out past their keystones
	var font0 := ThemeDB.fallback_font
	for b in PassiveTree.BRANCHES:
		var at := _to_screen(Vector2(b.dir) * 760.0)
		var fs0 := int(clampf(20.0 * zoom, 11.0, 24.0))
		var txt := String(Attributes.NAMES[b.key]).to_upper()
		draw_string_outline(font0, at + Vector2(-120, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 240, fs0, 5, Color.BLACK)
		draw_string(font0, at + Vector2(-120, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 240, fs0, Attributes.COLORS[b.key].lightened(0.1))
	# links
	for id in nodes:
		var n: Dictionary = nodes[id]
		var a_on := GameState.is_node_allocated(id)
		for l in n.links:
			if String(l) < String(id):
				continue  # draw each link once
			var b_on := GameState.is_node_allocated(String(l))
			var col := GOLD if a_on and b_on else (REACH.darkened(0.35) if a_on or b_on else DARK)
			draw_line(_to_screen(n.pos), _to_screen(nodes[l].pos), col, (5.0 if a_on and b_on else 3.0) * clampf(zoom, 0.6, 1.2))
	# nodes
	var font := ThemeDB.fallback_font
	for id in nodes:
		var n: Dictionary = nodes[id]
		var c := _to_screen(n.pos)
		if c.x < -60 or c.y < -60 or c.x > size.x + 60 or c.y > size.y + 60:
			continue
		var r: float = RADIUS[n.kind] * zoom
		var on := GameState.is_node_allocated(id)
		var reach := not on and GameState.node_block_reason(id) in ["", "No passive points"]
		var lean := node_attribute(n)
		var tint: Color = Attributes.COLORS[lean].darkened(0.45) if lean != "" else DARK
		var border := GOLD if on else (REACH if reach else tint)
		var fill := Color(0.35, 0.24, 0.08) if on else (Color(0.10, 0.09, 0.12).lerp(tint, 0.25) if lean != "" else Color(0.10, 0.09, 0.12))
		if n.kind == "start":
			fill = Color(0.30, 0.10, 0.08)
		draw_circle(c, r, fill)
		draw_arc(c, r, 0.0, TAU, 32, border, 3.0)
		if n.kind == "keystone":
			draw_arc(c, r + 5.0 * zoom, 0.0, TAU, 40, border, 2.0)
		elif n.kind == "notable":
			draw_arc(c, r - 5.0 * zoom, 0.0, TAU, 28, border.darkened(0.2), 1.5)
		if on:
			draw_circle(c, r * 0.35, GOLD.lightened(0.2))
		if id == selected_id:
			draw_arc(c, r + 9.0 * zoom, 0.0, TAU, 40, Color.WHITE, 2.5)
		# names of the big nodes
		if n.kind != "small" and zoom >= 0.5:
			var fs := int(clampf(13.0 * zoom, 10.0, 16.0))
			var label: String = "✦ START" if n.kind == "start" else n.name
			draw_string_outline(font, c + Vector2(-90, r + 16.0), label, HORIZONTAL_ALIGNMENT_CENTER, 180, fs, 4, Color.BLACK)
			draw_string(font, c + Vector2(-90, r + 16.0), label, HORIZONTAL_ALIGNMENT_CENTER, 180, fs,
				GOLD if on else Color(0.85, 0.80, 0.72))
