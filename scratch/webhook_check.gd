extends Node
## Checks Autharr's account.deleted handling without a real server or Autharr:
##   godot --headless --path . res://scratch/webhook_check.tscn
## Starts a WebhookServer on a free port, posts signed and unsigned notices to it over TCP, and checks
## that only a good one reaches the handler, and that AccountStore.erase removes an account's file and
## its backup copies (and nothing else). Prints "webhook: N checks, M failed".

const SECRET := "check-secret"
var _checks := 0
var _failed := 0
var _erased: Array = []


func _ready() -> void:
	# --- the account store ---
	var dir := OS.get_temp_dir().path_join("tainted_webhook_check_%d" % Time.get_ticks_usec())
	var store := AccountStore.new(dir)
	var gone := "a" + "11111111-1111-1111-1111-111111111111"
	var kept := "a" + "22222222-2222-2222-2222-222222222222"
	for acc in [gone, kept]:
		store.put(acc, "account", {"characters": [], "shared": {}, "stash": []})
	store.flush(true)
	DirAccess.make_dir_recursive_absolute(dir + "/backups/2026-11-04")
	for acc in [gone, kept]:
		DirAccess.copy_absolute("%s/accounts/%s.json" % [dir, acc], "%s/backups/2026-11-04/%s.json" % [dir, acc])
	_check(FileAccess.file_exists("%s/accounts/%s.json" % [dir, gone]), "an account is written")
	_check(store.erase(gone), "erase says it found something")
	_check(not FileAccess.file_exists("%s/accounts/%s.json" % [dir, gone]), "its file is gone")
	_check(not FileAccess.file_exists("%s/backups/2026-11-04/%s.json" % [dir, gone]), "and its backup copy")
	_check(store.files(gone).is_empty(), "and nothing is held in memory")
	_check(FileAccess.file_exists("%s/accounts/%s.json" % [dir, kept]), "another account's file stays")
	_check(FileAccess.file_exists("%s/backups/2026-11-04/%s.json" % [dir, kept]), "and its backup copy")
	_check(not store.erase(gone), "a second erase finds nothing")
	for bad in ["", "d" + "x".repeat(36), "a../../x", "a" + "11111111-1111-1111-1111-11111111111G", "A" + "11111111-1111-1111-1111-111111111111"]:
		_check(not store.erase(bad), "refuses '%s' as an account" % bad.left(20))

	# --- the signature and the notice ---
	var body := "{}".to_utf8_buffer()
	var sig := "sha256=" + Crypto.new().hmac_digest(HashingContext.HASH_SHA256, SECRET.to_utf8_buffer(), body).hex_encode()
	_check(WebhookServer.signature_ok(body, sig, SECRET), "a right signature passes")
	_check(not WebhookServer.signature_ok(body, sig, "other"), "a wrong secret fails")
	_check(not WebhookServer.signature_ok(body, "", SECRET), "no signature fails")
	_check(not WebhookServer.signature_ok(body, sig, ""), "no secret fails")
	_check(WebhookServer.is_stale({"timestamp": Time.get_unix_time_from_system() - 3600}), "an old notice is stale")
	_check(not WebhookServer.is_stale({"timestamp": Time.get_unix_time_from_system()}), "a new one is not")
	_check(WebhookServer.is_guid("c073f696-4d68-42a3-874b-c62bcdd7d07b"), "a GUID is one")
	_check(not WebhookServer.is_guid("1' OR '1'='1"), "an injection is not")

	# --- over TCP ---
	var server := WebhookServer.new()
	var port := 24700 + randi() % 200
	_check(not WebhookServer.new().start(port, "", func(_s): pass), "it will not start without a secret")
	_check(server.start(port, SECRET, func(s): _erased.append(s)), "it starts on port %d" % port)
	var sub := "c073f696-4d68-42a3-874b-c62bcdd7d07b"
	var now := int(Time.get_unix_time_from_system())
	var good := JSON.stringify({"event": "account.deleted", "sub": sub, "ent_v": 0, "timestamp": now})
	_check(await _post(server, good, _sign(good)) == 200, "a signed notice is accepted")
	_check(_erased == [sub], "and reaches the handler once, with the subject")
	_check(await _post(server, good, "") == 401, "an unsigned one is refused")
	_check(await _post(server, good, "sha256=" + "0".repeat(64)) == 401, "a badly signed one is refused")
	var stale := JSON.stringify({"event": "account.deleted", "sub": sub, "timestamp": now - 3600})
	_check(await _post(server, stale, _sign(stale)) == 200, "a replayed one is answered")
	var other := JSON.stringify({"event": "entitlements.changed", "sub": sub, "timestamp": now})
	_check(await _post(server, other, _sign(other)) == 200, "another event is answered")
	var bad := JSON.stringify({"event": "account.deleted", "sub": "1' OR '1'='1", "timestamp": now})
	_check(await _post(server, bad, _sign(bad)) == 400, "a notice naming no account is refused")
	_check(_erased == [sub], "none of those reached the handler")

	DirAccess.remove_absolute(dir)  # best effort: the temp folder is harmless if it stays
	print("webhook: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _sign(body: String) -> String:
	return "sha256=" + Crypto.new().hmac_digest(HashingContext.HASH_SHA256, SECRET.to_utf8_buffer(), body.to_utf8_buffer()).hex_encode()


## Posts `body` to the server and returns the HTTP status it answered (polling the server as a game would).
func _post(server: WebhookServer, body: String, signature: String) -> int:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", server._tcp.get_local_port())
	var head := "POST /webhooks/autharr HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: %d\r\n%s\r\n" % [
		body.to_utf8_buffer().size(), ("X-Autharr-Signature: %s\r\n" % signature) if signature != "" else ""]
	var sent := false
	var reply := PackedByteArray()
	for i in 200:
		peer.poll()
		server.poll()
		if not sent and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_data((head + body).to_utf8_buffer())
			sent = true
		if sent and peer.get_available_bytes() > 0:
			reply.append_array(peer.get_data(peer.get_available_bytes())[1])
		if reply.get_string_from_utf8().contains("\r\n\r\n"):
			break
		await get_tree().create_timer(0.02).timeout
	peer.disconnect_from_host()
	var line := reply.get_string_from_utf8().get_slice("\r\n", 0)  # "HTTP/1.1 200 OK"
	return int(line.get_slice(" ", 1)) if line != "" else 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok:   " if ok else "FAIL: ") + what)
	if not ok:
		_failed += 1
