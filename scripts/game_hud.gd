class_name GameHud
extends RefCounted
## The fighting HUD for a scene with a player: joystick, skill buttons, flask row, weapon swap, the
## life and resource orbs and the experience bar. Returns the CanvasLayer it all sits on.


static func build(scene: Node, player: Player) -> CanvasLayer:
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var joy := VirtualJoystick.new()
	layer.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.joystick = joy
	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	for i in SkillButton.CENTRES:
		var b := SkillButton.new()
		b.player = player
		b.index = i
		b.position = SkillButton.pad_position(i)
		pad.add_child(b)
	var flasks := FlaskBar.new()
	flasks.player = player
	layer.add_child(flasks)
	var swap := WeaponSwapButton.new()
	swap.player = player
	swap.position = Vector2(-137, -358)
	pad.add_child(swap)
	var bars := HudBars.new()
	bars.player = player
	layer.add_child(bars)
	return layer
