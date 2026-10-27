extends Node
## Lists the skills and supports that have no painted icon (SkillIcons): the ones drawn instead.
##   godot --headless --path . res://scratch/list_skill_icons.tscn
func _ready() -> void:
	SkillTree.init_skills()
	var have := []
	var missing := []
	for sk in SkillTree.all_skills():
		(have if SkillIcons.texture(sk.id) != null else missing).append("%s(%s)" % [sk.id, sk.cluster])
	print("SKILLS painted ", have.size(), ", drawn ", missing.size())
	print("DRAWN: ", ", ".join(PackedStringArray(missing)))
	get_tree().quit()
