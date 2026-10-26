extends Node2D
## Checks the Gambler: a full stall of unidentified gear (never flasks), rolled for your level; prices
## by item level, jewellery double; buying pays and puts the piece in your bag (not without the orbs
## or room); the card has no Identify; the stall is new once its time is up or it's sold out; it's
## saved with the character. With a window (--out=<folder>) it saves gambler.png and gambler_card.png.
##   godot --headless --path . res://scratch/test_gambler.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6).trim_suffix("/") + "/"
	var town = load("res://scenes/town.tscn").instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = town.player
	var menu: GameMenu = town.menu
	GameState.level = 20
	p.bag.clear()
	GameState.gamble_stock = []
	var wares := Gambler.stock()
	check(wares.size() == Gambler.STOCK_SIZE, "a full stall (%d)" % wares.size())
	check(wares.all(func(it): return not it.identified and not it.is_flask() and it.rarity != ItemInstance.Rarity.NORMAL),
		"all unidentified gear, no flasks")
	check(wares.all(func(it): return it.ilvl >= 20 and it.ilvl <= 22), "rolled for your level")
	check(wares.all(func(it): return it.display_name == it.base.display_name), "showing only their base names")
	var counts := {}
	for i in 400:
		var r := Gambler.roll(30)
		counts[r.rarity] = int(counts.get(r.rarity, 0)) + 1
	print("rarities over 400: ", counts)
	check(int(counts.get(ItemInstance.Rarity.MAGIC, 0)) > 200 and int(counts.get(ItemInstance.Rarity.RARE, 0)) > 50, "mostly Magic, some Rare")
	var ring := wares.filter(func(it): return it.base.slot in ["ring", "amulet"])
	var sword := wares.filter(func(it): return not it.base.slot in ["ring", "amulet"])
	if not ring.is_empty() and not sword.is_empty():
		var rp := Gambler.price(ring[0])
		var sp := Gambler.price(sword[0])
		check(rp.values()[0] == sp.values()[0] * 2 or rp.keys() != sp.keys(), "jewellery costs double")
	# Buying
	GameState.orbs = {}
	var it: ItemInstance = wares[0]
	check(Gambler.buy(p, it) == "Not enough orbs!" and it in GameState.gamble_stock, "can't buy without the orbs")
	GameState.orbs = {"alteration": 100, "alchemy": 20, "chaos": 20}
	check(Gambler.buy(p, it) == "" and p.inventory.has(it) and not it in GameState.gamble_stock, "bought: in your bag")
	check(GameState.orb_count("alteration") == 100 - int(Gambler.price(it).get("alteration", 0)), "and paid for")
	check(not it.identified, "still unidentified")
	# Saved with the character
	var left := GameState.gamble_stock.size()
	var saved := {"at": GameState.gamble_at, "items": GameState.gamble_stock.map(func(i): return i.to_dict())}
	check(saved["items"].size() == left and ItemInstance.from_dict(saved["items"][0]).identified == false, "saved, unidentified")
	# The panel: its card has no Identify
	menu.open_vendor("gamble")
	await get_tree().process_frame
	var gp: GamblePanel = menu.current_panel()
	check(gp != null and gp is GamblePanel, "the Gambler's panel opens")
	if out != "":
		for f in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "gambler.png")
	gp._show_card(GameState.gamble_stock[0], Vector2(400, 300))
	for f in 4:
		await get_tree().process_frame
	var btns: Array = menu.item_tip().find_children("*", "Button", true, false).filter(func(b): return b.visible)
	check(btns.any(func(b): return "Buy" in b.text) and not btns.any(func(b): return "Identify" in b.text), "its card has Buy, not Identify")
	var shown: Array = GameState.gamble_stock.map(func(w): return gp._shown(w))
	check(shown.all(func(x): return x.rarity == ItemInstance.Rarity.NORMAL and x.sockets == 0 and x.affixes.is_empty()),
		"the stall shows every piece plain: no rarity, sockets or modifiers")
	var titles: Array = menu.item_tip().find_children("*", "Label", true, false)
	check(not menu.item_tip().find_children("*", "RichTextLabel", true, false).any(func(l): return "Socket" in l.text), "the card shows no sockets")
	if out != "":
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "gambler_card.png")
	menu.item_tip().close()
	# Sold out: new wares
	GameState.orbs = {"alteration": 999, "alchemy": 999, "chaos": 999}
	for w in GameState.gamble_stock.duplicate():
		p.bag.clear()
		gp._buy(w)
	check(GameState.gamble_stock.size() == Gambler.STOCK_SIZE, "sold out: a new stall at once")
	# Time's up: new wares
	var before: Array = GameState.gamble_stock.duplicate()
	GameState.gamble_at -= Gambler.REFRESH_SECS + 1
	check(Gambler.stock() != before and Gambler.seconds_left() > Gambler.REFRESH_SECS - 5, "time's up: new wares")
	menu.close()
	print("gambler: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
