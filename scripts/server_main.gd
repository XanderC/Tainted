extends Node
## The dedicated server's scene (Net starts the server; see Net.dedicated_requested). It has no
## world of its own: it reports who is online when that changes, and takes admin commands
## (ServerAdmin) if started with --admin=<dir>.

var _last := -1


func _ready() -> void:
	if Net.admin_dir != "":
		var admin := ServerAdmin.new()
		admin.dir = Net.admin_dir
		add_child(admin)


func _process(_delta: float) -> void:
	var n := Net.player_count()
	if n != _last:
		_last = n
		var where := {}
		for id in Net._peers:
			var inst: String = Net._peers[id].instance
			where[inst] = int(where.get(inst, 0)) + 1
		Net.log_line("Online: %d %s" % [n, where])
