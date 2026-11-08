class_name Options
extends RefCounted
## Settings kept on this device (user://options.cfg), the same for every character: the camera zoom
## (GameCamera). The window that changes them is OptionsUI. Add a setting with get_value / set_value
## under a section of its own.

const FILE := "user://options.cfg"

static var _cfg: ConfigFile = null


static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(FILE)  # no file yet: stays empty, and every setting is its default
	return _cfg


static func get_value(section: String, key: String, default: Variant) -> Variant:
	return _config().get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var c := _config()
	c.set_value(section, key, value)
	c.save(FILE)
