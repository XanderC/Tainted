class_name QuestDB
extends RefCounted
## The story's people and quests (Quests runs them; progress is saved per character).
##
## A quest: name, act, kind ("main" | "side"), giver and turn_in (NPC ids), summary (quest log),
## offer / progress / complete (what the giver says), steps, and rewards.
## A step: {"type", "key", "count", "text"} where type is
##   "talk"     - talk to NPC `key`
##   "reach"    - walk into trigger `key` (a map "trigger" object)
##   "zone"     - enter zone `key`
##   "waypoint" - touch the waypoint in zone `key`
##   "kill"     - kill `count` monsters of MonsterKinds `key`
##   "kill_boss"- kill the quest boss `key` (a map "boss" object)
##   "use"      - use object `key` (a map "quest_object")
## Rewards: {"xp", "orbs": {id: n}, "passive_points", "item": {"slot", "rarity"}}.

## NPCs anywhere in the story: name, title (under the name), skin (RigSprite.skin), and what they
## say when they have nothing else for you.
const NPCS := {
	"battlemaster": {"name": "Battlemaster Brom", "title": "Passive Tree", "skin": "battlemaster",
		"greeting": "Ashfall stands because we hold the line. Every hand that can swing a blade counts."},
	"sage": {"name": "Sage Aldous", "title": "Identify", "skin": "sage",
		"greeting": "The taint is older than this outpost, older than the oldest trees in the Ashwood. I read what I can of it."},
	"blacksmith": {"name": "Blacksmith", "title": "Craft", "skin": "blacksmith",
		"greeting": "Steel's steel. Bring me orbs and I'll make it sing."},
	"merchant": {"name": "Merchant", "title": "Buy & Sell", "skin": "merchant",
		"greeting": "Coin is scarce since the roads closed. I'll take orbs."},
	"stash_keeper": {"name": "Stash Keeper", "title": "Shared Storage", "skin": "stash_keeper",
		"greeting": "What's stored here stays here. Every soul of yours can reach it."},
	"jeweler": {"name": "Jeweler", "title": "Gems", "skin": "jeweler",
		"greeting": "Three small stones make one fine one. Patience, friend."},
	"hesk": {"name": "Caravan Master Hesk", "title": "Caravans", "skin": "caravan_master",
		"greeting": "Not a single caravan has made it through the Ashwood this month. Not one."},
	"caravan_guard": {"name": "Wounded Guard", "title": "Survivor", "skin": "caravan_guard",
		"greeting": "Water... thank the gods, someone came."},
}

const QUESTS := {
	"a1_into_the_wastes": {
		"name": "Into the Ashwood", "act": 1, "kind": "main", "giver": "battlemaster", "turn_in": "battlemaster",
		"summary": "Brom wants the road west scouted. Find the old waypoint in the Ashwood so Ashfall can reach it again.",
		"offer": "You made it through the husks, so you can fight. Good. The road west runs into the [b]Ashwood[/b], and the old waypoint there has gone dark. Find it, wake it, and come back. Then we talk about what's out there.",
		"progress": "The waypoint lies somewhere in the Ashwood, west of the outpost. Touch the stone and it will remember you.",
		"complete": "It's lit again. I saw the glow from the wall. You've earned this, and you'll need it.",
		"steps": [
			{"type": "waypoint", "key": "dune_wastes", "text": "Find the waypoint in the Ashwood"},
		],
		"rewards": {"xp": 160, "orbs": {"transmute": 2, "augment": 1}},
	},
	"a1_lost_caravan": {
		"name": "The Lost Caravan", "act": 1, "kind": "side", "giver": "hesk", "turn_in": "hesk",
		"summary": "Hesk's last caravan never arrived. Find what happened to it in the Ashwood and bring back his strongbox.",
		"offer": "My last caravan left the river crossing eight days ago and never arrived. Twelve wagons, gone. If anyone lived, they'd be near the old road through the [b]Ashwood[/b]. Find them. And if you find my strongbox... I'll make it worth your while.",
		"progress": "The caravan took the old road through the Ashwood. Look for the wreck.",
		"complete": "My strongbox! And the guard lives? You've done more for Ashfall today than the garrison has all month. Take this, it was meant for a buyer who'll never come now.",
		"steps": [
			{"type": "reach", "key": "caravan_wreck", "text": "Find the caravan wreck in the Ashwood"},
			{"type": "talk", "key": "caravan_guard", "text": "Speak to the survivor at the wreck"},
			{"type": "kill_boss", "key": "raider_captain", "text": "Slay Vesh, the Raider Captain"},
			{"type": "use", "key": "strongbox", "text": "Recover Hesk's strongbox from the raider camp"},
		],
		"rewards": {"xp": 320, "orbs": {"alteration": 3, "augment": 2}, "item": {"slot": "flask", "rarity": 1}},
		# What the people on the way say at a step (npc id -> {step index: line})
		"lines": {
			"caravan_guard": {1: "Raiders hit us at dusk. [b]Vesh[/b] and his archers, hooded bandits from the north ridge. They took Hesk's strongbox up to their camp. I couldn't stop them. Please... get it back."},
		},
	},
}


static func npc(id: String) -> Dictionary:
	return NPCS.get(id, {"name": id.capitalize(), "title": "", "skin": "", "greeting": "..."})


static func quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})
