class_name Quests
extends RefCounted
## Runs the quests in QuestDB. Progress is GameState.quests (saved with the character):
## quest id -> {"state": ACTIVE | READY | DONE, "step": index, "count": kills so far}.
## Scenes report what happens with notify(); NPC conversations use npc_options() and turn_in().

const ACTIVE := "active"  # working through its steps
const READY := "ready"    # every step done: hand it in to its turn_in NPC
const DONE := "done"      # rewarded


static func state(id: String) -> String:
	return String(GameState.quests.get(id, {}).get("state", ""))


static func step_index(id: String) -> int:
	return int(GameState.quests.get(id, {}).get("step", 0))


## The step a quest is on ({} once its steps are done).
static func current_step(id: String) -> Dictionary:
	var steps: Array = QuestDB.quest(id).get("steps", [])
	var i := step_index(id)
	return steps[i] if state(id) == ACTIVE and i < steps.size() else {}


static func start(id: String) -> void:
	if state(id) != "" or QuestDB.quest(id).is_empty():
		return
	GameState.quests[id] = {"state": ACTIVE, "step": 0, "count": 0}
	_changed()


## Something happened: advance every active quest whose current step it completes.
## `event` is a step type ("talk", "reach", "zone", "waypoint", "kill", "kill_boss", "use").
static func notify(event: String, key: String, amount := 1) -> void:
	var any := false
	for id in GameState.quests.keys():
		var s := current_step(id)
		if s.is_empty() or String(s["type"]) != event or String(s["key"]) != key:
			continue
		var q: Dictionary = GameState.quests[id]
		q["count"] = int(q.get("count", 0)) + amount
		if q["count"] >= int(s.get("count", 1)):
			_advance(id)
		any = true
	if any:
		_changed()


## Whether an active quest is waiting on this exact event right now (show the strongbox, etc.).
static func wants(event: String, key: String) -> bool:
	for id in GameState.quests:
		var s := current_step(id)
		if not s.is_empty() and String(s["type"]) == event and String(s["key"]) == key:
			return true
	return false


## Whether a quest boss is still to be fought (it doesn't come back once its quest is past it).
static func boss_alive(boss_id: String) -> bool:
	for id in QuestDB.QUESTS:
		var steps: Array = QuestDB.quest(id).get("steps", [])
		for i in steps.size():
			if steps[i]["type"] == "kill_boss" and steps[i]["key"] == boss_id:
				return state(id) == "" or (state(id) == ACTIVE and step_index(id) <= i)
	return true


static func _advance(id: String) -> void:
	var q: Dictionary = GameState.quests[id]
	q["step"] = int(q["step"]) + 1
	q["count"] = 0
	var steps: Array = QuestDB.quest(id).get("steps", [])
	if int(q["step"]) >= steps.size():
		q["state"] = READY


## What an NPC can do with you now: [{"label", "quest", "action": "offer" | "turn_in" | "talk",
## "text"}]. "talk" is a step that is talking to them (with their line for it).
static func npc_options(npc_id: String) -> Array:
	var out: Array = []
	for id in QuestDB.QUESTS:
		var q := QuestDB.quest(id)
		var st := state(id)
		if st == READY and q.get("turn_in", "") == npc_id:
			out.append({"label": "✔ " + String(q["name"]), "quest": id, "action": "turn_in", "text": q.get("complete", "")})
		elif st == "" and q.get("giver", "") == npc_id and available(id):
			out.append({"label": "! " + String(q["name"]), "quest": id, "action": "offer", "text": q.get("offer", "")})
		elif st == ACTIVE:
			var s := current_step(id)
			if s.get("type", "") == "talk" and s.get("key", "") == npc_id:
				var line: String = q.get("lines", {}).get(npc_id, {}).get(step_index(id), npc_options_default(npc_id))
				out.append({"label": "… " + String(q["name"]), "quest": id, "action": "talk", "text": line})
			elif q.get("giver", "") == npc_id:
				out.append({"label": "? " + String(q["name"]), "quest": id, "action": "progress", "text": q.get("progress", "")})
	return out


static func npc_options_default(npc_id: String) -> String:
	return String(QuestDB.npc(npc_id).get("greeting", ""))


## "!" an NPC has a quest for you, "?" one to hand in or talk about, "" nothing.
static func npc_marker(npc_id: String) -> String:
	var mark := ""
	for o in npc_options(npc_id):
		if o["action"] in ["turn_in", "talk"]:
			return "?"
		if o["action"] == "offer":
			mark = "!"
	return mark


## Whether a quest can be picked up yet (later main quests wait for the one before; all wait for
## the tutorial).
static func available(id: String) -> bool:
	if GameState.tutorial_stage < GameState.TUTORIAL_DONE:
		return false
	var need: String = QuestDB.quest(id).get("requires", "")
	return need == "" or state(need) == DONE


## Hand a READY quest in: rewards it and marks it DONE. Returns the rewards as lines of text.
static func turn_in(id: String, player: Player) -> Array:
	if state(id) != READY:
		return []
	var r: Dictionary = QuestDB.quest(id).get("rewards", {})
	var got: Array = []
	if r.has("xp"):
		GameState.add_xp(float(r["xp"]))
		got.append("+%d experience" % int(r["xp"]))
	for orb in r.get("orbs", {}):
		GameState.add_orb(orb, int(r["orbs"][orb]))
		got.append("%d × %s" % [int(r["orbs"][orb]), Currency.orb_name(orb)])
	if int(r.get("passive_points", 0)) > 0:
		GameState.skill_points += int(r["passive_points"])
		got.append("+%d passive skill point%s" % [int(r["passive_points"]), "" if int(r["passive_points"]) == 1 else "s"])
	if r.has("item") and player != null:
		var it_def: Dictionary = r["item"]
		var it := LootGenerator.roll_item(maxi(GameState.level, 2) + 1, int(it_def.get("rarity", 1)), String(it_def.get("slot", "")))
		if it != null:
			if not player.pick_up(it):
				player.item_dropped.emit(it)  # no room: the scene drops it at your feet
			got.append(it.display_name)
	GameState.quests[id]["state"] = DONE
	_changed()
	return got


## Lines for the HUD tracker: each active quest and its step (main quests first), then main quests
## waiting to be picked up.
static func tracker_lines() -> Array:
	var out: Array = []
	for kind in ["main", "side"]:
		for id in QuestDB.QUESTS:
			var q := QuestDB.quest(id)
			if q.get("kind", "side") != kind:
				continue
			var st := state(id)
			if st == ACTIVE:
				var s := current_step(id)
				var txt: String = s.get("text", "")
				if s.get("type", "") == "kill" and int(s.get("count", 1)) > 1:
					txt += " (%d / %d)" % [int(GameState.quests[id].get("count", 0)), int(s["count"])]
				out.append({"quest": id, "title": q["name"], "text": txt, "kind": kind})
			elif st == READY:
				out.append({"quest": id, "title": q["name"], "kind": kind,
					"text": "Return to %s" % QuestDB.npc(String(q.get("turn_in", ""))).get("name", "")})
			elif st == "" and kind == "main" and available(id):
				out.append({"quest": id, "title": q["name"], "kind": kind,
					"text": "Talk to %s" % QuestDB.npc(String(q.get("giver", ""))).get("name", "")})
	return out


static func _changed() -> void:
	GameState.quests_changed.emit()
	GameState.save()
