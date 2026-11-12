extends Node2D
## Screenshots: the inventory with a belt and flasks (one selected), the Merchant's flasks, and the
## HUD flask bar. Needs a window:  godot --path . res://scratch/capture_flasks.tscn


func item(id: String, rarity := ItemInstance.Rarity.NORMAL, fams: Array = [], ilvl := 60) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = LootGenerator.base_by_id(id)
	it.rarity = rarity
	it.ilvl = ilvl
	for m in fams:
		it.affixes.append(LootGenerator.make_family_entry(it.base, m[0], m[1], m[2]))
	it.display_name = it.base.display_name
	it.refill()
	return it


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var R := ItemInstance.Rarity
	var belt := item("chain_belt", R.RARE, [["life", 3, 80.0], ["belt_charm_used", 1, 0.12], ["belt_flask_gained", 2, 0.2]], 40)
	p.bag.add(belt)
	p.equip_to(belt, "belt", true)
	p.flasks = [item("large_life_flask", R.MAGIC, [["flask_amount", 2, 0.5], ["flask_charges", 1, 0.3]]), item("medium_power_flask")]
	p.flasks[0].charges = 38.0
	p.charms = [item("ruby_charm", R.MAGIC, [["charm_life", 2, 70.0]]), item("silver_charm"), null]
	p.charms[1].charges = 10.0
	p.bag.add(item("sapphire_charm"))
	p.bag.add(item("iron_helm", R.RARE, [["life", 2, 40.0], ["armour", 3, 60.0], ["res_fire", 4, 0.2], ["str", 2, 15.0], ["res_cold", 1, 0.1]], 40))
	p.inventory_changed.emit()

	town.menu.open("details")
	town.menu.select(p.flasks[0])
	await _settle()
	_shot("flask_inventory.png")
	town.menu.select(p.charms[0])
	await _settle()
	_shot("charm_inventory.png")
	town.menu.close()

	p.take_damage(5.0, RuneDef.DamageType.FIRE)
	p.use_flask(0)
	await _settle()
	_shot("flask_hud.png")

	town.menu.open_vendor("shop")
	await _settle()
	_shot("flask_shop.png")
	get_tree().quit(0)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://scratch/" + name))
	print("saved ", name)
