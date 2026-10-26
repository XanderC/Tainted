extends Node
## Updates the game without reinstalling it: the installed app (the APK, the exe) stays, and a patch
## pack of just the files changed since that release is downloaded from the Tainted World and loaded
## over it at startup. The first autoload, so the patch is in place before any other script loads.
##
## Builds are numbered (res://build.json, stamped by publish_builds.ps1 and publish_update.ps1). A full
## release (publish_builds.ps1) is a base; publish_update.ps1 exports a patch per platform against it
## and the server offers it (server: serve_from):
##   client                                server
##   connects, then before its hello:
##     {"upd": "check", build, app, plat}  ->  "ok" (up to date, or nothing that fits: play on), or
##                                         <-  {"upd": "offer", build, base, size, sha256}
##     {"upd": "get", o} ...               ->  {"upd": "data", o, b} ... (CHUNK at a time)
##   checks the hash, saves user://update/patch_<build>.pck and patch.json, and restarts.
## These go as raw packets (multiplayer.send_bytes), not RPCs: an update may change the game's RPCs,
## and a game must still be able to fetch it from a server that has changed them.
## A patch fits an app at least as new as its base; an app newer than the patch drops it. Only an
## exported game (feature "template") updates; runs from the editor never load or fetch a patch (but
## --update-test on the command line makes one act as if exported: scratch/test_update.sh).
## What a patch can't change: the engine, export settings (icons, permissions), project settings and
## the autoload list. Those need a full release.
##
## On Android the APK holds just this script, build.json and the game as one pack (GAME_PACK, the
## "Android Data" preset), which this loads first. Godot reads the files of an APK one by one through
## Android's asset manager, and the first pack loaded at runtime makes it list every one of them: with
## the whole game loose in the APK that took a phone a minute and a half before a patch could load.
## (The .mp4 name keeps the exporter from compressing it, so it can be read anywhere in it at once.)
## This script reaches Net by its node path (_net), not its name: naming an autoload compiles its
## script along with this one, before the game pack, or a patch with a newer one, is loaded.

const GAME_PACK := "res://pack/game.mp4"
const DIR := "user://update/"
const META := DIR + "patch.json"
const LOG := DIR + "updater.log"  # what the last start did (note), for a game that won't start
const CHUNK := 128 * 1024
const CHECK_TIMEOUT := 6.0  # seconds to wait for a server's answer before saying hello anyway (an older server)

## The installed app's build, and the build running (the patch's when one is loaded)
var app_build := 0
var build := 0
var patched := false
var _test := false  # --update-test: a run from the editor acting as an exported game

# Client: asking, then downloading
var _checking := false
var _dl := {}  # {build, base, size, sha256, path, file: FileAccess, got}
# Server: what it offers ({} for nothing): {build, base, dir, files: {plat: {file, size, sha256}}}
var _offer := {}


func _init() -> void:
	_test = "--update-test" in OS.get_cmdline_user_args()
	app_build = _read_build()
	build = app_build
	if not _enabled():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var log := FileAccess.open(LOG, FileAccess.WRITE)  # (a new log each start)
	if log != null:
		log.close()
	note("start: app build %d on %s" % [app_build, platform()])
	if OS.has_feature("template") and FileAccess.file_exists(GAME_PACK):
		note("loading the game pack")
		if not ProjectSettings.load_resource_pack(GAME_PACK, true):
			note("the game pack didn't load")
	var meta := _read_json(META)
	var path := DIR + String(meta.get("file", ""))
	var pb := int(meta.get("build", 0))
	if pb > app_build and int(meta.get("base", 0)) <= app_build and FileAccess.file_exists(path):
		note("loading patch %s (build %d)" % [path, pb])
		if ProjectSettings.load_resource_pack(path, true):
			build = pb
			patched = true
		note("patch loaded: %s" % patched)
	elif not meta.is_empty():
		note("dropping patch build %d (base %d)" % [pb, int(meta.get("base", 0))])
		_clear()  # the app is as new as the patch (a new install), or the patch doesn't fit it
	_tidy()
	note("ready to start")


## A line in this start's log (user://update/updater.log): each step of a start, so a game that stops
## partway shows where.
func note(text: String) -> void:
	if not _enabled():
		return
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%d %s" % [Time.get_ticks_msec(), text])
	f.close()


## Net (see the header).
func _net():
	return get_node("/root/Net")


func _enabled() -> bool:
	return OS.has_feature("template") or _test


static func _read_build() -> int:
	var res = load("res://build.json") if ResourceLoader.exists("res://build.json") else null
	return int(res.data.get("build", 0)) if res != null and res.data is Dictionary else 0


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("windows"):
		return "windows"
	return ""


## Patch files no longer in use (the one before the last update, a half-finished download).
func _tidy() -> void:
	var keep := String(_read_json(META).get("file", ""))
	for f in DirAccess.get_files_at(DIR):
		if f != "patch.json" and f != keep and f != "updater.log":
			DirAccess.remove_absolute(DIR + f)


func _clear() -> void:
	DirAccess.remove_absolute(META)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_packet.connect(_on_packet)
	note("autoloads ready")


# ---------- client ----------

## Called once connected, before the hello: true if it is asking the server for an update (Net says
## hello when it's done, through Net.send_hello).
func begin_check() -> bool:
	if not _enabled() or build <= 0 or platform() == "":
		return false
	_checking = true
	_send(1, {"upd": "check", "build": build, "app": app_build, "plat": platform()})
	get_tree().create_timer(CHECK_TIMEOUT, true, false, true).timeout.connect(func():
		if _checking:  # no answer: a server from before updates
			_checking = false
			_net().send_hello())
	return true


func _client_packet(m: Dictionary) -> void:
	match String(m.get("upd", "")):
		"ok":
			if _checking:
				_checking = false
				_net().send_hello()
		"offer":
			if _checking:
				_checking = false
				_start_download(m)
		"data":
			_got_data(m)


func _start_download(m: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var nb := int(m.get("build", 0))
	var path := DIR + "patch_%d.part" % nb
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null or int(m.get("size", 0)) <= 0:
		_net().send_hello()
		return
	_dl = {"build": nb, "base": int(m.get("base", 0)), "size": int(m.get("size", 0)), "sha256": String(m.get("sha256", "")),
		"path": path, "file": f, "got": 0}
	_progress()
	_send(1, {"upd": "get", "o": 0, "plat": platform()})


func _got_data(m: Dictionary) -> void:
	if _dl.is_empty() or int(m.get("o", -1)) != int(_dl.got) or not m.get("b") is PackedByteArray:
		return
	var b: PackedByteArray = m.b
	(_dl.file as FileAccess).store_buffer(b)
	_dl.got = int(_dl.got) + b.size()
	_progress()
	if int(_dl.got) < int(_dl.size):
		_send(1, {"upd": "get", "o": int(_dl.got), "plat": platform()})
	else:
		_finish()


func _progress() -> void:
	var pct := int(100.0 * float(_dl.got) / maxf(float(_dl.size), 1.0))
	_net().update_status("Downloading an update... %d%%  (%.1f of %.1f MB)" % [pct,
		float(_dl.got) / 1048576.0, float(_dl.size) / 1048576.0])


func _finish() -> void:
	(_dl.file as FileAccess).close()
	var path: String = _dl.path
	var ok := FileAccess.get_sha256(path) == String(_dl.sha256)
	if not ok:
		DirAccess.remove_absolute(path)
		_dl = {}
		_net().leave()
		_net().update_status("The update didn't download properly: try again.", true)
		return
	var name := "patch_%d.pck" % int(_dl.build)
	DirAccess.rename_absolute(path, DIR + name)
	var f := FileAccess.open(META, FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": int(_dl.build), "base": int(_dl.base), "file": name}))
	f.close()
	_dl = {}
	_net().leave()
	_net().update_status("Update installed. Restarting...")
	await get_tree().create_timer(1.0, true, false, true).timeout
	_restart()


## Starts the game again, now with the patch: a PC relaunches itself; a phone reopens the app (or, if
## it can't, asks the player to).
func _restart() -> void:
	if _test:
		print("UPDATED to build %d" % int(_read_json(META).get("build", 0)))
		get_tree().quit()
		return
	if OS.has_feature("android"):
		if _android_relaunch():
			OS.kill(OS.get_process_id())  # (now: the app opens again in a new process)
			return
		_net().update_status("The update is installed: close the game and open it again.", true)
		await get_tree().create_timer(4.0, true, false, true).timeout
		get_tree().quit()
		return
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


## Asks Android to open the app again, which it does once this process has ended: the engine can't
## start a second time in the same process (quitting first leaves it running, and the app crashed).
func _android_relaunch() -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	if activity == null:
		return false
	var intent = activity.getPackageManager().getLaunchIntentForPackage(activity.getPackageName())
	if intent == null:
		return false
	intent.addFlags(0x10000000 | 0x00008000)  # FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK
	activity.startActivity(intent)
	return true


# ---------- server ----------

## Offers the patches in `dir` (its update.json, written by publish_update.ps1) to games older than
## this server's build that they fit.
func serve_from(dir: String) -> void:
	var meta := _read_json(dir.path_join("update.json"))
	if meta.is_empty():
		return
	meta["dir"] = dir
	_offer = meta
	print("Updates: offering build %d (fits apps from build %d) for %s" % [int(meta.get("build", 0)), int(meta.get("base", 0)),
		", ".join(PackedStringArray((meta.get("files", {}) as Dictionary).keys()))])


func _server_packet(id: int, m: Dictionary) -> void:
	match String(m.get("upd", "")):
		"check":
			var file := _offer_for(m)
			if file.is_empty():
				_send(id, {"upd": "ok"})
				return
			_net().hold_for_update(id)
			_send(id, {"upd": "offer", "build": int(_offer.build), "base": int(_offer.base), "size": int(file.size),
				"sha256": String(file.sha256)})
			_net().log_line("Offering update %d to a game on build %d (%s)" % [int(_offer.build), int(m.get("build", 0)), String(m.get("plat", ""))])
		"get":
			var file := _offer_for(m, true)
			var o := int(m.get("o", -1))
			if file.is_empty() or o < 0 or o >= int(file.size):
				return
			var f := FileAccess.open(String(_offer.dir).path_join(String(file.file)), FileAccess.READ)
			if f == null:
				return
			f.seek(o)
			_net().hold_for_update(id)
			_send(id, {"upd": "data", "o": o, "b": f.get_buffer(mini(CHUNK, int(file.size) - o))})


## The patch file for the game asking ({} if none fits): it is older than the patch, its app at least
## as new as the patch's base, and there is one for its platform. (`any`: for a chunk, whose request
## carries only the offset: the platform it was offered.)
func _offer_for(m: Dictionary, any := false) -> Dictionary:
	if _offer.is_empty() or int(_offer.get("build", 0)) != app_build:
		return {}  # (a patch for another build than the server's: published but not deployed together)
	var files: Dictionary = _offer.get("files", {})
	if any:
		var plat := String(m.get("plat", ""))
		return files.get(plat, {}) if plat != "" else {}
	if int(m.get("build", 0)) >= int(_offer.build) or int(m.get("app", 0)) < int(_offer.get("base", 0)):
		return {}
	return files.get(String(m.get("plat", "")), {})


# ---------- both ----------

func _send(id: int, m: Dictionary) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.send_bytes(var_to_bytes(m), id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _on_packet(id: int, bytes: PackedByteArray) -> void:
	var m = bytes_to_var(bytes)  # (no objects: bytes_to_var never decodes them)
	if not m is Dictionary or not m.has("upd"):
		return
	if _net().is_server():
		_server_packet(id, m)
	elif id == 1:
		_client_packet(m)
