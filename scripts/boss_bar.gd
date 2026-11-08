class_name BossBar
extends Control
## The boss fight's top of screen: its name and title, a health bar with a notch where each phase
## begins, and what it shouts (say). When the boss wakes, its name comes up big in the middle of the
## screen for a moment. Shown while the boss is awake and alive; a follower's copy of the boss does as well
## (it has the host's life and wakefulness). Made by the scene's HUD; setup() gives it the boss.

var boss: Enemy
var def := {}

var _name: Label
var _title: Label
var _bar: Control
var _pct: Label
var _quote: Label
var _card: Label
var _card_sub: Label
var _carded := false
var _quote_tween: Tween


func _ready() -> void:
	add_to_group("boss_bar")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -290.0
	offset_right = 290.0
	offset_top = 8.0
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name = _outlined("", 24, Color(1.0, 0.82, 0.55))
	_name.add_theme_font_override("font", UIKit.title_font())
	box.add_child(_name)
	_title = _outlined("", 14, Color(0.85, 0.75, 0.65))
	box.add_child(_title)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(580, 20)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	_pct = _outlined("", 14, Color(1, 1, 1))
	_pct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.add_child(_pct)
	_quote = _outlined("", 17, Color(1.0, 0.9, 0.7))
	_quote.add_theme_font_override("font", UIKit.body_font(500, true))
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.modulate.a = 0.0
	box.add_child(_quote)

	# The name card, in the middle of the screen
	_card = _outlined("", 44, Color(1.0, 0.8, 0.5))
	_card.add_theme_font_override("font", UIKit.title_font())
	_card.add_theme_constant_override("outline_size", 10)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_card.offset_left = -400.0
	_card.offset_right = 400.0
	_card.offset_top = 180.0
	_card_sub = _outlined("", 20, Color(0.9, 0.75, 0.6))
	_card_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_sub.modulate.a = 0.0
	add_child(_card_sub)
	_card_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_card_sub.offset_left = -400.0
	_card_sub.offset_right = 400.0
	_card_sub.offset_top = 238.0


func _outlined(text: String, size: int, col: Color) -> Label:
	var l := UIKit.label(text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The boss it shows, and what BossDB says of it (`id`: its map id).
func setup(e: Enemy, id: String) -> void:
	boss = e
	def = BossDB.def(id)
	_carded = false
	_name.text = e.display_name
	_title.text = String(def.get("title", ""))


func _process(_delta: float) -> void:
	var live := is_instance_valid(boss) and not boss._dead and boss._aggro
	visible = live
	if not live:
		return
	if not _carded:
		_carded = true
		_show_card()
	# (100 * hp / max can come out a hair over 100 at full life, which ceil made 101%: divide first)
	_pct.text = "%d%%" % clampi(int(ceil(100.0 * (boss.hp / maxf(boss.max_hp, 1.0)) - 0.001)), 0, 100)
	_bar.queue_redraw()


func _show_card() -> void:
	_card.text = boss.display_name.to_upper()
	_card_sub.text = String(def.get("title", ""))
	for l in [_card, _card_sub]:
		l.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(l, "modulate:a", 1.0, 0.35)
		t.tween_interval(1.6)
		t.tween_property(l, "modulate:a", 0.0, 0.8)


## What the boss shouts: under its bar for a few seconds. (`who` is its name, for the log of the fight.)
func say(_who: String, text: String) -> void:
	if _quote == null:
		return
	_quote.text = "“%s”" % text
	_quote.modulate.a = 1.0
	if _quote_tween != null and _quote_tween.is_valid():
		_quote_tween.kill()
	_quote_tween = create_tween()
	_quote_tween.tween_interval(3.6)
	_quote_tween.tween_property(_quote, "modulate:a", 0.0, 1.0)


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	var frac := clampf(boss.hp / maxf(boss.max_hp, 1.0), 0.0, 1.0) if is_instance_valid(boss) else 0.0
	_bar.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.03, 0.03, 0.85))
	_bar.draw_rect(Rect2(2, 2, (w - 4) * frac, h - 4), Color(0.78, 0.12, 0.1))
	_bar.draw_rect(Rect2(2, 2, (w - 4) * frac, (h - 4) * 0.45), Color(1.0, 0.42, 0.3, 0.55))
	# A notch where each later phase begins
	for ph in def.get("phases", []):
		var at := float(ph.get("at", 1.0))
		if at < 0.999:
			var x := 2.0 + (w - 4.0) * at
			_bar.draw_line(Vector2(x, 0), Vector2(x, h), Color(0.95, 0.8, 0.45), 2.0)
	_bar.draw_rect(Rect2(0, 0, w, h), Color(0.75, 0.6, 0.35), false, 2.0)
