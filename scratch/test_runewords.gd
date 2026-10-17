extends Node2D
## Checks runes and runewords: socket limits (6 on two-handers and body armour), the rune ladder,
## runes as socket gems (weapon vs armour stats), runewords forming only from a Normal item with
## exactly the right runes in order, breaking when a rune comes out, saving, orbs refusing them,
## and selling handing runes back. Run headless:
##   godot --headless --path . res://scratch/test_runewords.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func base(id: String) -> ItemBase:
	for b in LootGenerator.bases:
		if b.id == id:
			return b
	return null


func item(id: String, sockets: int, rarity := ItemInstance.Rarity.NORMAL) -> ItemInstance:
	var it := ItemInstance.new()
	it.base = base(id)
	it.display_name = it.base.display_name
	it.sockets = sockets
	it.rarity = rarity
	it.ilvl = 20
	return it


func rune(key: String) -> String:
	return SocketRune.id_of(key)


## Socket these runes into the item through GameState, as the Gems panel does.
func socket_all(it: ItemInstance, keys: Array) -> void:
	for k in keys:
		GameState.add_gem(rune(k), 1)
		GameState.socket_gem(it, it.gems.size(), rune(k))


func _ready() -> void:
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	p.bag.clear()

	# --- socket limits ---
	check(base("greatsword").max_sockets() == 6, "two-handed sword: 6 sockets")
	check(base("hunting_bow").max_sockets() == 6, "bow: 6 sockets")
	check(base("chain_mail").max_sockets() == 6, "body armour: 6 sockets")
	check(base("rusty_sword").max_sockets() == 4, "one-handed sword: 4")
	check(base("tower_shield").max_sockets() == 4, "shield: 4")
	check(base("dagger").max_sockets() == 3, "dagger: 3")
	check(base("iron_helm").max_sockets() == 3, "helmet: 3")
	check(base("worn_boots").max_sockets() == 2, "boots: 2")
	check(base("bone_ring").max_sockets() == 1, "ring: 1")
	var most := 0
	var over := false
	for i in 3000:
		var n := ItemInstance.roll_sockets(base("greatsword"), ItemInstance.Rarity.RARE)
		most = maxi(most, n)
		over = over or n > 6
	check(most == 6 and not over, "greatswords roll up to 6 sockets, never more (most %d)" % most)
	check(Crafting.socket_cap(item("chain_mail", 0)) == 6, "Jeweller's Orb uses the base's limit")

	# --- the rune ladder ---
	check(SocketRune.LADDER.size() == 33, "El to Zod: 33 runes")
	check(SocketRune.rank_of(rune("el")) == 1 and SocketRune.rank_of(rune("zod")) == 33, "ranks")
	check(SocketRune.next_id(rune("el")) == rune("eld") and SocketRune.next_id(rune("zod")) == "", "next rune")
	check(SocketRune.combine_count(rune("tal")) == 3 and SocketRune.combine_count(rune("ber")) == 2, "combine counts")
	var w := GemDef.info(rune("el"), "weapon")
	var a := GemDef.info(rune("el"), "chest")
	check(w.stat == "damage" and a.stat == "armor", "El: damage in a weapon, armour elsewhere")
	check(String(GemDef.info(rune("el")).text).contains("Weapon") , "slot-less text describes both")
	check(GemDef.all_ids().has(rune("zod")), "runes are in the gem pool order")
	check(GemDef.icon(rune("tal")) != null, "runes have an icon")
	var top_ok := true
	for i in 500:
		top_ok = top_ok and SocketRune.rank_of(SocketRune.random_drop(1)) <= SocketRune.max_drop_rank(1)
	check(top_ok, "a level 1 rift drops nothing above rank %d" % SocketRune.max_drop_rank(1))

	# --- combining runes at the Jeweler ---
	GameState.gems.clear()
	GameState.add_gem(rune("el"), 3)
	GameState.add_orb("transmute", 5)
	check(GameState.combine_gems(rune("el")) == 1 and GameState.gem_count(rune("eld")) == 1, "3 El make 1 Eld")

	# --- every runeword can actually be made ---
	for id in Runewords.LIST:
		var rw: Dictionary = Runewords.LIST[id]
		var runes_ok := true
		for k in rw.runes:
			runes_ok = runes_ok and SocketRune.rank_of(rune(String(k))) > 0
		check(runes_ok, "%s: every rune exists" % id)
		var some_base := false
		for b in LootGenerator.bases:
			some_base = some_base or (Runewords.fits(rw, b) and b.max_sockets() >= rw.runes.size())
		check(some_base, "%s: some base fits it with enough sockets" % id)

	# --- a runeword forms ---
	GameState.gems.clear()
	var mail := item("chain_mail", 2)
	p.add_to_bag(mail)
	socket_all(mail, ["tal", "eth"])
	check(mail.is_runeword() and mail.runeword_id == "stealth", "Tal Eth in 2-socket body armour is Stealth")
	check(mail.rarity == ItemInstance.Rarity.RUNEWORD and mail.display_name == "Stealth", "named and coloured")
	check(mail.powers.has("move_inc") and float(mail.powers.move_inc) >= 0.10, "rolled its powers")
	check(mail.rw_mods.size() == 1 and mail.rw_mods[0].stat == "armor", "rolled its flat armour")
	check(Crafting.orb_block_reason(mail, "chaos") != "", "orbs can't alter a runeword")

	# --- it works when worn ---
	p.equip(mail)
	check(float(p.item_powers.get("move_inc", 0.0)) >= 0.10, "worn: its powers count")

	# --- and survives a save ---
	var copy := ItemInstance.from_dict(mail.to_dict())
	check(copy.runeword_id == "stealth" and copy.rarity == ItemInstance.Rarity.RUNEWORD, "save keeps the runeword")
	check(copy.rw_mods.size() == 1 and is_equal_approx(float(copy.rw_mods[0].value), float(mail.rw_mods[0].value)), "save keeps its rolls")
	check(copy.gems == mail.gems, "save keeps its runes")

	# --- taking a rune out breaks it ---
	GameState.unsocket_gem(mail, 1)
	check(not mail.is_runeword() and mail.rarity == ItemInstance.Rarity.NORMAL, "broken: Normal again")
	check(mail.display_name == mail.base.display_name and mail.powers.is_empty(), "broken: name and powers gone")
	check(GameState.gem_count(rune("eth")) == 1, "the rune is back in the pool")
	check(float(p.item_powers.get("move_inc", 0.0)) == 0.0, "worn: its powers stop")
	p.unequip("chest")

	# --- only the exact recipe ---
	var wrong := item("chain_mail", 2)
	p.add_to_bag(wrong)
	socket_all(wrong, ["eth", "tal"])
	check(not wrong.is_runeword(), "wrong order: nothing")
	var roomy := item("chain_mail", 3)
	p.add_to_bag(roomy)
	socket_all(roomy, ["tal", "eth"])
	check(not roomy.is_runeword(), "a spare socket: nothing")
	var magic := item("chain_mail", 2, ItemInstance.Rarity.MAGIC)
	p.add_to_bag(magic)
	socket_all(magic, ["tal", "eth"])
	check(not magic.is_runeword(), "a Magic item: nothing")
	var helm := item("iron_helm", 2)
	p.add_to_bag(helm)
	socket_all(helm, ["tal", "eth"])
	check(not helm.is_runeword(), "a helmet isn't body armour: nothing")

	# --- and it says why ---
	check(Runewords.why_not(magic).contains("Normal") and Runewords.why_not(magic).contains("Scouring"), "Magic: needs Normal, scour it")
	check(Runewords.why_not(roomy).contains("exactly 2"), "a spare socket: says it needs exactly 2")
	check(Runewords.why_not(helm).contains("Body Armour"), "wrong kind: says where it goes")
	check(Runewords.why_not(wrong) == "", "wrong order spells nothing")
	var legend := item("battle_axe", 2, ItemInstance.Rarity.LEGENDARY)
	legend.unique_id = "executioners_due"
	p.add_to_bag(legend)
	socket_all(legend, ["tir", "el"])
	check(not legend.is_runeword() and Runewords.why_not(legend).contains("Legendary")
		and not Runewords.why_not(legend).contains("Scouring"), "a Legendary: says so, no scouring hint")
	var three := item("battle_axe", 3)
	p.add_to_bag(three)
	socket_all(three, ["tir", "el"])
	check(Runewords.why_not(three).contains("exactly 2 sockets") and Runewords.why_not(three).contains("has 3"),
		"Tir El in a 3-socket weapon: Steel needs exactly 2")
	# Eth Tir is how Grief starts: in a roomier weapon that's progress, not a mistake
	var grief_base := item("greatsword", 5)
	p.add_to_bag(grief_base)
	socket_all(grief_base, ["eth", "tir"])
	check(Runewords.why_not(grief_base) == "", "part-way through Grief: no warning")

	# --- six sockets ---
	p.bag.clear()  # room for a 2x4 greatsword
	var sword := item("greatsword", 6)
	check(p.add_to_bag(sword), "the greatsword goes in the bag")
	socket_all(sword, ["jah", "mal", "jah", "sur", "jah", "ber"])
	check(sword.runeword_id == "last_wish", "Last Wish in a 6-socket greatsword")
	var short_sword := item("rusty_sword", 4)
	check(not Runewords.fits(Runewords.LIST.last_wish, short_sword.base) or short_sword.base.max_sockets() < 6,
		"a one-handed sword can never hold Last Wish")

	# --- the UI builds for runes and runewords (errors would print SCRIPT ERROR) ---
	var card := VBoxContainer.new()
	add_child(card)
	UIKit.item_card(card, sword)
	check(card.get_child_count() > 0, "a runeword's item card builds")
	var menu: GameMenu = town.menu
	menu.open_vendor("jeweler")
	menu.selected = sword
	var gp := menu.current_panel() as GemsPanel
	check(gp != null, "the Jeweler opens the Gems panel")
	if gp != null:
		GameState.add_gem(rune("tal"), 3)
		gp._sel_gem = rune("tal")
		gp._combine_gem = rune("tal")
		menu.refresh()
		check(gp.get_child_count() > 0, "the Gems panel builds with a runeword and a rune picked")
	menu.close()

	# --- selling hands the runes back ---
	GameState.gems.clear()
	GameState.sell_item(sword)
	check(GameState.gem_count(rune("jah")) == 3 and GameState.gem_count(rune("ber")) == 1, "selling returns the runes")

	print("runewords: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
