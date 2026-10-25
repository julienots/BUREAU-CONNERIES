extends Node
## Headless entry point (dispatched by the boot scene):
##   --master [--port=24680]                    room directory (spawns room servers)
##   --server --port=24681 [--code=ABCD] [--name=X] [--public=1] [--max=9] [--autostart=1]
##   --bot --connect=127.0.0.1:24681 [--botrole=director|employee] [--botname=Bob]


func _ready() -> void:
	if Net.arg("master") != "":
		var port := int(Net.arg("port", str(Net.DEFAULT_PORT)))
		if Net.host(port, 64) != OK:
			push_error("[master] cannot open port %d" % port)
			get_tree().quit(1)
			return
		var link := MasterLink.ensure()
		link.is_master = true
		print("[master] listening on %d" % port)
		return
	if Net.arg("server") != "":
		var port2 := int(Net.arg("port", "24681"))
		if Net.host(port2, Net.MAX_CLIENTS) != OK:
			push_error("[server] cannot open port %d" % port2)
			get_tree().quit(1)
			return
		Net.room_code = Net.arg("code", Net.make_code())
		print("[server] listening on %d code=%s" % [port2, Net.room_code])
		Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
		return
	if Net.arg("bot") != "":
		var addr := Net.arg("connect", "127.0.0.1:24681").split(":")
		Net.join(addr[0], int(addr[1]) if addr.size() > 1 else 24681)
		var on_ok := func():
			print("[bot] connected")
			Game.goto_scene("res://src/gameplay/game_scene.tscn", {"mode": "online"})
		Net.connected.connect(on_ok, CONNECT_ONE_SHOT)
		Net.connection_failed.connect(func():
			print("[bot] connection failed")
			get_tree().quit(2))
		return
	# a headless run without a role: nothing to do
	print("Office Mayhem headless: use --master, --server or --bot")
	get_tree().quit()
