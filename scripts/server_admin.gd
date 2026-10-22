class_name ServerAdmin
extends Node
## A dedicated server's admin commands (server_main adds it when started with --admin=<dir>). A
## command is a one-line file <dir>/<id>.cmd; the answer goes to <dir>/<id>.out. The image's
## tainted-admin script does both, so on the host:  docker exec tainted tainted-admin <command>
## Commands: help, status, kick, ban, unban, bans, mute, unmute, mutes, say, save, shutdown.
## A player is named by their name (any case, while online) or their account ("a..." / "d...").

const HELP := """Commands (a player: their name while online, or their account):
  status                      who is online, where, and the server's state
  kick <player> [reason]      sends them away (they can come back)
  ban <player> [reason]       sends them away and keeps their account out
  unban <player>              lets them back (name or account, as listed by bans)
  bans                        who is banned
  mute <player> [minutes]     no chat for them (60 minutes; 0: until unmuted)
  unmute <player>
  mutes                       who is muted
  say <text>                  a line to everyone online
  save                        writes every account now
  shutdown [seconds]          tells everyone, saves and stops (10 seconds)"""

var dir := ""
var _t := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".cmd"):
			continue
		var path := dir.path_join(f)
		var line := FileAccess.get_file_as_string(path).strip_edges()
		DirAccess.remove_absolute(path)
		var answer := run(line)
		var out := dir.path_join(f.get_basename() + ".out")
		var w := FileAccess.open(out + ".tmp", FileAccess.WRITE)
		if w != null:
			w.store_string(answer + "\n")
			w.close()
			DirAccess.rename_absolute(out + ".tmp", out)


## Runs one command line and says how it went.
func run(line: String) -> String:
	var words := line.split(" ", false)
	if words.is_empty():
		return HELP
	var cmd := words[0].to_lower()
	var who := words[1] if words.size() > 1 else ""
	var rest := " ".join(words.slice(2))
	if cmd != "status" and cmd != "help" and cmd != "bans" and cmd != "mutes":
		Net.log_line("Admin: " + line)
	match cmd:
		"status":
			return _status()
		"kick":
			var id := Net.find_player(who)
			if id == 0:
				return "No one called %s is online." % who
			var name := String(Net._peers[id].info.name)
			Net.kick_player(id, "You were removed from the server." + (" Reason: " + rest if rest != "" else ""))
			return "Kicked %s." % name
		"ban":
			var id := Net.find_player(who)
			var account := String(Net._peers[id].get("account", "")) if id != 0 else who
			var name := String(Net._peers[id].info.name) if id != 0 else ""
			if account == "" or (id == 0 and not (who.begins_with("a") or who.begins_with("d"))):
				return "No one called %s is online (an offline player is banned by account)." % who
			Net.moderation.ban(account, name, rest)
			if id != 0:
				Net.kick_player(id, "You are banned from this server." + (" Reason: " + rest if rest != "" else ""))
			return "Banned %s (%s)." % [name if name != "" else account, account]
		"unban":
			var account := Moderation.find_in(Net.moderation.bans, who)
			if account == "" or not Net.moderation.unban(account):
				return "%s isn't banned." % who
			return "Unbanned %s." % who
		"bans":
			return _list(Net.moderation.bans, func(e): return String(e.get("reason", "")))
		"mute":
			var id := Net.find_player(who)
			if id == 0 or String(Net._peers[id].get("account", "")) == "":
				return "No one called %s is online (with an account)." % who
			var minutes := int(rest) if rest.is_valid_int() else 60
			Net.moderation.mute(String(Net._peers[id].account), String(Net._peers[id].info.name), minutes)
			Net._send(id, "_rpc_notice", ["You are muted." if minutes <= 0 else "You are muted for %d minutes." % minutes])
			return "Muted %s %s." % [Net._peers[id].info.name, "until unmuted" if minutes <= 0 else "for %d minutes" % minutes]
		"unmute":
			var account := Moderation.find_in(Net.moderation.mutes, who)
			if account == "":
				var id := Net.find_player(who)
				account = String(Net._peers[id].get("account", "")) if id != 0 else ""
			if account == "" or not Net.moderation.unmute(account):
				return "%s isn't muted." % who
			return "Unmuted %s." % who
		"mutes":
			return _list(Net.moderation.mutes, func(e):
				var until := int(e.get("until", 0))
				return "until unmuted" if until == 0 else "until " + Time.get_datetime_string_from_unix_time(until, true) + " UTC")
		"say":
			var text := " ".join(words.slice(1))
			if text == "":
				return "Say what?"
			Net.announce(text)
			return "Said to %d online." % Net._peers.size()
		"save":
			Net.save_all()
			return "Every account written."
		"shutdown":
			var secs := float(who) if who.is_valid_float() else 10.0
			Net.shutdown(maxf(secs, 0.0))
			return "Stopping in %d seconds." % int(secs)
	return HELP


func _status() -> String:
	var players := Net.players_online()
	var up := Time.get_ticks_msec() / 1000
	var t := "%s: %d / %d online, up %dh %02dm, protocol %d" % [Net.server_name, players.size(), Net._max_online,
		up / 3600, up / 60 % 60, Net.PROTOCOL]
	t += "\nCharacters kept: %s.  Sign-in: %s.  Parties: %d.  Banned: %d.  Muted: %d." % [
		"yes" if Net._store != null else "no", "Autharr" if Net._auth_check != "" else "none", Net._parties.size(),
		Net.moderation.bans.size(), Net.moderation.mutes.size()]
	for p in players:
		t += "\n  %-24s Lv %-3d %-14s %s%s" % [p.name, p.level, p.where if p.where != "" else "(between places)",
			p.account, "  party %d" % p.party if p.party != 0 else ""]
	return t


func _list(list: Dictionary, detail: Callable) -> String:
	if list.is_empty():
		return "None."
	var t := ""
	for account in list:
		var e: Dictionary = list[account]
		var d := String(detail.call(e))
		t += "%s  %s%s\n" % [account, String(e.get("name", "")), "  (" + d + ")" if d != "" else ""]
	return t.strip_edges()
