class_name PartyUI
extends Node
## Parties on screen, wherever you are (Net owns it, so it lasts across scenes):
##  - the party list, top right under the menu buttons: each other member's name, level, life and
##    whereabouts, the leader crowned; tap one for their card. "Leave" under it.
##  - an invite: "Brom invites you to their party", Join / No (it lapses after Net.INVITE_TIMEOUT).
##  - a party rift opened by a member: "Brom opened Rift 3", Join / Not now; while it's open the
##    party list has a Join button too, for whoever said not now or came later.
##  - a player's card (show_card): name, level, class, and Invite / Make leader / Remove as fits.
##  - short notices from the server ("Kael joined the party").
##  - friends (on a server that keeps characters): "★ Friends n/m" at the top of the list opens them
##    (online first, with where they are, Invite to party and Remove); a friend request asks like an
##    invite; a player's card has Add friend.
## Hidden while offline and on the character select screen.

const ROW_W := 236.0
const LIFE := Color(0.85, 0.18, 0.15)

var _frame_layer: CanvasLayer
var _pop_layer: CanvasLayer
var _frame: VBoxContainer
var _rows := {}  # member id -> {"life": ColorRect, "where": Label, "dead": Label}
var _invite_box: PanelContainer
var _invites: Array = []  # [{"id", "name", "at"}], [{"portal": {...}, "at"}] or [{"friend": id, "name", "at"}]
var _friends_win: PanelContainer
var _card: PanelContainer
var _card_id := 0
var _toast: Label


func _ready() -> void:
	_frame_layer = CanvasLayer.new()
	_frame_layer.layer = 6
	add_child(_frame_layer)
	_pop_layer = CanvasLayer.new()
	_pop_layer.layer = 30  # over the menus: an invite can come while the bag is open
	add_child(_pop_layer)

	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation", 4)
	_frame.anchor_left = 1.0
	_frame.anchor_right = 1.0
	_frame.offset_left = -ROW_W - 16.0
	_frame.offset_right = -16.0
	_frame.offset_top = 84.0
	_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # anything wider grows leftwards, onto the screen
	_frame_layer.add_child(_frame)

	_toast = UIKit.label("", 16, Color(0.85, 0.95, 1.0))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 52.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop_layer.add_child(_toast)

	Net.party_changed.connect(func():
		if Net.in_party():  # in a party now (however the invite was answered): other invites lapse
			var n := _invites.size()
			_invites = _invites.filter(func(i): return i.has("portal"))
			if _invites.size() != n:
				_show_invite()
		_rebuild())
	Net.party_vitals.connect(_on_vitals)
	Net.invited.connect(_on_invited)
	Net.party_portal.connect(_on_portal)
	Net.trade_changed.connect(func(state):
		if not state.is_empty():  # a trade is open: other trade asks lapse
			var n := _invites.size()
			_invites = _invites.filter(func(i): return not i.has("trade"))
			if _invites.size() != n:
				_show_invite())
	Net.trade_asked.connect(func(from_id, from_name):
		_invites.append({"trade": from_id, "name": from_name, "at": Time.get_ticks_msec()})
		_show_invite())
	Net.friend_asked.connect(func(from_id, from_name):
		_invites.append({"friend": from_id, "name": from_name, "at": Time.get_ticks_msec()})
		_show_invite())
	Net.friends_changed.connect(func():
		_rebuild()
		if _friends_win != null:
			_show_friends())
	Net.notice.connect(say)
	Net.status_changed.connect(func():
		if not Net.online():
			_invites.clear()
			_show_invite()
			_close_card()
		_rebuild())


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var show := Net.online() and scene != null and not scene is CharacterSelect
	_frame_layer.visible = show
	_pop_layer.visible = show
	# A rift you're in already needs no asking
	if not _invites.is_empty() and _invites[0].has("portal") and Net.instance == String(_invites[0].portal.inst):
		_drop_portal_asks()
	# Invites run out
	if not _invites.is_empty() and Time.get_ticks_msec() - int(_invites[0].at) > Net.INVITE_TIMEOUT * 1000.0:
		_invites.pop_front()
		_show_invite()


## A short line at the top of the screen for a few seconds.
func say(text: String) -> void:
	_toast.text = text
	get_tree().create_timer(4.0, true, false, true).timeout.connect(func():
		if is_instance_valid(_toast) and _toast.text == text:
			_toast.text = ""
	)


# ---------- the party list ----------

func _rebuild() -> void:
	UIKit.clear(_frame)
	_rows.clear()
	if Net.accounts:
		var on := Net.friends.filter(func(f): return f.online).size()
		var fb := UIKit.button("★  Friends  %d / %d" % [on, Net.friends.size()], Color(0.16, 0.14, 0.10), Color(0.85, 0.75, 0.45), Vector2(ROW_W, 32), 13)
		fb.pressed.connect(func():
			if _friends_win != null:
				_close_friends()
			else:
				_show_friends())
		_frame.add_child(fb)
	if not Net.in_party():
		return
	var me := Net.my_id()
	var head := HBoxContainer.new()
	_frame.add_child(head)
	var title := UIKit.label("PARTY  %d / %d" % [Net.party.members.size(), Net.PARTY_MAX], 14, UIKit.GOLD)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var leave := UIKit.button("Leave", Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30), Vector2(70, 28), 12)
	leave.pressed.connect(Net.leave_party)
	head.add_child(leave)
	var portal: Dictionary = Net.party.get("portal", {})
	if not portal.is_empty() and Net.instance != String(portal.inst):
		var join := UIKit.button("🌀  Join %s's Rift %d" % [portal.by_name, int(portal.level)],
			Color(0.20, 0.10, 0.30), Color(0.85, 0.55, 1.0), Vector2(ROW_W, 40), 14)
		join.pressed.connect(func(): Net.join_portal(Net.party.get("portal", {})))
		_frame.add_child(join)
	for m in Net.party.members:
		if int(m.id) != me:
			_frame.add_child(_row(m))
	for a in Net.party.get("away", []):  # dropped: their place is kept a while
		var row := _row({"id": -1, "name": a.name, "level": a.level})
		row.modulate = Color(1, 1, 1, 0.5)
		row.disabled = true
		_frame.add_child(row)
		(_rows[-1].where as Label).text = "Reconnecting..."
		_rows.erase(-1)


func _row(m: Dictionary) -> Control:
	var id := int(m.id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(ROW_W, 64)
	b.clip_contents = true
	var face := UIKit.tooltip_box()
	face.set_content_margin_all(0.0)  # the row's own margins (below) place what is in it
	b.add_theme_stylebox_override("normal", face)
	b.add_theme_stylebox_override("hover", face)
	b.add_theme_stylebox_override("pressed", face)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(show_card.bind(id))
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 18 if side in ["left", "right"] else 6)
	b.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var lead := "👑 " if int(Net.party.leader) == id else ""
	var n := UIKit.label("%s%s" % [lead, m.name], 14, RemotePlayer.NAME_COLOR)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.clip_text = true
	top.add_child(n)
	var lv := UIKit.label("Lv %d" % int(m.level), 13, UIKit.TEXT_DIM)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(lv)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.10, 0.06, 0.06)
	bar_bg.custom_minimum_size = Vector2(0, 7)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar_bg)
	var life := ColorRect.new()
	life.color = LIFE
	life.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life.anchor_bottom = 1.0
	life.anchor_right = 1.0
	bar_bg.add_child(life)
	var where := UIKit.label("", 12, UIKit.TEXT_DIM)
	where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	where.clip_text = true
	v.add_child(where)
	_rows[id] = {"life": life, "where": where}
	return b


func _on_vitals(batch: Dictionary) -> void:
	for id in batch:
		if _rows.has(id):
			var h := clampf(float(batch[id].get("h", 1.0)), 0.0, 1.0)
			_rows[id].life.anchor_right = h
			var w := String(batch[id].get("w", ""))
			_rows[id].where.text = ("☠ Dead  •  " if h <= 0.0 else "") + (w if w != "" else "Choosing a character")


# ---------- invites ----------

## A member opened a party rift: ask (unless it's yours: you're on your way in).
func _on_portal(portal: Dictionary) -> void:
	if int(portal.get("by", 0)) == Net.my_id():
		return
	_invites = _invites.filter(func(i): return not i.has("portal"))
	_invites.append({"portal": portal, "at": Time.get_ticks_msec()})
	_show_invite()


func _on_invited(from_id: int, from_name: String) -> void:
	_invites = _invites.filter(func(i): return i.get("id", 0) != from_id)
	_invites.append({"id": from_id, "name": from_name, "at": Time.get_ticks_msec()})
	_show_invite()


## The oldest open invite, or none.
func _show_invite() -> void:
	if _invite_box != null:
		_invite_box.queue_free()
		_invite_box = null
	if _invites.is_empty():
		return
	var inv: Dictionary = _invites[0]
	if inv.has("portal"):
		_show_portal_ask(inv.portal)
		return
	if inv.has("friend"):
		_show_friend_ask(inv)
		return
	if inv.has("trade"):
		_show_trade_ask(inv)
		return
	_invite_box = PanelContainer.new()
	_invite_box.add_theme_stylebox_override("panel", UIKit.window_box(16))
	_invite_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_invite_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invite_box.offset_top = 90.0
	_pop_layer.add_child(_invite_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_invite_box.add_child(v)
	var l := UIKit.label("⚔  %s invites you to their party" % inv.name, 18, Color(0.92, 0.90, 0.84))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var id: int = inv.id
	var yes := UIKit.button("Join", Color(0.14, 0.34, 0.18), Color(0.40, 1.0, 0.55), Vector2(140, 46), 17)
	yes.pressed.connect(func(): _answer(id, true))
	row.add_child(yes)
	var no := UIKit.button("No thanks", Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30), Vector2(140, 46), 17)
	no.pressed.connect(func(): _answer(id, false))
	row.add_child(no)


func _show_portal_ask(portal: Dictionary) -> void:
	_invite_box = PanelContainer.new()
	_invite_box.add_theme_stylebox_override("panel", UIKit.window_box(16))
	_invite_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_invite_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invite_box.offset_top = 90.0
	_pop_layer.add_child(_invite_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_invite_box.add_child(v)
	var l := UIKit.label("🌀  %s opened a Rift (level %d)" % [portal.by_name, int(portal.level)], 18, Color(0.88, 0.72, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var yes := UIKit.button("Join", Color(0.20, 0.10, 0.30), Color(0.85, 0.55, 1.0), Vector2(140, 46), 17)
	yes.pressed.connect(func():
		_drop_portal_asks()
		Net.join_portal(portal))
	row.add_child(yes)
	var no := UIKit.button("Not now", Color(0.16, 0.14, 0.18), Color(0.50, 0.45, 0.50), Vector2(140, 46), 17)
	no.pressed.connect(_drop_portal_asks)
	row.add_child(no)


func _show_trade_ask(inv: Dictionary) -> void:
	_invite_box = PanelContainer.new()
	_invite_box.add_theme_stylebox_override("panel", UIKit.window_box(16))
	_invite_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_invite_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invite_box.offset_top = 90.0
	_pop_layer.add_child(_invite_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_invite_box.add_child(v)
	var l := UIKit.label("🤝  %s wants to trade" % inv.name, 18, Color(0.85, 0.95, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var id: int = inv.trade
	for pair in [["Trade", true, Color(0.14, 0.34, 0.18), Color(0.40, 1.0, 0.55)], ["No thanks", false, Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30)]]:
		var b := UIKit.button(pair[0], pair[2], pair[3], Vector2(140, 46), 17)
		var yes: bool = pair[1]
		b.pressed.connect(func():
			Net.answer_trade(id, yes)
			_invites = _invites.filter(func(i): return i.get("trade", 0) != id)
			_show_invite())
		row.add_child(b)


func _show_friend_ask(inv: Dictionary) -> void:
	_invite_box = PanelContainer.new()
	_invite_box.add_theme_stylebox_override("panel", UIKit.window_box(16))
	_invite_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_invite_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invite_box.offset_top = 90.0
	_pop_layer.add_child(_invite_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_invite_box.add_child(v)
	var l := UIKit.label("★  %s wants to be friends" % inv.name, 18, Color(0.95, 0.85, 0.55))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var id: int = inv.friend
	for pair in [["Accept", true, Color(0.14, 0.34, 0.18), Color(0.40, 1.0, 0.55)], ["No thanks", false, Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30)]]:
		var b := UIKit.button(pair[0], pair[2], pair[3], Vector2(140, 46), 17)
		var yes: bool = pair[1]
		b.pressed.connect(func():
			Net.answer_friend(id, yes)
			_invites = _invites.filter(func(i): return i.get("friend", 0) != id)
			_show_invite())
		row.add_child(b)


# ---------- friends ----------

func _show_friends() -> void:
	_close_friends()
	_friends_win = PanelContainer.new()
	_friends_win.add_theme_stylebox_override("panel", UIKit.window_box(18, Color.WHITE, true))
	_friends_win.custom_minimum_size = Vector2(440, 0)
	_friends_win.set_anchors_preset(Control.PRESET_CENTER)
	_friends_win.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_friends_win.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pop_layer.add_child(_friends_win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_friends_win.add_child(v)
	UIKit.window_header(v, "FRIENDS", Color(0.95, 0.85, 0.55), _close_friends, 20)
	if Net.friends.is_empty():
		v.add_child(UIKit.label("No friends yet. Walk up to a player, tap Talk, then Add friend.", 15, UIKit.TEXT_DIM, true))
	for f in Net.friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UIKit.label(("●  " if f.online else "○  ") + String(f.name), 16,
			Color(0.55, 1.0, 0.6) if f.online else UIKit.TEXT_DIM))
		info.add_child(UIKit.label(String(f.where) if f.online and String(f.where) != "" else ("Online" if f.online else "Offline"), 12, UIKit.TEXT_DIM))
		var fid := int(f.id)
		var acc := String(f.account)
		if f.online and not Net.is_member(fid) and (not Net.in_party() or Net.is_leader()):
			var inv := UIKit.button("Invite", Color(0.12, 0.26, 0.40), Color(0.50, 0.80, 1.0), Vector2(84, 38), 13)
			inv.pressed.connect(func(): Net.invite(fid))
			row.add_child(inv)
		var rm := UIKit.button("Remove", Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30), Vector2(84, 38), 13)
		rm.pressed.connect(func(): Net.unfriend(acc))
		row.add_child(rm)


func _close_friends() -> void:
	if _friends_win != null:
		_friends_win.queue_free()
		_friends_win = null


func _drop_portal_asks() -> void:
	_invites = _invites.filter(func(i): return not i.has("portal"))
	_show_invite()


func _answer(id: int, accept: bool) -> void:
	Net.answer_invite(id, accept)
	_invites = _invites.filter(func(i): return i.get("id", 0) != id)
	if accept:
		_invites = _invites.filter(func(i): return i.has("portal"))  # in a party now: other invites lapse
	_show_invite()


# ---------- a player's card ----------

## A player's card: who they are, and what you can do (invite, or as leader make leader / remove).
func show_card(id: int) -> void:
	_close_card()
	var info: Dictionary = Net.others.get(id, {})
	if info.is_empty() and Net.in_party():
		for m in Net.party.members:
			if int(m.id) == id:
				info = m
	if info.is_empty():
		return
	_card_id = id
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UIKit.window_box(18))
	_card.custom_minimum_size = Vector2(340, 0)
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pop_layer.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var cd := ClassLibrary.get_class_def(String(info.get("class", "warrior")))
	var t := UIKit.label(String(info.get("name", "?")), 22, RemotePlayer.NAME_COLOR)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UIKit.close_button(0.8)
	x.pressed.connect(_close_card)
	head.add_child(x)
	v.add_child(UIKit.label("Level %d %s" % [int(info.get("level", 1)), cd.display_name], 16, UIKit.TEXT_DIM))
	_card_button(v, "🔍  Inspect", Color(0.16, 0.16, 0.20), Color(0.70, 0.70, 0.75), func(): Net.inspect(id))
	if Net.accounts and not Net.is_friend(id):
		_card_button(v, "★  Add friend", Color(0.24, 0.20, 0.10), Color(0.95, 0.85, 0.55), func(): Net.add_friend(id))
	if Net.accounts:
		_card_button(v, "🤝  Trade", Color(0.12, 0.24, 0.14), Color(0.55, 0.95, 0.60), func(): Net.trade_with(id))
	var member := Net.is_member(id)
	if member:
		v.add_child(UIKit.label("👑 Leads your party" if int(Net.party.leader) == id else "In your party", 15, UIKit.GOLD))
		var place := Net.member_place(id)
		if place != "":
			var text := {"here": "🧭  Go to them", "town": "🧭  Go to them (town)", "zone": "🧭  Go to them (%s)" % ActDB.zone_name(String(Net.member_where[id]).get_slice(":", 2)),
				"rift": "🧭  Go to them (the rift)"}
			_card_button(v, text[place], Color(0.10, 0.20, 0.26), Color(0.50, 0.85, 0.95), func():
				if not Net.go_to(id):
					say("You can't go there now."))
		if Net.is_leader():
			_card_button(v, "👑  Make leader", Color(0.30, 0.26, 0.10), UIKit.GOLD, func(): Net.promote(id))
			_card_button(v, "Remove from party", Color(0.22, 0.10, 0.10), Color(0.70, 0.35, 0.30), func(): Net.kick(id))
	elif not Net.in_party() or Net.is_leader():
		_card_button(v, "⚔  Invite to party", Color(0.12, 0.26, 0.40), Color(0.50, 0.80, 1.0), func(): Net.invite(id))
	else:
		v.add_child(UIKit.label("Only your party's leader can invite.", 14, UIKit.TEXT_DIM, true))


func _card_button(parent: Control, text: String, bg: Color, border: Color, action: Callable) -> void:
	var b := UIKit.button(text, bg, border, Vector2(0, 46), 17)
	b.pressed.connect(func():
		action.call()
		_close_card())
	parent.add_child(b)


func _close_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	_card_id = 0
