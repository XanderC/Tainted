extends SceneTree
## Checks the public addresses from a Godot game (its own HTTP and WebSocket clients, as a phone uses):
## a wrong sign-in at Autharr (expect 400: reached Autharr, not a Cloudflare challenge), and a
## WebSocket to the Tainted World (expect it to open).
##   godot --headless --path . -s res://scratch/check_public.gd


func _init() -> void:
	var http := HTTPRequest.new()
	get_root().add_child.call_deferred(http)
	await process_frame
	http.request("https://auth.xandflix.uk/connect/token", ["Content-Type: application/x-www-form-urlencoded"],
		HTTPClient.METHOD_POST, "grant_type=password&client_id=tainted-game&username=nobody&password=wrong")
	var r = await http.request_completed
	print("auth: result %d, HTTP %d, %s" % [r[0], r[1], r[3].get_string_from_utf8().left(120)])
	var ws := WebSocketPeer.new()
	ws.connect_to_url("wss://tainted.xandflix.uk")
	var t := 0.0
	while t < 10.0:
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN or st == WebSocketPeer.STATE_CLOSED:
			break
		await create_timer(0.1).timeout
		t += 0.1
	print("world: state %d (1 = open, 3 = closed), close code %d" % [ws.get_ready_state(), ws.get_close_code()])
	quit()
