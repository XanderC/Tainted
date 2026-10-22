class_name Moderation
extends RefCounted
## The server's bans and mutes, by account (an Autharr sign-in "a...", or a device "d..."): kept in
## <data dir>/moderation.json, or only in memory on a server without --data. The server's admin
## commands change them (ServerAdmin); Net refuses a banned account's hello and a muted one's chat.

var path := ""
var bans := {}   # account -> {"name", "reason", "at": unix seconds}
var mutes := {}  # account -> {"name", "until": unix seconds, 0 until unmuted}


func _init(dir := "") -> void:
	if dir == "":
		return
	path = dir.trim_suffix("/") + "/moderation.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			bans = d.bans if d.get("bans") is Dictionary else {}
			mutes = d.mutes if d.get("mutes") is Dictionary else {}


func is_banned(account: String) -> bool:
	return account != "" and bans.has(account)


func ban_reason(account: String) -> String:
	return String(bans.get(account, {}).get("reason", ""))


func ban(account: String, name: String, reason: String) -> void:
	bans[account] = {"name": name, "reason": reason, "at": int(Time.get_unix_time_from_system())}
	_save()


func unban(account: String) -> bool:
	var had := bans.erase(account)
	if had:
		_save()
	return had


## Seconds of mute left: 0 not muted, -1 muted until unmuted.
func mute_left(account: String) -> int:
	if account == "" or not mutes.has(account):
		return 0
	var until := int(mutes[account].get("until", 0))
	if until == 0:
		return -1
	var left := until - int(Time.get_unix_time_from_system())
	if left <= 0:
		mutes.erase(account)
		_save()
		return 0
	return left


## Mutes `account` for `minutes` (0: until unmuted).
func mute(account: String, name: String, minutes: int) -> void:
	var until := 0 if minutes <= 0 else int(Time.get_unix_time_from_system()) + minutes * 60
	mutes[account] = {"name": name, "until": until}
	_save()


func unmute(account: String) -> bool:
	var had := mutes.erase(account)
	if had:
		_save()
	return had


## The account in `list` (bans or mutes) that `who` names: the account itself, or the name it was
## banned or muted under (any case). "" if none.
static func find_in(list: Dictionary, who: String) -> String:
	if list.has(who):
		return who
	for account in list:
		if String(list[account].get("name", "")).to_lower() == who.to_lower():
			return String(account)
	return ""


func _save() -> void:
	if path == "":
		return
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Moderation: can't write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify({"bans": bans, "mutes": mutes}, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, path)
