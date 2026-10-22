class_name AccountStore
extends RefCounted
## The Tainted World's characters (a dedicated server started with --data=<dir>): each account's save
## "files" (GameState's account file and one per character, by virtual path: "account",
## "characters/<id>"), kept in one JSON file per account under <dir>/accounts, written atomically (a
## temporary file, then renamed) a moment after a change and when the player goes. Every file a game
## sends is checked first (check()): its path, its size and its shape. Once a day every account is
## copied to <dir>/backups/<date>, and the last BACKUP_DAYS days are kept.

const FLUSH_AFTER := 2.0  ## seconds after a change before the account is written to disk
const MAX_FILE_BYTES := 512 * 1024
const MAX_CHARACTERS := 8  ## GameState.MAX_CHARACTERS
const MAX_LEVEL := 100
const BACKUP_DAYS := 7

var base_dir := ""
var _accounts := {}  # account id -> {"files": {vpath: data}, "dirty_at": msec or -1}


func _init(dir: String) -> void:
	base_dir = dir.trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(base_dir + "/accounts")


## An account's files (loaded on first use), as {vpath: data}.
func files(account: String) -> Dictionary:
	return _rec(account).files


## Stores file `vpath` for `account`, if check() passes; returns why not ("" when stored).
func put(account: String, vpath: String, data: Variant) -> String:
	var why := check(vpath, data)
	if why != "":
		return why
	var rec := _rec(account)
	rec.files[vpath] = data
	_mark(rec)
	return ""


func remove(account: String, vpath: String) -> void:
	if not vpath.begins_with("characters/"):
		return
	var rec := _rec(account)
	if rec.files.erase(vpath):
		_mark(rec)


## Writes accounts changed more than FLUSH_AFTER seconds ago (or all changed ones, `now_all`), and
## makes the day's backup if it isn't made yet.
func flush(now_all := false) -> void:
	_backup_daily()
	var now := Time.get_ticks_msec()
	for account in _accounts:
		var rec: Dictionary = _accounts[account]
		if int(rec.dirty_at) >= 0 and (now_all or now - int(rec.dirty_at) > FLUSH_AFTER * 1000.0):
			_write(account, rec.files)
			rec.dirty_at = -1


## Writes one account now (it's leaving).
func flush_account(account: String) -> void:
	if _accounts.has(account) and int(_accounts[account].dirty_at) >= 0:
		_write(account, _accounts[account].files)
		_accounts[account].dirty_at = -1


## Why file `data` can't be stored at `vpath`, or "" if it can: only the account file and character
## files, plain dictionaries of a sane size and shape.
static func check(vpath: String, data: Variant) -> String:
	if not data is Dictionary:
		return "not a dictionary"
	var size := JSON.stringify(data).length()
	if size > MAX_FILE_BYTES:
		return "too big (%d bytes)" % size
	if vpath == "account":
		var chars = data.get("characters", [])
		if not chars is Array or chars.size() > MAX_CHARACTERS:
			return "bad character list"
		for c in chars:
			if not c is Dictionary or not _is_char_id(String(c.get("id", ""))):
				return "bad character in the list"
		if not data.get("shared", {}) is Dictionary or not data.get("stash", []) is Array:
			return "bad shared stash"
		return ""
	if vpath.begins_with("characters/"):
		if not _is_char_id(vpath.trim_prefix("characters/")):
			return "bad character id"
		var lvl = data.get("level", 1)
		if not (lvl is int or lvl is float) or int(lvl) < 1 or int(lvl) > MAX_LEVEL:
			return "bad level"
		if not data.get("inventory", []) is Array or not data.get("equipment", {}) is Dictionary:
			return "bad items"
		return ""
	return "unknown file"


static func _is_char_id(id: String) -> bool:
	if id.is_empty() or id.length() > 40:
		return false
	for ch in id:
		if not (ch >= "a" and ch <= "z") and not (ch >= "0" and ch <= "9") and ch != "_":
			return false
	return true


## Today's copy of every account, once; days older than BACKUP_DAYS are deleted.
func _backup_daily() -> void:
	var day := Time.get_date_string_from_system(true)
	var dir := "%s/backups/%s" % [base_dir, day]
	if DirAccess.dir_exists_absolute(dir):
		return
	var files_now := Array(DirAccess.get_files_at(base_dir + "/accounts")).filter(func(f): return f.ends_with(".json"))
	if files_now.is_empty():
		return  # nothing to keep yet: the day's copy waits until there is
	DirAccess.make_dir_recursive_absolute(dir)
	for f in files_now:
		DirAccess.copy_absolute("%s/accounts/%s" % [base_dir, f], "%s/%s" % [dir, f])
	var days := DirAccess.get_directories_at(base_dir + "/backups")
	days.sort()
	for i in maxi(days.size() - BACKUP_DAYS, 0):
		var old := "%s/backups/%s" % [base_dir, days[i]]
		for f in DirAccess.get_files_at(old):
			DirAccess.remove_absolute("%s/%s" % [old, f])
		DirAccess.remove_absolute(old)


func _rec(account: String) -> Dictionary:
	if not _accounts.has(account):
		var loaded := {}
		var path := _path(account)
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary and d.get("files") is Dictionary:
				loaded = d.files
		_accounts[account] = {"files": loaded, "dirty_at": -1}
	return _accounts[account]


func _mark(rec: Dictionary) -> void:
	if int(rec.dirty_at) < 0:
		rec.dirty_at = Time.get_ticks_msec()


func _path(account: String) -> String:
	return "%s/accounts/%s.json" % [base_dir, account]


func _write(account: String, files_: Dictionary) -> void:
	var path := _path(account)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("AccountStore: can't write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify({"version": 1, "files": files_}))
	f.close()
	DirAccess.rename_absolute(tmp, path)
