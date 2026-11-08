class_name PartyScale
extends RefCounted
## Diablo II's "Players X": the more players in the same area, the tougher its monsters and the richer what they
## give. The count is everyone standing in this instance (you and the RemotePlayers in the scene), so a party member
## who is in town doesn't make the fight harder, and it moves as people arrive and leave.
##   life  - monsters take this much more to kill. Done when they are hit (Enemy.take_damage), not by growing their
##           life, so a monster's life bar and what the host sends the party stay as they were.
##   xp    - experience for each kill, for every player.
##   drops - the chance of a drop and of its being better; a rift's horde loot counts this many more kills.
## Each extra player adds these to 1 (alone: all 1).

const LIFE_PER_EXTRA := 0.6
const XP_PER_EXTRA := 0.35
const DROPS_PER_EXTRA := 0.25


## Players in this area: you and the other players here.
static func size() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1
	return 1 + tree.get_nodes_in_group("remote_players").size()


static func life() -> float:
	return 1.0 + LIFE_PER_EXTRA * (size() - 1)


static func xp() -> float:
	return 1.0 + XP_PER_EXTRA * (size() - 1)


static func drops() -> float:
	return 1.0 + DROPS_PER_EXTRA * (size() - 1)


## "Monsters +120% life  •  +70% XP  •  +50% drops" for the party list; "" alone.
static func summary() -> String:
	if size() <= 1:
		return ""
	return "Monsters +%d%% life  •  +%d%% XP  •  +%d%% drops" % [
		int(round((life() - 1.0) * 100.0)), int(round((xp() - 1.0) * 100.0)), int(round((drops() - 1.0) * 100.0))]
