extends Control
## Screenshot of the "What's new" window (scratch/changelog.png). Needs a window:
##   godot --path . --resolution 1280x720 res://scratch/capture_changelog.tscn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Changelog.show(self)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/changelog.png"))
	get_tree().quit()
