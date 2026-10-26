extends Node
## A game joining a server (--addr=<url>) through the update check: run by scratch/test_update.sh.


func _ready() -> void:
	var addr := "ws://127.0.0.1:24601"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--addr="):
			addr = a.trim_prefix("--addr=")
	print("CLIENT app build %d, running build %d, patched %s" % [Updater.app_build, Updater.build, Updater.patched])
	Net.status_changed.connect(func(): print("STATUS ", Net.status))
	Net.join(addr)
	await get_tree().create_timer(25.0).timeout
	print("TIMEOUT"); get_tree().quit()
