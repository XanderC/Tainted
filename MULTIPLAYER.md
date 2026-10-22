# Multiplayer checklist

What's left to do for multiplayer, in the order it's being done. Tick items as they land (with the
commit). The README's Multiplayer section describes how what's done works.

## Done

- [x] Shared online town; busy towns split into copies of 20
- [x] Parties: invites, leader, party list with life and whereabouts
- [x] Party rifts and story zones together (host runs the monsters, the others follow; host handover)
- [x] Own loot for each player; XP for every kill; monsters' life scaled per player
- [x] Reconnecting by itself; a dropped party member's place kept for a minute
- [x] Online characters kept by the server (checked saves, daily backups)
- [x] Chat (local and party, word filter), inspect, friends, trading (no duplicating)
- [x] Autharr sign-in, required on the Tainted World
- [x] The Tainted World in Docker on the main host, LAN only

## 1. Co-op gameplay gaps

- [x] Elite affixes hit every player, not only the host's (molten ground and death blast, frost orbs,
      teleporting next to its target, electrified sparks); the party sees the orbs and flashes
- [x] Other players' skills visible: the swing arcs, rings, whirlwind's spin, earthquake's ground and
      battle standards their game draws, not only their animation
- [x] Hirelings and summoned Ancients visible to the party (and hirelings in town), fighting in each
      owner's game
- [x] Dying in a party rift or zone: wait to be revived by a party member (or after a while), instead of
      going back to town; a party's rift fails only when everyone is down
- [x] Rift level and unlocks with a party: the opener's level (no higher than they have reached); a
      clear in time unlocks each member's next level; the Rift Gate lists everyone's highest
- [ ] Markers pointing to party members off screen, and "go to" a party member (waypoint / portal)

## 2. Test with real devices

- [ ] Phone and PC together on the Tainted World: sign in, town, party, rift, zone, chat, trade
      (waiting for the phone to be reachable)
- [ ] Load test: 30 bots in town and a few party rifts on the host; server CPU, memory, bandwidth

## 3. Running the server

- [ ] Moderation: kick and ban an account (a file on the server, or Autharr's disable), mute in chat
- [ ] "Update the game" when the versions differ, with where to get the new build
- [ ] Save everything on shutdown (docker stop), checked
- [ ] Off-site backups of /appdata/estate/tainted (now 7 days on the host itself)
- [ ] Logs worth reading: joins, parties, trades, refused saves; a simple status (players online)

## 4. Going public (needs your go-ahead when ready)

- [ ] Traefik route tainted.xandflix.uk and the Cloudflare hostname and allowlist rule
- [ ] Game build with wss://tainted.xandflix.uk and https://auth.xandflix.uk for sign-in
- [ ] Sign-in screen links: create an account, forgot password (Autharr's pages)
- [ ] Per-address connection limits at Traefik / Cloudflare

## 5. Nice to have

- [ ] Currency (orbs) in trades
- [ ] Whispers to friends, chat history you can scroll, muting a player
- [ ] Join a friend where they are (their copy of the town)
- [ ] Bring a device character online once (a copy, checked by the server)
