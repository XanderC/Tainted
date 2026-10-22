extends Node
## The dedicated server's scene (Net starts the server; see Net.dedicated_requested). It has no
## world of its own: it just reports who is online now and then.

var _last := -1


func _process(_delta: float) -> void:
	var n := Net.player_count()
	if n != _last:
		_last = n
		var where := {}
		for id in Net._peers:
			var inst: String = Net._peers[id].instance
			where[inst] = int(where.get(inst, 0)) + 1
		print("Server: %d online %s" % [n, where])
