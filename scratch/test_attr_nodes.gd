extends Node2D
## The passive tree's attribute nodes (Path of Exile 2): every small node that gave points of one attribute
## is an attribute node, taken as the attribute you pick (a popup in the tree window), refunded and respecced
## with its choice, and an old save's node keeps the attribute it gave. Run headless:
##   godot --headless --path . res://scratch/test_attr_nodes.tscn

var _fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	for i in 3:
		await get_tree().process_frame
	var g := PassiveTree.get_tree()
	var attr_nodes := 0
	for id in g.nodes:
		var n: Dictionary = g.nodes[id]
		if n.has("attr"):
			attr_nodes += 1
			check(n.kind == "small" and n.stats.is_empty() and Attributes.KEYS.has(n.attr.default) and int(n.attr.amount) > 0,
				"%s is a small node with an amount and a default attribute" % id)
		else:
			check(not (n.kind == "small" and n.stats.size() == 1 and Attributes.KEYS.has(n.stats.keys()[0])),
				"%s (not an attribute node) gives more than one attribute point" % id)
	check(attr_nodes >= 30, "the tree has plenty of attribute nodes (%d)" % attr_nodes)
	check(not g.nodes.str_c0.has("attr") and g.nodes.str_c0.stats.has("dex"), "the two-attribute connectors are left as they are")

	# Taking one with a choice
	GameState.reset_all_skills()
	GameState.skill_points = 6
	var dex0 := GameState.passive_value("dex")
	var str0 := GameState.passive_value("str")
	check(not GameState.allocate_node("str_p0", "luck"), "a made-up attribute takes nothing")
	check(GameState.skill_points == 6 and not GameState.is_node_allocated("str_p0"), "and costs no point")
	check(GameState.allocate_node("str_p0", "dex"), "the Strength-branch node can be taken as Dexterity")
	check(GameState.passive_value("dex") == dex0 + 8 and GameState.passive_value("str") == str0, "it gives 8 Dexterity, and no Strength")
	check(GameState.attr_choice("str_p0") == "dex" and GameState.skill_points == 5, "it remembers the choice, and cost one point")
	check(GameState.allocate_node("str_p1"), "an ordinary node is still taken as before")
	check(GameState.allocate_node("str_p2"), "taking an attribute node with no choice")
	check(GameState.attr_choice("str_p2") == "str", "gives its own attribute then (%s)" % GameState.attr_choice("str_p2"))

	# An old save: a node taken with no recorded choice keeps its default
	GameState.passive_choices.erase("str_p2")
	check(GameState.attr_choice("str_p2") == "str", "an old save's node keeps the attribute it gave")
	GameState.passive_choices["str_p2"] = "nonsense"
	check(GameState.attr_choice("str_p2") == "str", "and a damaged choice falls back to it too")

	# Refund and respec forget the choice
	GameState.orbs["regret"] = 3
	check(GameState.refund_node("str_p2"), "refunding it")
	check(not GameState.passive_choices.has("str_p2"), "forgets its choice")
	GameState.reset_all_skills()
	check(GameState.passive_choices.is_empty() and GameState.passive_value("dex") == dex0, "a respec forgets them all")

	# The window: tap the node, the popup asks which
	var ui: SkillTreeUI = town.skill_tree_ui
	GameState.skill_points = 4
	ui.open()
	for i in 3:
		await get_tree().process_frame
	ui._tree_canvas.node_selected.emit("str_p0")
	await get_tree().process_frame
	check(is_instance_valid(ui._choice), "tapping an attribute node you can take opens the choice")
	check(find(ui._choice, "Pick_str") != null and find(ui._choice, "Pick_dex") != null
		and find(ui._choice, "Pick_vit") != null and find(ui._choice, "Pick_ene") != null, "with a button for each attribute")
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://scratch/attr_popup.png"))
	(find(ui._choice, "Pick_ene") as Button).pressed.emit()
	await get_tree().process_frame
	check(GameState.is_node_allocated("str_p0") and GameState.attr_choice("str_p0") == "ene", "picking Energy takes it as Energy")
	check(ui._choice == null, "and the popup closes")
	ui._tree_canvas.node_selected.emit("str_p0")
	await get_tree().process_frame
	check(ui._choice == null, "tapping one you already have does not ask again")
	ui._tree_canvas.node_selected.emit("dex_p2")  # not linked to anything you have
	await get_tree().process_frame
	check(ui._choice == null, "nor one you cannot take")
	ui._tree_canvas.node_selected.emit("str_p1")
	await get_tree().process_frame
	check(ui._choice == null and not GameState.is_node_allocated("str_p1"), "and an ordinary node does not ask either")
	ui.choose_attribute("dex_p0")
	await get_tree().process_frame
	check(is_instance_valid(ui._choice), "(another attribute node you can take asks)")
	ui.close()
	check(ui._choice == null, "closing the window drops the popup")
	GameState.reset_all_skills()
	print("attribute nodes: ", "ok" if _fails == 0 else "%d failed" % _fails)
	get_tree().quit(_fails)
