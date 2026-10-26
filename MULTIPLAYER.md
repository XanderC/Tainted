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
- [x] Online only (22 Oct 2026): no single player, no hosting on the Wi-Fi; the start screen signs in
      and joins, a game that loses the server goes back to it; device characters left unused

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
- [x] Markers pointing to party members off screen, and "go to" a party member (their town, story
      zone or the party's rift, arriving beside them)

## 2. Test with real devices

- [ ] Phone and PC together on the Tainted World: sign in, town, party, rift, zone, chat, trade.
      22 Oct 2026: the phone signs in, makes a character (kept by the server) and gets to town;
      the rest with a PC (a second Autharr account) still to do
- [x] Load test: 30 bots in town and a few party rifts on the host; server CPU, memory, bandwidth.
      22 Oct 2026, a throwaway server with the live one's limits (1 CPU, 512 MB): 35 online at the
      peak (town 20 + town~2 11 + 3 party rifts, every pair's checks passed). Server CPU 7-8.5% of its
      core, memory 143 -> 156 MB, out ~1.3 MB/s (~10 Mbit/s), in ~0.16 MB/s.

## 3. Running the server

- [x] Moderation: kick, ban (by account, kept in moderation.json) and mute, with `docker exec tainted
      tainted-admin <command>`; also say, save, shutdown (scratch/admin_bot: 21 checks)
- [x] "Update the game" when the versions differ, with where to get the new build (the NAS's
      Tainted > builds, filled by publish_builds.ps1)
- [x] Save everything on shutdown (docker stop): players warned, every account written (checked on
      the host: stopped cleanly in 3 s)
- [x] Off-host backups: every night to the NAS (/storage/Tainted/server-backups, 30 days; checked)
- [x] Logs worth reading: dated lines for joins, leaves, refusals, parties, trades, refused saves and
      admin commands; `tainted-admin status` for who is online

## 4. Going public (needs your go-ahead when ready)

- [x] Traefik route tainted.xandflix.uk (estate fde3101, 26 Oct 2026) and the Cloudflare hostname.
      The allowlist and threat-score rules are updated in the estate's apply-cloudflare-rules scripts
      but not yet applied to the zone (needs a Cloudflare API token)
- [x] Game build with wss://tainted.xandflix.uk (tried first, then the home network's address) and
      https://auth.xandflix.uk for sign-in; published 26 Oct 2026
- [x] Updates without reinstalling (publish_update.ps1, Updater): patches fetched from the server.
      Needs one full release (publish_builds.ps1) installed by everyone first
- [ ] Public downloads of the full release: the "update your game" message points at the NAS, which
      only the house reaches (needed now only for a first install and for full releases)
- [x] Sign-in screen links: create an account, forgot password (Autharr's pages at auth.xandflix.uk,
      already public; project setting tainted/net/account_url)
- [x] Per-address connection limits at Traefik: 6 WebSockets per Cloudflare client IP (tainted-connections)
- [x] Town traffic grew with the square of a copy's players (each one's moves to all the others, 15
      times a second; ~10 Mbit/s up at 35 players). Now a player standing still sends nothing, and
      players further than NEAR (1600 px) get each other's moves 3 times a second, not 15. Load
      test with 30 in town, half standing: ~0.85 MB/s out (was ~1.37 MB/s), CPU 6.4% (was ~7.7%)

## 5. Nice to have

- [x] Currency (orbs) in trades: − / + / +10 by each kind, held by the server to what you have
- [x] Whispers (a player's card, a friend's row; "To <name>" in chat, replies to the last), chat
      history you can scroll (100 lines), muting a player's chat (kept with your account)
- [x] Join a friend where they are: Friends > Go to, into their copy of the town (if it has room),
      beside them (their rift or zone is their party's: invite them, or be invited)
