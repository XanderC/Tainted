extends Node
## Checks currency (old crafting materials turn into shards) and loose gems are the account's: older accounts gather every
## character's into one pool (once), a new account gets the starting pools, characters neither
## save nor reset them. Backs up and restores the real account file. Run headless:
##   godot --headless --path . res://scratch/test_shared_pools.tscn

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	var gs := GameState
	var acc_backup := FileAccess.get_file_as_string(gs.ACCOUNT_PATH) if FileAccess.file_exists(gs.ACCOUNT_PATH) else ""
	var chars_backup: Array = gs.characters.duplicate(true)
	var pools_backup := {}
	for k in gs.SHARED_KEYS:
		pools_backup[k] = (gs.get(k) as Dictionary).duplicate()
	var made: Array[String] = []

	# --- an older account: each character carries its own pools ---
	var a_id := "test_pool_a"
	var b_id := "test_pool_b"
	made.append_array([a_id, b_id])
	gs._write_json(gs._char_path(a_id), {"name": "A", "class": "warrior", "level": 3,
		"orbs": {"chaos": 3}, "shards": {"chaos": 4}, "materials": {"scrap": 5},
		"skill_gems": {"frenzy": 1}, "runes": {"rune_fire": 2}, "gems": {"ruby_1": 1}, "gold": 0})
	gs._write_json(gs._char_path(b_id), {"name": "B", "class": "warrior", "level": 7,
		"orbs": {"chaos": 2, "divine": 1}, "materials": {"scrap": 1},
		"skill_gems": {"frenzy": 2, "cleave": 1}, "runes": {"rune_fire": 1}, "gems": {"ruby_1": 2}})
	gs.characters = [{"id": a_id, "name": "A", "class": "warrior", "level": 3},
		{"id": b_id, "name": "B", "class": "warrior", "level": 7}]
	gs._load_shared({})  # no "shared" yet: gather from the characters
	check(gs.orb_count("chaos") == 5 and gs.orb_count("divine") == 1, "orbs added together (chaos %d)" % gs.orb_count("chaos"))
	check(gs.shard_count("chaos") == 4, "shards added")
	# 6 Scrap at 4 Transmutation shards each = 24 shards: 1 orb and 4 shards left
	check(gs.orb_count("transmute") == 1 and gs.shard_count("transmute") == 4,
		"old materials became shards (%d orbs, %d shards)" % [gs.orb_count("transmute"), gs.shard_count("transmute")])
	check(not gs._read_json(gs._char_path(a_id)).has("materials"), "materials taken out of the character save")
	check(gs.skill_gem_count("frenzy") == 3 and gs.skill_gem_count("cleave") == 1, "skill gems added")
	check(gs.rune_count("rune_fire") == 3, "support gems added")
	check(gs.gem_count("ruby_1") == 3, "socket gems added")
	var a_after := gs._read_json(gs._char_path(a_id))
	check(not a_after.has("orbs") and not a_after.has("gems") and not a_after.has("skill_gems"),
		"pools taken out of the character save")
	check(int(a_after.get("level", 0)) == 3, "the rest of the character save kept")
	var acc := gs._read_json(gs.ACCOUNT_PATH)
	check(acc.has("shared") and int(acc.shared.orbs.get("chaos", 0)) == 5, "pools saved in the account")

	# --- loading again doesn't add them twice ---
	gs._load_shared(acc)
	check(gs.orb_count("chaos") == 5, "a second load reads the account, not the characters (%d)" % gs.orb_count("chaos"))

	# --- a new account gets the starting pools once ---
	gs.characters = []
	gs._load_shared({})
	check(gs.orb_count("chaos") == int(CraftingDB.STARTING_CURRENCY.get("chaos", 0)), "new account: starting orbs")
	check(gs.rune_count("rune_fire") == int(gs.STARTER_RUNES.rune_fire), "new account: starting supports")

	# --- making and saving a character leaves the pools alone ---
	gs.characters = [{"id": a_id, "name": "A", "class": "warrior", "level": 3},
		{"id": b_id, "name": "B", "class": "warrior", "level": 7}]
	gs._load_shared(acc)
	var before := gs.orb_count("chaos")
	var new_id := gs.create_character("PoolTester", "warrior")
	made.append(new_id)
	check(new_id != "", "character created")
	check(gs.orb_count("chaos") == before and gs.skill_gem_count("frenzy") == 3, "creating a character keeps the pools")
	var saved := gs._read_json(gs._char_path(new_id))
	for k in gs.SHARED_KEYS:
		check(not saved.has(k), "character save has no %s" % k)
	check(gs.select_character(a_id), "select an existing character")
	check(gs.orb_count("chaos") == before, "loading a character keeps the pools (%d)" % gs.orb_count("chaos"))

	# --- a socketed gem isn't also in the stash: loading never hands out a starter gem ---
	var slotted := gs._read_json(gs._char_path(a_id))
	var slots := gs._empty_slots()
	slots[0].skill = "frenzy"
	slotted["skill_slots"] = slots
	slotted["skill_tree_version"] = 2
	gs._write_json(gs._char_path(a_id), slotted)
	gs.skill_gems.erase("frenzy")
	check(gs.select_character(a_id), "select a character with Frenzy socketed")
	check(gs.slot_skill(0) == "frenzy", "Frenzy is in its slot")
	check(gs.skill_gem_count("frenzy") == 0, "and not in the stash too (%d)" % gs.skill_gem_count("frenzy"))
	gs.give_starter_skills()
	check(gs.skill_gem_count("frenzy") == 0, "skipping the tutorial gives no second Frenzy when one is socketed")

	# --- restore ---
	gs.char_id = ""  # or the selected test character is saved again on the way out
	for id in made:
		if id != "":
			DirAccess.remove_absolute(gs._char_path(id))
	if acc_backup != "":
		var f := FileAccess.open(gs.ACCOUNT_PATH, FileAccess.WRITE)
		f.store_string(acc_backup)
		f.close()
	gs.characters = chars_backup
	for k in gs.SHARED_KEYS:
		gs.set(k, pools_backup[k])
	print("shared pools: %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
