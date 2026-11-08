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
## Rewards: {"xp", "orbs": {id: n}, "gems": {gem id: n}, "passive_points", "item": {"slot", "rarity"}}.
##
## Act I is "The Bleeding Veil" (ACT1_DESIGN.md): Oakhaven Outpost and the zones round it.

## NPCs anywhere in the story: name, title (under the name), skin (RigSprite.skin), and what they
## say when they have nothing else for you.
const NPCS := {
	"battlemaster": {"name": "Battlemaster Brom", "title": "Passive Tree", "skin": "battlemaster",
		"greeting": "Oakhaven's palisade has held for sixty years. It will hold now, if every hand that can swing a blade swings it."},
	"sage": {"name": "Sage Aldous", "title": "Identify", "skin": "sage",
		"greeting": "The Taint feeds on fear, and Oakhaven is full of it. I read what I can of what it leaves behind."},
	"blacksmith": {"name": "Blacksmith", "title": "Craft", "skin": "blacksmith",
		"greeting": "Steel's steel. Bring me orbs and I'll make it sing."},
	"merchant": {"name": "Merchant", "title": "Buy & Sell", "skin": "merchant",
		"greeting": "Coin is scarce since the roads closed. I'll take orbs."},
	"stash_keeper": {"name": "Stash Keeper", "title": "Shared Storage", "skin": "stash_keeper",
		"greeting": "What's stored here stays here. Every soul of yours can reach it."},
	"jeweler": {"name": "Jeweler", "title": "Gems", "skin": "jeweler",
		"greeting": "Three small stones make one fine one. Patience, friend."},
	"althea": {"name": "High Priestess Althea", "title": "Wards", "skin": "",
		"greeting": "Salt and fire keep the dark at the door. Keep the braziers fed, and bring me what the Wilds throws at you."},
	"dennis": {"name": "Scout Captain Dennis", "title": "Scout", "skin": "forest_ranger_2",
		"greeting": "Another hour in that lodge and the wolves would have had the door. I owe you."},
	"corwin": {"name": "Merchant Corwin", "title": "In a hurry", "skin": "caravan_master",
		"greeting": "Don't ask me what's in the lockbox. Fetch it, and the gem is yours."},
}

const QUESTS := {
	"a1_first_incursion": {
		"name": "The First Incursion", "act": 1, "kind": "main", "giver": "battlemaster", "turn_in": "althea",
		"summary": "Briarwolves are pressing the gate and Scout Captain Dennis has not come back from the Blackroot Wilds. Clear the road, find him, and take what you find to High Priestess Althea.",
		"offer": "Dennis took three scouts into the [b]Blackroot Wilds[/b] to find where the beasts are coming from. Two nights ago the howling began at the gate, and he hasn't come back. Cull the briarwolves off the road first. Then find him.",
		"progress": "The briarwolves prowl the road out of the gate. Cull them, then push on into the Blackroot Wilds. Dennis's hunting lodge lies north-east of the waypoint.",
		"complete": "Give me that. [i]Gods.[/i] This is no natural venom. It is something pushing through from the other side, and it is feeding on our fear. I felt it in the well three nights ago and told no one. Rest, warrior. When you can stand, I will need you at the springs.",
		"steps": [
			{"type": "kill", "key": "briarwolf", "count": 8, "text": "Clear the briarwolves from the road into the Wilds"},
			{"type": "reach", "key": "hunting_lodge", "text": "Find Scout Captain Dennis in the Blackroot Wilds"},
			{"type": "kill_boss", "key": "briar_alpha", "text": "Slay the Briarwolf Alpha"},
			{"type": "use", "key": "rift_shard", "text": "Take the Coagulated Rift Shard"},
			{"type": "talk", "key": "dennis", "text": "Speak to Scout Captain Dennis"},
		],
		"rewards": {"xp": 220, "orbs": {"transmute": 2, "augment": 1}, "passive_points": 1},
		"lines": {
			"dennis": {4: "I'm alive because you came. The big one was no wolf of any season I know. It wore that shard like a second heart. Take it to Althea, she will know what it is. I'll follow when my legs agree."},
		},
	},
	"a1_lost_heirloom": {
		"name": "The Lost Heirloom", "act": 1, "kind": "side", "giver": "corwin", "turn_in": "corwin",
		"summary": "Merchant Corwin fled the Blackroot Wilds and left his family lockbox in a ruined manor. He will pay in an uncut gem.",
		"offer": "Listen. I left in a hurry, and in my hurry I left a lockbox in my family's manor, out in the [b]Blackroot Wilds[/b]. Papers, mostly. Sentimental. Fetch it and I'll give you an uncut gem, a good one. And don't open it.",
		"progress": "The manor lies south-east of the waypoint, roofless and black with rot. Bring me the lockbox and the gem is yours.",
		"complete": "You opened it. Of course you opened it. Whatever the diary says, it says what a man will write to live. Take the gem and spare me the sermon.",
		"steps": [
			{"type": "reach", "key": "ruined_manor", "text": "Find the ruined manor in the Blackroot Wilds"},
			{"type": "use", "key": "lockbox", "text": "Take Corwin's lockbox"},
		],
		"rewards": {"xp": 200, "orbs": {"alteration": 2}, "gems": {"topaz_2": 1}},
	},
}


static func npc(id: String) -> Dictionary:
	return NPCS.get(id, {"name": id.capitalize(), "title": "", "skin": "", "greeting": "..."})


static func quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})
