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
##   "use"      - use object `key` (a map "quest_object"; its "key", when it has one, is shared by several of them: "count" of them)
## Rewards: {"xp", "orbs": {id: n}, "gems": {gem id: n}, "passive_points", "attr_points", "skill_rune": n, "item": {"slot", "rarity"},
## "notes": [lines listed with the rewards, for what the story gives that is not an item],
## "bonus": {stat: amount} a permanent bonus for good once the quest is done (Quests.bonus: "res_all" adds to every resistance)}.
## "choose": [{"label", ...rewards}, ...] instead makes the player pick one of them when handing in (the others are lost).
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
	"voss": {"name": "Apothecary Voss", "title": "Cast out", "skin": "stash_keeper",
		"greeting": "Oakhaven threw me out for what I brew. Funny, now it wants what I know."},
	"mara": {"name": "Scout Mara", "title": "Last of the Watch", "skin": "forest_ranger_3",
		"greeting": "Don't stand in the doorway. They remember where the door is."},
	"ancestor_spirit": {"name": "Weeping Spirit", "title": "Of the Ossuary", "skin": "ghost_knight",
		"greeting": "Cold. It is always cold, here. They took our urns, and now we cannot sleep."},
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
	"a1_poisoning_the_well": {
		"name": "Poisoning the Well", "act": 1, "kind": "main", "giver": "althea", "turn_in": "althea", "requires": "a1_first_incursion",
		"summary": "Oakhaven's well is turning black. Follow its tributary into the Weeping Hollow, slay what guards the Brood Cyst, and plant Althea's Alchemical Purge Ward.",
		"offer": "The shard is only a splinter of it. The well is turning black, and the water comes from the caves under the [b]Weeping Hollow[/b], east of the Wilds. Something is feeding on it there: a cyst, I think, and a guardian. Take this Alchemical Purge Ward. Plant it at the cyst, and the water will clear, for a while.",
		"progress": "The Weeping Hollow lies east of the Blackroot Wilds, a cave mouth past the ruined manor. The cyst is in the great cavern in the north-east, beyond the river.",
		"complete": "The well runs clear. [i]For now.[/i] You said the dying thing screamed? Whispers, from the north? ...The ancestral tombs of Oakhaven lie that way, past the Ashen Verge, under the Ossuary. The Taint did not die in that cyst. It only let go of the water.",
		"steps": [
			{"type": "zone", "key": "weeping_hollow", "text": "Enter the Weeping Hollow"},
			{"type": "reach", "key": "brood_cyst", "text": "Find the Brood Cyst in the north-east cavern"},
			{"type": "kill_boss", "key": "matron_vhol", "text": "Slay Skittering Matron Vhol"},
			{"type": "use", "key": "purge_ward", "text": "Plant the Alchemical Purge Ward at the cyst"},
		],
		"rewards": {"xp": 420, "orbs": {"augment": 5, "alchemy": 1}, "passive_points": 1, "item": {"slot": "", "rarity": 2}},
	},
	"a1_breaking_the_seal": {
		"name": "Breaking the Seal", "act": 1, "kind": "main", "giver": "althea", "turn_in": "althea", "requires": "a1_poisoning_the_well",
		"summary": "The whispers come from the Grand Ossuary, past the Ashen Verge, behind iron gates sealed with a Warded Keystone that was broken in two. Take the halves from the grave warden and from the golem a Bleed Rift animated, and join them at the mausoleum.",
		"offer": "The Ossuary's gates were sealed three centuries ago with a [b]Warded Keystone[/b], and the seal was broken in two so that no one man could open it. One half went to the grave warden of the [b]Ashen Verge[/b]. I hear he drank what the Taint offered him. The other was lodged in a golem the old priests made, and the rift has woken it. Bring me both, and we open the gates ourselves, before something on the other side does.",
		"progress": "The Ashen Verge lies past the Weeping Hollow's far gate, or by the road out of the Sunken Fen. The warden haunts the graveyard in the north; the golem stands in a Bleed Rift in the south. The sealed mausoleum is on the raised ground to the east.",
		"complete": "Both halves, and the seal sings. The gates are open: a stair into the dark, and the whispers rise from it like heat. I will give you what blessing I have left. Whatever waits below is what the Taint has been reaching for.",
		"steps": [
			{"type": "zone", "key": "ashen_verge", "text": "Cross into the Ashen Verge"},
			{"type": "kill_boss", "key": "grave_warden", "text": "Slay the Maddened Grave Warden"},
			{"type": "use", "key": "warden_half", "text": "Take the first half of the Warded Keystone"},
			{"type": "kill_boss", "key": "rift_golem", "text": "Destroy the Bleed-Rift Golem"},
			{"type": "use", "key": "golem_half", "text": "Take the second half of the Warded Keystone"},
			{"type": "use", "key": "mausoleum_seal", "text": "Join the halves at the sealed mausoleum"},
		],
		"rewards": {"xp": 650, "orbs": {"augment": 5, "alchemy": 2, "chaos": 1}, "passive_points": 1, "item": {"slot": "", "rarity": 2}},
	},
	"a1_the_last_watch": {
		"name": "The Last Watch", "act": 1, "kind": "side", "giver": "dennis", "turn_in": "dennis", "requires": "a1_poisoning_the_well",
		"summary": "Scout Captain Dennis sent three scouts to the Ashen Verge to watch the Ossuary and none came back. Find them: two have been twisted by the Taint and must be put down, and one holds out in a ruined watchtower.",
		"offer": "I sent three of mine to watch the [b]Ashen Verge[/b] before the howling began. They had a beacon in the old watchtower, and they were to light it if the Ossuary stirred. It has been dark for weeks. Find them, if you can. If the Taint has them, you will know, and you will do what a captain would do, and I will not ask how.",
		"progress": "The scouts went into the Ashen Verge. Two have been twisted and must be put down; the third was last seen at the watchtower in the south-east, and may yet be alive.",
		"complete": "Mara. Alive. And the key she kept, the armory vault's, from the Ossuary's old guardroom. A rusted thing, but the lock will remember it. Keep it: a vault behind a wall that will not stay up if you press it, she says. Thank you. Tell the others they stood the watch to the last.",
		"steps": [
			{"type": "kill", "key": "mutated_scout", "count": 2, "text": "Put down the 2 scouts the Taint twisted"},
			{"type": "talk", "key": "mara", "text": "Find the surviving scout at the watchtower"},
		],
		"rewards": {"xp": 480, "orbs": {"augment": 2, "chaos": 1}, "item": {"slot": "", "rarity": 2},
			"notes": ["the Rusted Armory Key (for a vault in the Ossuary)"]},
		"lines": {
			"mara": {1: "Dennis sent you? Thank the gods. Jorin and Tess went down to the gates for a closer look... and came back wrong. I couldn't. Here: the armory key, from the guardroom. There's a vault behind a collapsible wall in the Ossuary's first hall. Take it to Dennis, and tell him the beacon's dry."},
		},
	},
	"a1_descent_into_madness": {
		"name": "Descent into Madness", "act": 1, "kind": "main", "giver": "althea", "turn_in": "althea", "requires": "a1_breaking_the_seal",
		"summary": "Beneath the Ossuary's gates the boundary between the realms is being held open by three Veil Anchors, each channelled by a cultist herald. Fight down through the catacombs, level by level, and shatter all three before the wall between the worlds collapses.",
		"offer": "The gates are open, and what I feared is true. The cult has driven three [b]Veil Anchors[/b] into the Ossuary's floors, and each is channelled by a herald who believes he is feeding a god. They hold the boundary open from the inside. Go down. Break the anchors, one on the first level, one deeper, and the last on the level below. Every one will shake the floor and bring what it can to your throat. And be quick: if the wall between the realms falls before they do, the Outpost falls with it.",
		"progress": "The Grand Ossuary lies behind the mausoleum in the Ashen Verge. Two anchors stand on its first level, in the north and the south; the third is on the level below. Each is held by a herald.",
		"complete": "Three anchors, and the floor still holds. I felt each one go, like a tooth. But you have seen the lower level: the stair at its end goes down to the Sepulcher of Mourning, and that is where they have been carrying everything they take from the graves. I will tell you what I can about what sleeps there.",
		"steps": [
			{"type": "zone", "key": "grand_ossuary_1", "text": "Descend into the Grand Ossuary"},
			{"type": "kill_boss", "key": "herald_oren", "text": "Slay Herald Oren, who channels the first Veil Anchor"},
			{"type": "use", "key": "anchor_1", "text": "Shatter the first Veil Anchor"},
			{"type": "kill_boss", "key": "herald_sable", "text": "Slay Herald Sable, who channels the second"},
			{"type": "use", "key": "anchor_2", "text": "Shatter the second Veil Anchor"},
			{"type": "zone", "key": "grand_ossuary_2", "text": "Take the stair down to the Lower Ossuary"},
			{"type": "kill_boss", "key": "herald_morrow", "text": "Slay Herald Morrow, who channels the third"},
			{"type": "use", "key": "anchor_3", "text": "Shatter the third Veil Anchor"},
		],
		"rewards": {"xp": 1100, "orbs": {"augment": 7, "alchemy": 3, "chaos": 2}, "passive_points": 1, "item": {"slot": "", "rarity": 2}},
	},
	"a1_lord_malaphax": {
		"name": "The Flesh-Torn", "act": 1, "kind": "main", "giver": "althea", "turn_in": "althea", "requires": "a1_descent_into_madness",
		"summary": "The great door at the end of the Lower Ossuary stands open on the Sepulcher of Mourning, where the rift is torn widest. What waits before it is Lord Malaphax, once Duke Edward of Oakhaven, who walled himself into the crypt alive so that death could not find him. End him.",
		"offer": "The door at the end of the choir is open now. The Sepulcher of Mourning lies behind it, a cathedral the old dukes built for their dead, and the rift is torn widest there, behind the altar. I know who stands before it. Duke Edward walled himself in alive when the Taint first came, so afraid of dying that he would rather be buried. The Taint found a man made entirely of fear, and made an engine of him. He calls himself [b]Lord Malaphax[/b] now. Put him down, and look at what he guards.",
		"progress": "The Sepulcher of Mourning is behind the great door at the end of the Lower Ossuary. Lord Malaphax stands before the altar and the torn rift behind it. He has two faces: iron first, and then what is under it. When the dark takes you, find the soul that feeds it.",
		"complete": "Edward. Poor, frightened Edward. You have done what the whole Outpost could not. I will ward the doorway myself: that scar will not heal, but it can be held. Hear me now, though, and do not let the cheering drown it: this was a symptom. Whatever tore the Veil here was reaching from far off, and the epicentre lies across the eastern mountain pass, in the barren wastes. When you are ready, that is where we go.",
		"steps": [
			{"type": "zone", "key": "sepulcher_of_mourning", "text": "Go through the great door into the Sepulcher of Mourning"},
			{"type": "kill_boss", "key": "lord_malaphax", "text": "Slay Lord Malaphax, the Flesh-Torn"},
			{"type": "use", "key": "rift_scar", "text": "Look into the torn rift behind the altar"},
		],
		"rewards": {"xp": 3000, "orbs": {"augment": 9, "alchemy": 4, "chaos": 3}, "passive_points": 2, "attr_points": 4,
			"item": {"slot": "", "rarity": 2},
			"notes": ["Act I is complete: the road east, over the mountain pass to the wastes, awaits in Act II"]},
	},
	"a1_restless_ancestors": {
		"name": "Restless Ancestors", "act": 1, "kind": "side", "giver": "ancestor_spirit", "turn_in": "ancestor_spirit",
		"summary": "A weeping spirit in the Grand Ossuary asks you to recover four desecrated burial urns from the crypt's sarcophagi and set them back on their sanctified pedestal.",
		"offer": "Oh. You can see me. Please: do not run. They broke the sarcophagi and took our urns, four of them, and without them we cannot rest. They lie in the old tomb-halls of this level, in the open sarcophagi. Bring them back to the pedestal beside me, and I will give you what blessing the dead can: a ward that stays.",
		"progress": "Four urns, in the open sarcophagi of the tomb-halls on this level. Set them on the pedestal here, beside me.",
		"complete": "Quiet. Do you hear it? Nothing. Nothing at all. Thank you. Take what the dead can give: a ward that will not leave you.",
		"steps": [
			{"type": "use", "key": "urn", "count": 4, "text": "Recover the desecrated burial urns from the sarcophagi"},
			{"type": "use", "key": "urn_pedestal", "text": "Set the urns on their sanctified pedestal"},
		],
		"rewards": {"xp": 540, "orbs": {"augment": 2, "alchemy": 1}, "bonus": {"res_all": 0.05}},
	},
	"a1_taste_for_rot": {
		"name": "A Taste for Rot", "act": 1, "kind": "side", "giver": "voss", "turn_in": "voss",
		"summary": "Apothecary Voss, cast out of Oakhaven, hides in a hovel in the Sunken Fen. He needs the glands of three Fen Crawlers for a mutagenic draught.",
		"offer": "You've the look of someone who doesn't ask what a man brews. Good. I need the glands of three [b]Fen Crawlers[/b], fresh, out of the mire round here. Bring them and I'll make you something Oakhaven's physicians would burn me for: a draught for your body, or a rune from my stores. Your choice.",
		"progress": "Fen Crawlers hunt the mire: pale, long and quick. Three glands, fresh.",
		"complete": "Three glands, and still warm. Beautiful. Now: one thing I can make, or one thing I already have. Which will it be?",
		"steps": [
			{"type": "kill", "key": "fen_crawler", "count": 3, "text": "Harvest the glands of 3 Fen Crawlers"},
		],
		"rewards": {"xp": 300, "choose": [
			{"label": "The draught: +4 attribute points", "attr_points": 4},
			{"label": "A rune from his stores", "skill_rune": 1},
		]},
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
		"rewards": {"xp": 200, "orbs": {"augment": 2}, "gems": {"topaz_2": 1}},
	},
}


static func npc(id: String) -> Dictionary:
	return NPCS.get(id, {"name": id.capitalize(), "title": "", "skin": "", "greeting": "..."})


static func quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})
