class_name Changelog
extends RefCounted
## What changed in each update (res://changelog.json, newest first: [{build, title, notes: [..]}]). It
## travels in every patch, so a game that has just updated can say what is new: a window shows once
## after an update (show_if_new) and from the build number on the start screen (show). The newest
## entry is written with build 0 until the update is published (publish_update.ps1 stamps its build).

const FILE := "res://changelog.json"
const SEEN := "user://changelog.cfg"  # the newest build whose changes this player has seen


static func entries() -> Array:
	if not FileAccess.file_exists(FILE):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	return d if d is Array else []


## Opens the window the first time this build runs after an update (not on a fresh install).
static func show_if_new(parent: Control) -> void:
	if Updater.build <= 0:
		return
	var cfg := ConfigFile.new()
	var seen := 0
	if cfg.load(SEEN) == OK:
		seen = int(cfg.get_value("changelog", "seen", 0))
	if seen == Updater.build:
		return
	cfg.set_value("changelog", "seen", Updater.build)
	cfg.save(SEEN)
	if Updater.patched and seen > 0:
		show(parent, seen)


## The window: every change (since build `since`, if given) with the newest first.
static func show(parent: Control, since := 0) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.window_box(18, Color.WHITE, true))
	panel.custom_minimum_size = Vector2(minf(560.0, parent.size.x - 40.0), 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIKit.label("What's new", 24, UIKit.GOLD))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(380.0, parent.size.y - 150.0))
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	var shown := 0
	for e in entries():
		var b := int(e.get("build", 0))
		if since > 0 and b != 0 and b <= since:
			continue
		var head := String(e.get("title", ""))
		list.add_child(UIKit.label(head if b == 0 else "%s  (build %d)" % [head, b], 16, UIKit.GOLD))
		for n in e.get("notes", []):
			list.add_child(UIKit.label("• " + String(n), 14, Color(0.9, 0.88, 0.82), true))
		shown += 1
	if shown == 0:
		list.add_child(UIKit.label("Nothing new yet.", 14, UIKit.TEXT_DIM))
	var close := UIKit.button("Close", Color(0.16, 0.12, 0.08), Color(0.95, 0.80, 0.30), Vector2(0, 46), 16)
	close.pressed.connect(shade.queue_free)
	box.add_child(close)
