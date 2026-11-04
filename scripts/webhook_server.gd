class_name WebhookServer
extends RefCounted
## Receives Autharr's signed notices (a tiny HTTP listener, on the estate's private network only: nothing
## publishes this port). The one that matters is `account.deleted`: a player deleted their account, here
## or in another app, so what the server keeps about them goes (`handler` is called with their Autharr
## subject). Each notice is signed with HMAC-SHA256 over its exact body (`X-Autharr-Signature:
## sha256=<hex>`) using the secret on Tainted's application record in Autharr; anything unsigned, stale
## or malformed is refused, because this can erase a player's characters.
##
## Call poll() every frame. It speaks just enough HTTP for Autharr's POST: one request per connection.

const MAX_BODY := 16 * 1024
const MAX_CONNECTIONS := 8
const TIMEOUT_MSEC := 5000
const STALE_SECONDS := 300

var _tcp := TCPServer.new()
var _secret := ""
var _handler: Callable
var _conns: Array = []  # {"peer": StreamPeerTCP, "buf": PackedByteArray, "since": msec}


## Starts listening on `port`; false if it can't (or there is no secret: refusing beats accepting unsigned notices).
func start(port: int, secret: String, handler: Callable) -> bool:
	if secret == "":
		return false
	_secret = secret
	_handler = handler
	return _tcp.listen(port) == OK


func poll() -> void:
	if not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
		else:
			_conns.append({"peer": peer, "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	var now := Time.get_ticks_msec()
	for c in _conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or now - int(c.since) > TIMEOUT_MSEC:
			peer.disconnect_from_host()
			_conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			c.buf.append_array(peer.get_data(n)[1])
		if c.buf.size() > MAX_BODY + 4096:
			_reply(c, 413, "too large")
			continue
		var done := _try_request(c.buf)
		if done.is_empty():
			continue
		if done.get("bad", false):
			_reply(c, 413, "too large")
			continue
		var status := _handle(done.headers, done.body)
		_reply(c, status, "ok" if status == 200 else "refused")


func _reply(c: Dictionary, status: int, text: String) -> void:
	var peer: StreamPeerTCP = c.peer
	var reason: String = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 413: "Payload Too Large", 503: "Service Unavailable"}.get(status, "Error")
	var body := ('{"ok":%s}' % ("true" if status == 200 else "false")).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
	_conns.erase(c)


## {"headers": {lowercase name: value}, "body": PackedByteArray} once a whole request has arrived, else {}.
static func _try_request(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var split := text.find("\r\n\r\n")
	if split < 0:
		return {}
	var headers := {}
	var lines := text.substr(0, split).split("\r\n")
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var head_bytes := text.substr(0, split + 4).to_utf8_buffer().size()
	var want := int(headers.get("content-length", "0"))
	if want < 0 or want > MAX_BODY:
		return {"headers": headers, "body": PackedByteArray(), "bad": true}
	if buf.size() - head_bytes < want:
		return {}
	return {"headers": headers, "body": buf.slice(head_bytes, head_bytes + want)}


func _handle(headers: Dictionary, body: PackedByteArray) -> int:
	if _secret == "":
		return 503
	if not signature_ok(body, String(headers.get("x-autharr-signature", "")), _secret):
		return 401
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary or not is_guid(String(d.get("sub", ""))):
		return 400
	if is_stale(d):
		return 200  # a replayed notice: signed, but too old to act on
	if String(d.get("event", "")).to_lower() == "account.deleted":
		_handler.call(String(d.sub).to_lower())
	return 200


## Whether `header` ("sha256=<hex>") is the HMAC-SHA256 of `body` under `secret`, compared in constant time.
static func signature_ok(body: PackedByteArray, header: String, secret: String) -> bool:
	if secret == "" or header == "":
		return false
	var given := header.strip_edges().to_lower().trim_prefix("sha256=")
	var want := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret.to_utf8_buffer(), body).hex_encode()
	if given.length() != want.length():
		return false
	var diff := 0
	for i in want.length():
		diff |= given.unicode_at(i) ^ want.unicode_at(i)
	return diff == 0


static func is_stale(notice: Dictionary, now_seconds := Time.get_unix_time_from_system()) -> bool:
	var t = notice.get("timestamp", 0)
	return (t is int or t is float) and float(t) > 0.0 and now_seconds - float(t) > STALE_SECONDS


static func is_guid(s: String) -> bool:
	if s.length() != 36:
		return false
	for i in s.length():
		var ch := s.unicode_at(i)
		if i in [8, 13, 18, 23]:
			if ch != 45:
				return false
		elif not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102) or (ch >= 65 and ch <= 70)):
			return false
	return true
